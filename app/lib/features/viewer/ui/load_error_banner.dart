import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Replaces pdfrx's raw error dump when a document fails to load.
///
/// A cancelled or wrong password is the common case and is not really an
/// error, so it gets its own wording and a way back in.
class LoadErrorBanner extends StatelessWidget {
  const LoadErrorBanner({
    required this.error,
    required this.onRetry,
    required this.onOpenAnother,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onOpenAnother;

  bool get _isPasswordError => error is PdfPasswordException;

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
                _isPasswordError ? Icons.lock_outline : Icons.error_outline,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _isPasswordError ? 'This PDF is locked' : 'Could not open this PDF',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isPasswordError
                    ? 'It needs a password before it can be shown.'
                    : '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(_isPasswordError ? 'Enter password' : 'Try again'),
                  ),
                  TextButton.icon(
                    onPressed: onOpenAnother,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open another'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
