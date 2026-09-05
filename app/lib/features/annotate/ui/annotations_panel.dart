import 'package:flutter/material.dart';

import '../annotation_controller.dart';
import '../model/annotation.dart';

/// Every annotation in the document, grouped by page.
///
/// Tapping one takes the reader to it and selects it, which is how an
/// annotation buried on page 40 gets found and edited again.
class AnnotationsPanel extends StatelessWidget {
  const AnnotationsPanel({
    required this.controller,
    required this.onSelect,
    required this.onEditText,
    super.key,
  });

  final AnnotationController controller;

  /// Called with the annotation to go to.
  final ValueChanged<Annotation> onSelect;

  /// Called to re-edit the text of a note or text box.
  final ValueChanged<Annotation> onEditText;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final annotations = controller.annotations;
        if (annotations.isEmpty) {
          return _Message(
            text: 'No annotations yet. Turn on the annotation toolbar to draw, '
                'highlight or leave a note.',
          );
        }

        final byPage = <int, List<Annotation>>{};
        for (final annotation in annotations) {
          byPage.putIfAbsent(annotation.pageNumber, () => []).add(annotation);
        }
        final pageNumbers = byPage.keys.toList()..sort();

        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            for (final pageNumber in pageNumbers) ...[
              _PageHeader(pageNumber: pageNumber, count: byPage[pageNumber]!.length),
              for (final annotation in byPage[pageNumber]!)
                _AnnotationRow(
                  annotation: annotation,
                  isSelected: annotation.id == controller.selectedId,
                  onTap: () => onSelect(annotation),
                  onDelete: () => controller.remove(annotation.id),
                  onEditText: _hasText(annotation) ? () => onEditText(annotation) : null,
                ),
            ],
          ],
        );
      },
    );
  }

  static bool _hasText(Annotation annotation) =>
      annotation is StickyNoteAnnotation || annotation is TextBoxAnnotation;
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.pageNumber, required this.count});

  final int pageNumber;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        'Page $pageNumber · $count ${count == 1 ? 'annotation' : 'annotations'}',
        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _AnnotationRow extends StatelessWidget {
  const _AnnotationRow({
    required this.annotation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onEditText,
  });

  final Annotation annotation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onEditText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: isSelected,
      leading: Icon(_iconFor(annotation), color: annotation.color),
      title: Text(annotation.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(_typeNameOf(annotation)),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEditText != null)
            IconButton(
              tooltip: 'Edit text',
              onPressed: onEditText,
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(
            tooltip: 'Delete annotation',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, color: scheme.error),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(Annotation annotation) => switch (annotation) {
    InkAnnotation() => Icons.draw_outlined,
    HighlightAnnotation() => Icons.highlight_alt_outlined,
    TextBoxAnnotation() => Icons.text_fields,
    StickyNoteAnnotation() => Icons.sticky_note_2_outlined,
    ShapeAnnotation(:final kind) => switch (kind) {
      ShapeKind.rectangle => Icons.crop_square,
      ShapeKind.ellipse => Icons.circle_outlined,
      ShapeKind.line => Icons.remove,
      ShapeKind.arrow => Icons.north_east,
    },
  };

  static String _typeNameOf(Annotation annotation) => switch (annotation) {
    InkAnnotation() => 'Drawing',
    HighlightAnnotation() => 'Highlight',
    TextBoxAnnotation() => 'Text box',
    StickyNoteAnnotation() => 'Sticky note',
    ShapeAnnotation() => annotation.summary,
  };
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
