import 'package:flutter/material.dart';

/// Shown before any document is open.
class ViewerEmptyState extends StatelessWidget {
  const ViewerEmptyState({required this.onOpenPressed, this.isOpening = false, super.key});

  final VoidCallback onOpenPressed;
  final bool isOpening;

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
                Icons.picture_as_pdf_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('The PDF Project', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Open a PDF to start reading. Everything happens on this '
                'device — no account, no upload, no network.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: isOpening ? null : onOpenPressed,
                icon: isOpening
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open),
                label: Text(isOpening ? 'Opening…' : 'Open PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
