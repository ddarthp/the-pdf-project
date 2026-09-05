import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../viewer/model/pdf_source.dart';
import '../../viewer/services/pdf_picker.dart';
import '../../viewer/ui/password_dialog.dart';
import '../logic/page_operations.dart';
import '../model/page_plan_entry.dart';
import '../services/pdf_page_editor.dart';
import '../../share/services/pdf_export_service.dart';
import '../../share/ui/pdf_export_sheet.dart';
import 'page_range_dialog.dart';
import 'page_tile.dart';

/// Delete, reorder, rotate, merge, split and insert blank pages.
///
/// The screen edits a *plan* — an ordered list of page references — and only
/// touches the file system when the reader saves. The document open in the
/// viewer is never modified: the organiser opens its own copies.
class PageOrganizerScreen extends StatefulWidget {
  const PageOrganizerScreen({
    required this.source,
    this.picker = const PdfPicker(),
    this.exporter = const PdfExportService(),
    super.key,
  });

  final PdfSource source;
  final PdfPicker picker;

  /// Sends the finished PDF to a file, the share sheet or a printer.
  final PdfExportService exporter;

  @override
  State<PageOrganizerScreen> createState() => _PageOrganizerScreenState();
}

class _PageOrganizerScreenState extends State<PageOrganizerScreen> {
  late final PdfPageEditor _editor = PdfPageEditor(passwordProvider: _requestPassword);

  final _sourceNames = <String, String>{};
  final _selection = <int>{};
  final _undoStack = <List<PagePlanEntry>>[];

  List<PagePlanEntry> _plan = const [];
  bool _isBusy = true;
  bool _isSaving = false;
  String? _error;
  int _passwordAttempts = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialSource();
  }

  @override
  void dispose() {
    // Closing the documents is best-effort cleanup; nothing waits on it.
    unawaited(_editor.dispose());
    super.dispose();
  }

  Future<String?> _requestPassword() async {
    if (!mounted) return null;
    final isRetry = _passwordAttempts > 0;
    _passwordAttempts++;
    return showPdfPasswordDialog(
      context,
      fileName: widget.source.displayName,
      isRetry: isRetry,
    );
  }

  Future<void> _loadInitialSource() async {
    try {
      final entries = await _editor.addSource(widget.source);
      if (!mounted) return;
      setState(() {
        _sourceNames[widget.source.key] = widget.source.displayName;
        _plan = entries;
        _isBusy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _isBusy = false;
      });
    }
  }

  // --- plan editing --------------------------------------------------------

  /// Applies a new plan, remembering the old one so [_undo] can put it back.
  void _apply(List<PagePlanEntry> plan, {Set<int>? selection}) {
    setState(() {
      _undoStack.add(_plan);
      _plan = plan;
      _selection
        ..clear()
        ..addAll(selection ?? const <int>{});
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _plan = _undoStack.removeLast();
      _selection.clear();
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (!_selection.remove(index)) _selection.add(index);
    });
  }

  void _selectAllOrNone() {
    setState(() {
      if (_selection.length == _plan.length) {
        _selection.clear();
      } else {
        _selection
          ..clear()
          ..addAll(List.generate(_plan.length, (i) => i));
      }
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    _apply(
      PageOperations.reorder(_plan, oldIndex, newIndex),
      selection: PageOperations.selectionAfterReorder(oldIndex, newIndex, _selection),
    );
  }

  void _deleteSelection() {
    if (_selection.isEmpty) return;
    if (_selection.length == _plan.length) {
      _showMessage('A PDF needs at least one page.');
      return;
    }
    final count = _selection.length;
    _apply(PageOperations.delete(_plan, _selection));
    _showMessage('Removed $count ${count == 1 ? 'page' : 'pages'}.');
  }

  void _rotateSelection(int quarterTurns) {
    if (_selection.isEmpty) return;
    _apply(
      PageOperations.rotate(_plan, _selection, quarterTurns),
      selection: Set.of(_selection),
    );
  }

  void _extractSelection() {
    if (_selection.isEmpty) return;
    final count = _selection.length;
    _apply(PageOperations.extract(_plan, _selection));
    _showMessage('Kept $count ${count == 1 ? 'page' : 'pages'}. Save to write them out.');
  }

  void _insertBlankPage() {
    final at = PageOperations.insertionPointAfter(_plan, _selection);
    final entry = _editor.newBlankEntry(plan: _plan, index: at - 1);
    _apply(PageOperations.insertAll(_plan, at, [entry]), selection: {at});
  }

  Future<void> _mergePdfs() async {
    try {
      final sources = await widget.picker.pickPdfs();
      if (!mounted || sources.isEmpty) return;

      final added = <PagePlanEntry>[];
      for (final source in sources) {
        added.addAll(await _editor.addSource(source));
        _sourceNames[source.key] = source.displayName;
      }
      if (!mounted || added.isEmpty) return;

      _apply(PageOperations.append(_plan, added));
      _showMessage('Added ${added.length} ${added.length == 1 ? 'page' : 'pages'}.');
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not add that PDF: $error');
    }
  }

  Future<void> _selectRange() async {
    final pages = await showPageRangeDialog(context, pageCount: _plan.length);
    if (pages == null || !mounted) return;
    setState(() {
      _selection
        ..clear()
        // The dialog speaks in page numbers; the plan is indexed from zero.
        ..addAll(pages.map((page) => page - 1));
    });
  }

  Future<void> _save() async {
    if (_plan.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final bytes = await _editor.encode(_plan);
      if (!mounted) return;
      final fileName = _suggestedFileName();
      final destination = await showPdfExportSheet(
        context,
        fileName: fileName,
        note: '${_plan.length} ${_plan.length == 1 ? 'page' : 'pages'}',
      );
      if (!mounted || destination == null) return;

      final result = await widget.exporter.run(destination, bytes: bytes, fileName: fileName);
      if (!mounted || !result.completed) return;
      Navigator.of(context).pop(result.savedTo);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not save the PDF: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _suggestedFileName() {
    final name = widget.source.displayName;
    final base = name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
    return '$base-edited.pdf';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- rendering -----------------------------------------------------------

  String _labelFor(PagePlanEntry entry) => switch (entry) {
    BlankPageEntry() => 'Blank page',
    SourcePageEntry(:final sourceId, :final pageNumber) =>
      'Page $pageNumber of ${_sourceNames[sourceId] ?? 'a removed document'}',
  };

  PdfDocument? _documentFor(PagePlanEntry entry) => switch (entry) {
    SourcePageEntry(:final sourceId) => _editor.documentFor(sourceId),
    BlankPageEntry() => null,
  };

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasSelection ? '${_selection.length} selected' : 'Organize pages'),
        actions: [
          if (_undoStack.isNotEmpty)
            IconButton(tooltip: 'Undo', onPressed: _undo, icon: const Icon(Icons.undo)),
          if (hasSelection) ...[
            IconButton(
              tooltip: 'Rotate left',
              onPressed: () => _rotateSelection(-1),
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              tooltip: 'Rotate right',
              onPressed: () => _rotateSelection(1),
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton(
              tooltip: 'Delete pages',
              onPressed: _deleteSelection,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          PopupMenuButton<_OrganizerAction>(
            tooltip: 'More page actions',
            onSelected: _runAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _OrganizerAction.merge,
                child: ListTile(
                  leading: Icon(Icons.merge_type),
                  title: Text('Add PDF…'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _OrganizerAction.insertBlank,
                child: ListTile(
                  leading: Icon(Icons.insert_page_break_outlined),
                  title: Text('Insert blank page'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _OrganizerAction.selectRange,
                child: ListTile(
                  leading: Icon(Icons.filter_list),
                  title: Text('Select range…'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _OrganizerAction.selectAll,
                child: ListTile(
                  leading: const Icon(Icons.select_all),
                  title: Text(
                    _selection.length == _plan.length ? 'Select none' : 'Select all',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _OrganizerAction.extract,
                enabled: hasSelection,
                child: const ListTile(
                  leading: Icon(Icons.content_cut),
                  title: Text('Split: keep only selection'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _error != null ? null : _buildBottomBar(),
    );
  }

  void _runAction(_OrganizerAction action) {
    switch (action) {
      case _OrganizerAction.merge:
        _mergePdfs();
      case _OrganizerAction.insertBlank:
        _insertBlankPage();
      case _OrganizerAction.selectRange:
        _selectRange();
      case _OrganizerAction.selectAll:
        _selectAllOrNone();
      case _OrganizerAction.extract:
        _extractSelection();
    }
  }

  Widget _buildBody() {
    if (_isBusy) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Could not open this PDF', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      // Tapping selects, so only the handle starts a drag.
      buildDefaultDragHandles: false,
      itemCount: _plan.length,
      itemExtent: PageTile.height,
      onReorderItem: _onReorder,
      itemBuilder: (context, index) {
        final entry = _plan[index];
        return PageTile(
          key: ValueKey(entry.id),
          entry: entry,
          index: index,
          document: _documentFor(entry),
          sourceLabel: _labelFor(entry),
          isSelected: _selection.contains(index),
          onTap: () => _toggleSelection(index),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final documentCount = _sourceNames.length;
    return BottomAppBar(
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_plan.length} ${_plan.length == 1 ? 'page' : 'pages'}'
              '${documentCount > 1 ? ' from $documentCount documents' : ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: _plan.isEmpty || _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving…' : 'Save PDF'),
          ),
        ],
      ),
    );
  }
}

enum _OrganizerAction { merge, insertBlank, selectRange, selectAll, extract }
