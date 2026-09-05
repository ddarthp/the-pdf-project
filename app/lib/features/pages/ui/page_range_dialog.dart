import 'package:flutter/material.dart';

import '../logic/page_range.dart';

/// Asks for a page range and returns the pages it names, 1-based and sorted.
///
/// Returns null if dismissed.
Future<List<int>?> showPageRangeDialog(
  BuildContext context, {
  required int pageCount,
  String initialText = '',
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (context) => _PageRangeDialog(pageCount: pageCount, initialText: initialText),
  );
}

class _PageRangeDialog extends StatefulWidget {
  const _PageRangeDialog({required this.pageCount, required this.initialText});

  final int pageCount;
  final String initialText;

  @override
  State<_PageRangeDialog> createState() => _PageRangeDialogState();
}

class _PageRangeDialogState extends State<_PageRangeDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pages = PageRange.parse(_controller.text, widget.pageCount);
    if (pages == null) {
      setState(() => _error = 'Enter pages between 1 and ${widget.pageCount}, like 1-3, 7.');
      return;
    }
    Navigator.of(context).pop(pages);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select a page range'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Pages',
          hintText: '1-3, 7, 10-',
          helperText: 'This document has ${widget.pageCount} pages',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Select')),
      ],
    );
  }
}
