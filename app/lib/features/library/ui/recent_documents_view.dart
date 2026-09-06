import 'package:flutter/material.dart';

import '../model/recent_document.dart';

/// The app's home: what you have been reading, and a way to open something
/// else.
///
/// Shown whenever no document is open, so the first thing on screen is the
/// reader's own library rather than an empty page.
class RecentDocumentsView extends StatelessWidget {
  const RecentDocumentsView({
    required this.documents,
    required this.missingPaths,
    required this.isOpening,
    required this.onOpenPressed,
    required this.onImagesPressed,
    required this.onDocumentSelected,
    required this.onDocumentRemoved,
    super.key,
  });

  final List<RecentDocument> documents;

  /// Paths that are no longer on the device — the document was moved, deleted,
  /// or handed over by another app that has since cleaned it up.
  final Set<String> missingPaths;

  final bool isOpening;
  final VoidCallback onOpenPressed;

  /// Starts a new document from pictures.
  final VoidCallback onImagesPressed;
  final ValueChanged<RecentDocument> onDocumentSelected;
  final ValueChanged<RecentDocument> onDocumentRemoved;

  @override
  Widget build(BuildContext context) {
    // No spinner while the list loads: reading it takes a moment and a
    // spinner would only hide the one button that is always worth showing.
    if (documents.isEmpty) {
      return _EmptyLibrary(
        isOpening: isOpening,
        onOpenPressed: onOpenPressed,
        onImagesPressed: onImagesPressed,
      );
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8),
            itemCount: documents.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Recent',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                );
              }
              final document = documents[index - 1];
              return _RecentTile(
                document: document,
                isMissing: missingPaths.contains(document.path),
                onTap: () => onDocumentSelected(document),
                onRemove: () => onDocumentRemoved(document),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _StartActions(
              isOpening: isOpening,
              onOpenPressed: onOpenPressed,
              onImagesPressed: onImagesPressed,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.document,
    required this.isMissing,
    required this.onTap,
    required this.onRemove,
  });

  final RecentDocument document;
  final bool isMissing;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      leading: Icon(
        isMissing ? Icons.report_gmailerrorred_outlined : Icons.picture_as_pdf_outlined,
        color: isMissing ? scheme.error : scheme.primary,
      ),
      title: Text(
        document.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isMissing ? TextStyle(color: scheme.onSurfaceVariant) : null,
      ),
      subtitle: Text(
        isMissing ? 'No longer on this device' : _subtitleFor(document),
        style: theme.textTheme.bodySmall?.copyWith(
          color: isMissing ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        tooltip: 'Remove from recent',
        icon: const Icon(Icons.close),
        onPressed: onRemove,
      ),
      onTap: isMissing ? null : onTap,
      enabled: !isMissing,
    );
  }

  static String _subtitleFor(RecentDocument document) {
    final when = describeWhen(document.lastOpenedAt);
    final pages = document.pageCount;
    if (pages == null) return when;
    return '$pages ${pages == 1 ? 'page' : 'pages'} · $when';
  }
}

/// How long ago something was opened, in words.
///
/// Deliberately coarse: the exact minute a document was last opened is not
/// something anyone needs, and "yesterday" reads better than a timestamp.
String describeWhen(DateTime when, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(when);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes} ${elapsed.inMinutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} ${elapsed.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  if (elapsed.inDays == 1) return 'Yesterday';
  if (elapsed.inDays < 7) return '${elapsed.inDays} days ago';
  if (elapsed.inDays < 30) {
    final weeks = elapsed.inDays ~/ 7;
    return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
  }
  final months = elapsed.inDays ~/ 30;
  return '$months ${months == 1 ? 'month' : 'months'} ago';
}

/// Opening something that exists, or making something that does not.
class _StartActions extends StatelessWidget {
  const _StartActions({
    required this.isOpening,
    required this.onOpenPressed,
    required this.onImagesPressed,
  });

  final bool isOpening;
  final VoidCallback onOpenPressed;
  final VoidCallback onImagesPressed;

  @override
  Widget build(BuildContext context) {
    // Wraps rather than overflowing: two buttons side by side do not fit a
    // narrow phone.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
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
        OutlinedButton.icon(
          onPressed: onImagesPressed,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Images to PDF'),
        ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.isOpening,
    required this.onOpenPressed,
    required this.onImagesPressed,
  });

  final bool isOpening;
  final VoidCallback onOpenPressed;
  final VoidCallback onImagesPressed;

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
              Icon(Icons.picture_as_pdf_outlined, size: 72, color: theme.colorScheme.primary),
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
              _StartActions(
                isOpening: isOpening,
                onOpenPressed: onOpenPressed,
                onImagesPressed: onImagesPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
