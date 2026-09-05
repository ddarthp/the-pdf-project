import 'package:flutter/material.dart';

import '../../annotate/ui/annotation_painter.dart';
import '../logic/signature_geometry.dart';
import '../model/signature_source.dart';
import 'signature_canvas.dart';
import 'signature_image_picker.dart';

/// Captures a signature: drawn, typed, or from a picture.
///
/// Returns the signature, or null if the reader backed out. Everything happens
/// on the device — the picture never leaves it.
Future<SignatureSource?> showSignaturePad(
  BuildContext context, {
  required Color color,
  SignatureImagePicker picker = const SignatureImagePicker(),
}) {
  return showModalBottomSheet<SignatureSource>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SignaturePadSheet(color: color, picker: picker),
  );
}

class _SignaturePadSheet extends StatefulWidget {
  const _SignaturePadSheet({required this.color, required this.picker});

  final Color color;
  final SignatureImagePicker picker;

  @override
  State<_SignaturePadSheet> createState() => _SignaturePadSheetState();
}

class _SignaturePadSheetState extends State<_SignaturePadSheet> {
  final _typedController = TextEditingController();

  List<List<Offset>> _strokes = const [];
  SignatureTypeface _typeface = SignatureTypeface.flowing;
  PickedSignatureImage? _image;
  String? _imageError;
  bool _isPicking = false;

  @override
  void dispose() {
    _typedController.dispose();
    super.dispose();
  }

  /// The signature as it currently stands, or null while there is nothing to
  /// place yet.
  SignatureSource? _buildSource(int tabIndex) => switch (tabIndex) {
    0 => _buildDrawn(),
    1 => _buildTyped(),
    _ => _buildImage(),
  };

  DrawnSignature? _buildDrawn() {
    final tightened = SignatureGeometry.tighten(_strokes);
    if (tightened == null) return null;

    // The pad's stroke width is in its own pixels; store it as a fraction of
    // the signature so it scales with wherever the signature is placed.
    return DrawnSignature(
      strokes: tightened.strokes,
      strokeWidth: (SignatureCanvas.strokeWidth / tightened.width).clamp(0.002, 0.08),
      aspectRatio: tightened.aspectRatio,
    );
  }

  TypedSignature? _buildTyped() {
    final text = _typedController.text.trim();
    if (text.isEmpty) return null;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AnnotationPainter.typedSignatureStyle(_typeface, widget.color, 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final aspectRatio = painter.height <= 0 ? 4.0 : painter.width / painter.height;
    painter.dispose();
    return TypedSignature(
      text: text,
      typeface: _typeface,
      aspectRatio: SignatureGeometry.clampAspectRatio(aspectRatio),
    );
  }

  ImageSignature? _buildImage() {
    final image = _image;
    if (image == null) return null;
    return ImageSignature(bytes: image.bytes, aspectRatio: image.aspectRatio);
  }

  Future<void> _pickImage() async {
    setState(() {
      _isPicking = true;
      _imageError = null;
    });
    try {
      final picked = await widget.picker.pick();
      if (!mounted || picked == null) return;
      setState(() => _image = picked);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _imageError = '$error');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A plain header rather than an AppBar: inside a
                  // shrink-wrapping sheet an AppBar has no bounded height to
                  // lay its title and tabs out in.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Cancel',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Text(
                            'Signature',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        FilledButton(
                          onPressed: _buildSource(tabController.index) == null
                              ? null
                              : () =>
                                    Navigator.of(context).pop(_buildSource(tabController.index)),
                          child: const Text('Place'),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.gesture), text: 'Draw'),
                      Tab(icon: Icon(Icons.keyboard), text: 'Type'),
                      Tab(icon: Icon(Icons.image_outlined), text: 'Image'),
                    ],
                  ),
                  SizedBox(
                    height: 260,
                    child: TabBarView(
                      children: [_buildDrawTab(), _buildTypeTab(), _buildImageTab()],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrawTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: SignatureCanvas(
              strokes: _strokes,
              color: widget.color,
              onChanged: (strokes) => setState(() => _strokes = strokes),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _strokes.isEmpty
                    ? null
                    : () => setState(() => _strokes = _strokes.sublist(0, _strokes.length - 1)),
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
              TextButton.icon(
                onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes = const []),
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _typedController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Your name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final typeface in SignatureTypeface.values)
                ChoiceChip(
                  label: Text(typeface.label),
                  selected: _typeface == typeface,
                  onSelected: (_) => setState(() => _typeface = typeface),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: FittedBox(
                child: Text(
                  _typedController.text.trim().isEmpty ? ' ' : _typedController.text.trim(),
                  style: AnnotationPainter.typedSignatureStyle(_typeface, widget.color, 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTab() {
    final image = _image;
    final error = _imageError;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: image == null
                  ? Text(
                      error ?? 'Pick a photo or scan of your signature.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: error == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.error,
                      ),
                    )
                  : Image.memory(image.bytes, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _isPicking ? null : _pickImage,
            icon: const Icon(Icons.folder_open),
            label: Text(image == null ? 'Choose image' : 'Choose another'),
          ),
        ],
      ),
    );
  }
}
