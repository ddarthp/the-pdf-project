import 'dart:math' as math;
import 'dart:ui';

/// A PDF appearance stream: the drawing instructions a viewer runs to paint an
/// annotation, plus the points it touches so the caller can size the bounding
/// box around them.
class AppearanceStream {
  const AppearanceStream({required this.content, required this.extent});

  /// PDF content-stream operators, in page coordinates (points, y upwards).
  final String content;

  /// Every point the drawing reaches, so the annotation rectangle can be made
  /// big enough — an arrowhead sticks out past the line's own endpoints.
  final List<Offset> extent;
}

/// Builds appearance streams for the annotations PDFium will not draw itself.
///
/// PDFium generates appearances for ink, square, circle, highlight and text
/// notes, but not for lines. Writing the stream by hand covers those: it is
/// only path operators, which need no resources — and an appearance stream
/// created through `FPDFAnnot_SetAP` gets an empty `/Resources` dictionary, so
/// anything needing a font or an ExtGState has to be built a different way.
/// Opacity still works, because it comes from the annotation's own `/CA`.
abstract final class AnnotationAppearance {
  /// A straight line from [from] to [to], in PDF page coordinates.
  static AppearanceStream line({
    required Offset from,
    required Offset to,
    required Color color,
    required double strokeWidth,
  }) {
    final buffer = StringBuffer();
    _begin(buffer, color, strokeWidth);
    _stroke(buffer, [from, to]);
    _end(buffer);
    return AppearanceStream(content: buffer.toString(), extent: [from, to]);
  }

  /// A line with an arrowhead at [to].
  static AppearanceStream arrow({
    required Offset from,
    required Offset to,
    required Color color,
    required double strokeWidth,
  }) {
    final barbs = arrowHead(from: from, to: to, strokeWidth: strokeWidth);
    final buffer = StringBuffer();
    _begin(buffer, color, strokeWidth);
    _stroke(buffer, [from, to]);
    for (final barb in barbs) {
      _stroke(buffer, [to, barb]);
    }
    _end(buffer);
    return AppearanceStream(content: buffer.toString(), extent: [from, to, ...barbs]);
  }

  /// Freehand strokes, in PDF page coordinates.
  ///
  /// Used for a drawn signature, which stays vector rather than being turned
  /// into pixels — a signature is the thing most likely to end up printed.
  static AppearanceStream strokes({
    required List<List<Offset>> strokes,
    required Color color,
    required double strokeWidth,
  }) {
    final buffer = StringBuffer();
    _begin(buffer, color, strokeWidth);
    final extent = <Offset>[];
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      // A single point is a dot; a zero-length line draws nothing, so give it
      // somewhere to go.
      _stroke(buffer, stroke.length == 1 ? [stroke.first, stroke.first.translate(0.01, 0)] : stroke);
      extent.addAll(stroke);
    }
    _end(buffer);
    return AppearanceStream(content: buffer.toString(), extent: extent);
  }

  /// The two barb tips of an arrowhead pointing from [from] towards [to].
  ///
  /// Shared with the on-screen painter's geometry so an exported arrow looks
  /// like the one that was drawn.
  static List<Offset> arrowHead({
    required Offset from,
    required Offset to,
    required double strokeWidth,
  }) {
    final direction = to - from;
    if (direction.distance == 0) return const [];
    final angle = math.atan2(direction.dy, direction.dx);
    final length = math.max(strokeWidth * 3, 8.0);
    const spread = math.pi / 7;
    return [
      for (final side in const [1, -1])
        to - Offset(math.cos(angle + spread * side), math.sin(angle + spread * side)) * length,
    ];
  }

  static void _begin(StringBuffer buffer, Color color, double strokeWidth) {
    buffer
      ..writeln('q')
      // Round caps and joins, to match how the strokes are drawn on screen.
      ..writeln('1 J 1 j')
      ..writeln('${_number(strokeWidth)} w')
      ..writeln(
        '${_number(color.r)} ${_number(color.g)} ${_number(color.b)} RG',
      );
  }

  static void _stroke(StringBuffer buffer, List<Offset> points) {
    if (points.isEmpty) return;
    buffer.writeln('${_number(points.first.dx)} ${_number(points.first.dy)} m');
    for (final point in points.skip(1)) {
      buffer.writeln('${_number(point.dx)} ${_number(point.dy)} l');
    }
    buffer.writeln('S');
  }

  static void _end(StringBuffer buffer) => buffer.writeln('Q');

  /// PDF numbers are plain decimals: no exponents, no thousands separators.
  static String _number(double value) {
    final text = value.toStringAsFixed(3);
    // Trim the noise a fixed precision leaves behind, keeping the stream small
    // and readable.
    if (!text.contains('.')) return text;
    final trimmed = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return trimmed.isEmpty || trimmed == '-' ? '0' : trimmed;
  }
}
