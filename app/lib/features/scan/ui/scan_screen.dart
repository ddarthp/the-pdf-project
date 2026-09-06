import 'dart:async';

import 'package:flutter/material.dart';

import '../../convert/model/picked_image.dart';
import '../../convert/services/image_pdf_builder.dart';
import '../../share/services/pdf_export_service.dart';
import '../../share/ui/pdf_export_sheet.dart';
import '../model/scanned_page.dart';
import '../services/document_camera.dart';
import '../services/page_processor.dart';
import 'scan_review_screen.dart';

/// Scans a document with the camera, a page at a time.
///
/// Each photograph is straightened and cleaned up as it arrives; the pages are
/// then handed to the same builder that turns pictures into a PDF, so
/// everything past this point — page order, the document itself, saving,
/// sharing, printing — is machinery that already exists.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    this.camera = const DocumentCamera(),
    this.processor = const PageProcessor(),
    this.builder = const ImagePdfBuilder(),
    this.exporter = const PdfExportService(),
    super.key,
  });

  final DocumentCamera camera;
  final PageProcessor processor;
  final ImagePdfBuilder builder;
  final PdfExportService exporter;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScannedPage> _pages = const [];
  bool _isCapturing = false;
  bool _isBuilding = false;
  var _nextId = 0;

  @override
  void initState() {
    super.initState();
    // There is nothing to show until something is scanned, so the camera opens
    // straight away rather than making the reader ask twice.
    unawaited(_capture());
  }

  Future<void> _capture({bool fromCamera = true}) async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final photograph = fromCamera
          ? await widget.camera.capture()
          : await widget.camera.chooseExisting();
      if (!mounted || photograph == null) return;

      final page = await widget.processor.process(
        photograph: photograph,
        id: 'page-${_nextId++}',
      );
      if (!mounted) return;
      setState(() => _pages = [..._pages, page]);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not scan that: $error');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _review(ScannedPage page) async {
    final adjusted = await Navigator.of(context).push<ScannedPage>(
      MaterialPageRoute(
        builder: (context) => ScanReviewScreen(page: page, processor: widget.processor),
      ),
    );
    if (!mounted || adjusted == null) return;
    setState(() {
      _pages = [
        for (final existing in _pages)
          if (existing.id == adjusted.id) adjusted else existing,
      ];
    });
  }

  Future<void> _create() async {
    if (_pages.isEmpty || _isBuilding) return;
    setState(() => _isBuilding = true);
    try {
      final bytes = await widget.builder.build([
        for (final page in _pages)
          PickedImage(
            id: page.id,
            displayName: '${page.id}.png',
            bytes: page.processedBytes,
            pixelWidth: page.processedWidth,
            pixelHeight: page.processedHeight,
          ),
      ]);
      if (!mounted) return;

      const fileName = 'scan.pdf';
      final destination = await showPdfExportSheet(
        context,
        fileName: fileName,
        note: '${_pages.length} ${_pages.length == 1 ? 'page' : 'pages'}',
      );
      if (!mounted || destination == null) return;

      final result = await widget.exporter.run(
        destination,
        bytes: bytes,
        fileName: fileName,
      );
      if (!mounted || !result.completed) return;
      Navigator.of(context).pop(result.savedTo);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not make the PDF: $error');
    } finally {
      if (mounted) setState(() => _isBuilding = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          IconButton(
            tooltip: 'Scan another page',
            onPressed: _isCapturing ? null : () => unawaited(_capture()),
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
          IconButton(
            tooltip: 'Use a photo already taken',
            onPressed: _isCapturing ? null : () => unawaited(_capture(fromCamera: false)),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: _pages.isEmpty ? _buildEmpty() : _buildList(),
      bottomNavigationBar: _pages.isEmpty ? null : _buildBottomBar(),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.document_scanner_outlined, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Nothing scanned yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Photograph a page and it will be straightened and cleaned up. '
                'Scan as many as you like — they become one document.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isCapturing ? null : () => unawaited(_capture()),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(_isCapturing ? 'Scanning…' : 'Scan a page'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      itemCount: _pages.length,
      itemExtent: _ScannedPageTile.height,
      onReorderItem: (oldIndex, newIndex) => setState(() {
        final reordered = [..._pages];
        reordered.insert(newIndex, reordered.removeAt(oldIndex));
        _pages = reordered;
      }),
      itemBuilder: (context, index) {
        final page = _pages[index];
        return _ScannedPageTile(
          key: ValueKey(page.id),
          page: page,
          pageNumber: index + 1,
          onTap: () => unawaited(_review(page)),
          onRemove: () => setState(
            () => _pages = [
              for (final existing in _pages)
                if (existing.id != page.id) existing,
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_pages.length} ${_pages.length == 1 ? 'page' : 'pages'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: _isBuilding ? null : () => unawaited(_create()),
            icon: _isBuilding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_isBuilding ? 'Making…' : 'Make PDF'),
          ),
        ],
      ),
    );
  }
}

class _ScannedPageTile extends StatelessWidget {
  const _ScannedPageTile({
    required this.page,
    required this.pageNumber,
    required this.onTap,
    required this.onRemove,
    super.key,
  });

  final ScannedPage page;
  final int pageNumber;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  static const double height = 104;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Image.memory(page.processedBytes, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Page $pageNumber', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      page.filter.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Tap to adjust',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove page',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
