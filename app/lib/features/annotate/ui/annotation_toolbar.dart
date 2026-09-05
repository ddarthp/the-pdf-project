import 'package:flutter/material.dart';

import '../annotation_controller.dart';
import '../model/annotation.dart';
import '../model/annotation_style.dart';
import '../model/annotation_tool.dart';

/// Tools, colours, thickness and opacity for annotating.
///
/// Changing colour, thickness or opacity restyles the selected annotation as
/// well as the next one drawn, so the same controls edit what is already on
/// the page.
class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    required this.controller,
    required this.onClose,
    required this.onEditSelectedText,
    super.key,
  });

  final AnnotationController controller;
  final VoidCallback onClose;

  /// Re-opens the text of the selected note or text box.
  final VoidCallback onEditSelectedText;

  static const _toolIcons = {
    AnnotationTool.pan: Icons.pan_tool_outlined,
    AnnotationTool.select: Icons.near_me_outlined,
    AnnotationTool.ink: Icons.draw_outlined,
    AnnotationTool.highlight: Icons.highlight_alt_outlined,
    AnnotationTool.rectangle: Icons.crop_square,
    AnnotationTool.ellipse: Icons.circle_outlined,
    AnnotationTool.line: Icons.remove,
    AnnotationTool.arrow: Icons.north_east,
    AnnotationTool.textBox: Icons.text_fields,
    AnnotationTool.stickyNote: Icons.sticky_note_2_outlined,
    AnnotationTool.eraser: Icons.auto_fix_normal,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Material(
          color: theme.colorScheme.surfaceContainer,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolRow(
                  controller: controller,
                  toolIcons: _toolIcons,
                  onClose: onClose,
                  onEditSelectedText: onEditSelectedText,
                ),
                const Divider(height: 1),
                _StyleRow(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.controller,
    required this.toolIcons,
    required this.onClose,
    required this.onEditSelectedText,
  });

  final AnnotationController controller;
  final Map<AnnotationTool, IconData> toolIcons;
  final VoidCallback onClose;
  final VoidCallback onEditSelectedText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = controller.selected;
    final canEditText = selected is StickyNoteAnnotation || selected is TextBoxAnnotation;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tool in AnnotationTool.values)
                  IconButton(
                    tooltip: tool.label,
                    isSelected: controller.tool == tool,
                    onPressed: () => controller.tool = tool,
                    icon: Icon(toolIcons[tool]),
                    style: IconButton.styleFrom(
                      backgroundColor: controller.tool == tool ? scheme.primaryContainer : null,
                      foregroundColor: controller.tool == tool ? scheme.onPrimaryContainer : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, indent: 8, endIndent: 8),
        // Edit and delete act on the selection, so they are only live once
        // something is selected.
        IconButton(
          tooltip: 'Edit text',
          onPressed: canEditText ? onEditSelectedText : null,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete selected',
          onPressed: selected == null ? null : () => controller.remove(selected.id),
          icon: Icon(Icons.delete_outline, color: selected == null ? null : scheme.error),
        ),
        IconButton(
          tooltip: 'Done annotating',
          onPressed: onClose,
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }
}

class _StyleRow extends StatelessWidget {
  const _StyleRow({required this.controller});

  final AnnotationController controller;

  @override
  Widget build(BuildContext context) {
    final style = controller.style;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final color in AnnotationStyle.colorPresets)
            Semantics(
              label: 'Colour ${_colorName(color)}',
              selected: style.color == color,
              button: true,
              child: IconButton(
                tooltip: _colorName(color),
                onPressed: () => controller.style = style.copyWith(color: color),
                icon: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: style.color == color ? scheme.primary : scheme.outlineVariant,
                      width: style.color == color ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          for (final width in AnnotationStyle.strokeWidthPresets)
            IconButton(
              tooltip: 'Thickness ${width.toStringAsFixed(0)}',
              onPressed: () => controller.style = style.copyWith(strokeWidth: width),
              icon: Container(
                width: 22,
                height: width.clamp(2, 12).toDouble(),
                decoration: BoxDecoration(
                  color: style.strokeWidth == width ? scheme.primary : scheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          const Icon(Icons.opacity, size: 18),
          Expanded(
            child: Semantics(
              label: 'Opacity',
              child: Slider(
                value: style.opacity,
                min: 0.1,
                divisions: 9,
                label: '${(style.opacity * 100).round()}%',
                onChanged: (value) => controller.style = style.copyWith(opacity: value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _colorName(Color color) => switch (color.toARGB32()) {
    0xFFE53935 => 'Red',
    0xFFFB8C00 => 'Orange',
    0xFFFDD835 => 'Yellow',
    0xFF43A047 => 'Green',
    0xFF1E88E5 => 'Blue',
    0xFF8E24AA => 'Purple',
    _ => 'Black',
  };
}
