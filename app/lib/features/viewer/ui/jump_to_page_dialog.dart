import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/page_navigation.dart';

/// Asks for a page number. Returns null if dismissed.
Future<int?> showJumpToPageDialog(
  BuildContext context, {
  required int pageCount,
  required int currentPage,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _JumpToPageDialog(pageCount: pageCount, currentPage: currentPage),
  );
}

class _JumpToPageDialog extends StatefulWidget {
  const _JumpToPageDialog({required this.pageCount, required this.currentPage});

  final int pageCount;
  final int currentPage;

  @override
  State<_JumpToPageDialog> createState() => _JumpToPageDialogState();
}

class _JumpToPageDialogState extends State<_JumpToPageDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.currentPage}',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final page = PageNavigation.parsePageInput(_controller.text, widget.pageCount);
    if (page == null) {
      setState(() => _error = 'Enter a page between 1 and ${widget.pageCount}.');
      return;
    }
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to page'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Page number',
          helperText: '1 – ${widget.pageCount}',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}
