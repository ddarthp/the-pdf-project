import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../share/services/pdf_export_service.dart';
import '../../share/ui/pdf_export_sheet.dart';
import '../../viewer/model/pdf_source.dart';
import '../../viewer/ui/password_dialog.dart';
import '../logic/form_edits.dart';
import '../model/pdf_form_field.dart';
import '../services/pdf_form_service.dart';
import 'form_field_editor.dart';

/// Fills in a PDF's form fields and saves the result.
///
/// Like the page organiser, this works on its own copy of the document: the
/// one the viewer is showing is never changed, and nothing reaches the file
/// system until the reader saves.
class FormFillScreen extends StatefulWidget {
  const FormFillScreen({
    required this.source,
    this.service = const PdfFormService(),
    this.exporter = const PdfExportService(),
    super.key,
  });

  final PdfSource source;
  final PdfFormService service;

  /// Sends the filled PDF to a file, the share sheet or a printer.
  final PdfExportService exporter;

  @override
  State<FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<FormFillScreen> {
  PdfDocument? _document;
  List<PdfFormField> _fields = const [];
  Map<String, String> _values = const {};
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  int _passwordAttempts = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_document?.dispose());
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

  Future<void> _load() async {
    try {
      final document = await _openCopy();
      final fields = await widget.service.readFields(document);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() {
        _document = document;
        _fields = fields;
        _values = FormEdits.initialValues(fields);
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _isLoading = false;
      });
    }
  }

  Future<PdfDocument> _openCopy() => switch (widget.source) {
    PdfFileSource(:final path) => PdfDocument.openFile(path, passwordProvider: _requestPassword),
    PdfDataSource(:final bytes, :final sourceId) => PdfDocument.openData(
      bytes,
      sourceName: 'form-$sourceId',
      passwordProvider: _requestPassword,
    ),
  };

  void _setValue(String name, String value) {
    setState(() => _values = {..._values, name: value});
  }

  Future<void> _save() async {
    final document = _document;
    if (document == null || _isSaving) return;

    final changes = FormEdits.changes(_fields, _values);
    if (changes.isEmpty) {
      _showMessage('Nothing has been filled in yet.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final result = await widget.service.fill(document, _fields, changes);
      if (!mounted) return;
      final fileName = _suggestedFileName();
      final destination = await showPdfExportSheet(
        context,
        fileName: fileName,
        note: result.skipped > 0
            ? '${result.filled} of ${result.requested} fields filled; '
                  '${result.skipped} could not be'
            : '${result.filled} ${result.filled == 1 ? 'field' : 'fields'} filled',
      );
      if (!mounted || destination == null) return;

      final outcome = await widget.exporter.run(
        destination,
        bytes: result.bytes,
        fileName: fileName,
      );
      if (!mounted || !outcome.completed) return;
      Navigator.of(context).pop(outcome.savedTo);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not save the form: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _suggestedFileName() {
    final name = widget.source.displayName;
    final base = name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
    return '$base-filled.pdf';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fill form')),
      body: _buildBody(),
      bottomNavigationBar: _fields.isEmpty ? null : _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not read this form',
        detail: error,
        isError: true,
      );
    }

    if (_fields.isEmpty) {
      return const _Message(
        icon: Icons.article_outlined,
        title: 'No form fields',
        detail: 'This PDF has nothing to fill in. You can still annotate it or '
            'sign it from the viewer.',
      );
    }

    // Fields are grouped by page so a long form reads in the order it is
    // printed rather than as one flat list.
    final byPage = <int, List<PdfFormField>>{};
    for (final field in _fields) {
      byPage.putIfAbsent(field.pageNumber, () => []).add(field);
    }
    final pageNumbers = byPage.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final pageNumber in pageNumbers) ...[
          _PageHeader(pageNumber: pageNumber, count: byPage[pageNumber]!.length),
          for (final field in byPage[pageNumber]!)
            FormFieldEditor(
              key: ValueKey('${field.pageNumber}:${field.name}'),
              field: field,
              value: _values[field.name] ?? field.value,
              onChanged: (value) => _setValue(field.name, value),
            ),
        ],
      ],
    );
  }

  Widget _buildBottomBar() {
    final progress = FormEdits.progress(_fields, _values);
    return BottomAppBar(
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${progress.filled} of ${progress.total} filled in',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving…' : 'Save filled PDF'),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.pageNumber, required this.count});

  final int pageNumber;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        'Page $pageNumber · $count ${count == 1 ? 'field' : 'fields'}',
        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: isError ? theme.colorScheme.error : theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
