import 'dart:async';

import 'package:flutter/material.dart';

import '../../share/services/pdf_export_service.dart';
import '../../share/ui/pdf_export_sheet.dart';
import '../logic/image_pages.dart';
import '../model/picked_image.dart';
import '../services/image_pdf_builder.dart';
import '../services/image_source_picker.dart';

/// Turns a set of pictures into a PDF, one page each.
///
/// Nothing is written until the reader saves, and the pictures never leave the
/// device.
class ImageToPdfScreen extends StatefulWidget {
  const ImageToPdfScreen({
    this.picker = const ImageSourcePicker(),
    this.builder = const ImagePdfBuilder(),
    this.exporter = const PdfExportService(),
    super.key,
  });

  final ImageSourcePicker picker;
  final ImagePdfBuilder builder;
  final PdfExportService exporter;

  @override
  State<ImageToPdfScreen> createState() => _ImageToPdfScreenState();
}

class _ImageToPdfScreenState extends State<ImageToPdfScreen> {
  List<PickedImage> _images = const [];
  bool _isPicking = false;
  bool _isBuilding = false;

  @override
  void initState() {
    super.initState();
    // The screen has nothing to show until something is chosen, so the picker
    // opens straight away rather than making the reader ask twice.
    unawaited(_addImages());
  }

  Future<void> _addImages() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final added = await widget.picker.pickImages(startingId: _images.length);
      if (!mounted || added.isEmpty) return;
      setState(() => _images = ImagePages.append(_images, added));
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not read those images: $error');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _create() async {
    if (_images.isEmpty || _isBuilding) return;
    setState(() => _isBuilding = true);
    try {
      final bytes = await widget.builder.build(_images);
      if (!mounted) return;
      final fileName = ImagePages.suggestedFileName(_images);
      final destination = await showPdfExportSheet(
        context,
        fileName: fileName,
        note: '${_images.length} ${_images.length == 1 ? 'page' : 'pages'}',
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
        title: const Text('Images to PDF'),
        actions: [
          IconButton(
            tooltip: 'Add images',
            onPressed: _isPicking ? null : () => unawaited(_addImages()),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: _images.isEmpty ? _buildEmpty() : _buildList(),
      bottomNavigationBar: _images.isEmpty ? null : _buildBottomBar(),
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
              Icon(Icons.photo_library_outlined, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('No images yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Choose photos or scans and each one becomes a page, in the '
                'order you put them in.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isPicking ? null : () => unawaited(_addImages()),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_isPicking ? 'Choosing…' : 'Choose images'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      // Tapping does nothing, so the whole row can start a drag.
      itemCount: _images.length,
      itemExtent: _ImageTile.height,
      onReorderItem: (oldIndex, newIndex) =>
          setState(() => _images = ImagePages.reorder(_images, oldIndex, newIndex)),
      itemBuilder: (context, index) {
        final image = _images[index];
        return _ImageTile(
          key: ValueKey(image.id),
          image: image,
          pageNumber: index + 1,
          onRemove: () => setState(() => _images = ImagePages.remove(_images, image.id)),
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
              '${_images.length} ${_images.length == 1 ? 'page' : 'pages'}',
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

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.image,
    required this.pageNumber,
    required this.onRemove,
    super.key,
  });

  final PickedImage image;
  final int pageNumber;
  final VoidCallback onRemove;

  static const double height = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant)),
                child: Image.memory(image.bytes, fit: BoxFit.contain),
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
                    image.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${image.pixelWidth} × ${image.pixelHeight}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove image',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
