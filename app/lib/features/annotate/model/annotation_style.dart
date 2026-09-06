import 'dart:ui';

/// Colour, thickness and opacity for newly drawn annotations.
class AnnotationStyle {
  const AnnotationStyle({
    this.color = defaultColor,
    this.strokeWidth = defaultStrokeWidth,
    this.opacity = 1,
  });

  static const defaultColor = Color(0xFFE53935);
  static const defaultStrokeWidth = 3.0;

  /// Multi-colour presets offered by the toolbar.
  static const colorPresets = [
    Color(0xFFE53935), // red
    Color(0xFFFB8C00), // orange
    Color(0xFFFDD835), // yellow
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF8E24AA), // purple
    Color(0xFF000000), // black
  ];

  /// Stroke widths in PDF points, so a line keeps its real-world thickness
  /// whatever the zoom.
  static const strokeWidthPresets = [1.0, 3.0, 6.0, 12.0];

  final Color color;

  /// Stroke thickness in PDF points.
  final double strokeWidth;

  /// 0–1. Highlights default to something translucent; ink defaults to solid.
  final double opacity;

  AnnotationStyle copyWith({Color? color, double? strokeWidth, double? opacity}) => AnnotationStyle(
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    opacity: opacity ?? this.opacity,
  );

  @override
  bool operator ==(Object other) =>
      other is AnnotationStyle &&
      other.color == color &&
      other.strokeWidth == strokeWidth &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(color, strokeWidth, opacity);
}
