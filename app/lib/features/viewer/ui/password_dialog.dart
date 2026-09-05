import 'package:flutter/material.dart';

/// Asks for the password of an encrypted PDF.
///
/// Returns the entered password, or null if the reader gave up — pdfrx treats
/// a null password as "stop trying" and surfaces a load error.
Future<String?> showPdfPasswordDialog(
  BuildContext context, {
  required String fileName,
  required bool isRetry,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PasswordDialog(fileName: fileName, isRetry: isRetry),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.fileName, required this.isRetry});

  final String fileName;
  final bool isRetry;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: const Text('Password required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isRetry
                ? 'That password did not open ${widget.fileName}. Try again.'
                : '${widget.fileName} is protected. Enter its password to open it.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _obscure,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: widget.isRetry ? 'Incorrect password' : null,
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Open')),
      ],
    );
  }
}
