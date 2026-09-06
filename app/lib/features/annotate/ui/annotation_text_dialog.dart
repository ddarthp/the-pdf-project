import 'package:flutter/material.dart';

/// Asks for the text of a sticky note or text box.
///
/// Returns the text, or null if dismissed. An empty result cancels the
/// annotation, so a note is never created with nothing in it.
Future<String?> showAnnotationTextDialog(
  BuildContext context, {
  required String title,
  String? initialText,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AnnotationTextDialog(title: title, initialText: initialText),
  );
}

class _AnnotationTextDialog extends StatefulWidget {
  const _AnnotationTextDialog({required this.title, this.initialText});

  final String title;
  final String? initialText;

  @override
  State<_AnnotationTextDialog> createState() => _AnnotationTextDialogState();
}

class _AnnotationTextDialogState extends State<_AnnotationTextDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Type your note', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
