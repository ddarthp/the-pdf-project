import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../model/page_plan_entry.dart';

/// One row of the page organiser: a thumbnail, what the page is, and a handle
/// to drag it somewhere else.
class PageTile extends StatelessWidget {
  const PageTile({
    required this.entry,
    required this.index,
    required this.document,
    required this.sourceLabel,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final PagePlanEntry entry;

  /// Position in the plan, so the tile can show the page number it will have.
  final int index;

  /// The document the entry's page comes from; null for a blank page or for a
  /// source that is no longer open.
  final PdfDocument? document;

  final String sourceLabel;
  final bool isSelected;
  final VoidCallback onTap;

  static const double height = 108;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Material(
          color: isSelected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(width: 56, child: _Thumbnail(entry: entry, document: document)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Page ${index + 1}', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          sourceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (entry.quarterTurns != 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Rotated ${entry.quarterTurns * 90}°',
                            style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.entry, required this.document});

  final PagePlanEntry entry;
  final PdfDocument? document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = BoxDecoration(
      color: Colors.white,
      border: Border.all(color: scheme.outlineVariant),
    );

    return switch (entry) {
      BlankPageEntry() => DecoratedBox(
        decoration: border,
        child: Center(
          child: Icon(Icons.insert_page_break_outlined, size: 20, color: scheme.outline),
        ),
      ),
      SourcePageEntry(:final pageNumber) when document != null => PdfPageView(
        document: document,
        pageNumber: pageNumber,
        rotationOverride: _absoluteRotation(document!, pageNumber, entry.quarterTurns),
        decoration: border,
      ),
      // The source document went away; show that rather than an empty gap.
      _ => DecoratedBox(
        decoration: border,
        child: Center(child: Icon(Icons.broken_image_outlined, size: 20, color: scheme.error)),
      ),
    };
  }

  /// [PdfPageView.rotationOverride] wants the final rotation, while a plan
  /// entry stores a turn relative to the page's own.
  static PdfPageRotation? _absoluteRotation(PdfDocument document, int pageNumber, int quarterTurns) {
    if (quarterTurns == 0) return null;
    if (pageNumber < 1 || pageNumber > document.pages.length) return null;
    final base = document.pages[pageNumber - 1].rotation;
    return PdfPageRotation.values[(base.index + quarterTurns) % 4];
  }
}
