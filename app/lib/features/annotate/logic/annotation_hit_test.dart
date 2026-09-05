import 'dart:math' as math;
import 'dart:ui';

import '../model/annotation.dart';
import 'page_coordinates.dart';

/// Finds the annotation under a touch.
///
/// Hit testing happens in document space rather than normalised space: a
/// tolerance means "within so many pixels of what I can see", and normalised
/// units are stretched differently across a page's width and height, so a
/// circular tolerance there would come out as an ellipse on screen.
abstract final class AnnotationHitTest {
  /// The annotation nearest the front under [documentPoint], or null.
  ///
  /// Later annotations sit on top of earlier ones, so the list is searched
  /// backwards.
  static Annotation? topmostAt(
    List<Annotation> annotations,
    Offset documentPoint,
    Rect pageRect, {
    required double tolerance,
    required double pageWidthInPoints,
  }) {
    for (final annotation in annotations.reversed) {
      if (hits(
        annotation,
        documentPoint,
        pageRect,
        tolerance: tolerance,
        pageWidthInPoints: pageWidthInPoints,
      )) {
        return annotation;
      }
    }
    return null;
  }

  /// Whether [documentPoint] is on [annotation], within [tolerance] document
  /// units of its drawn shape.
  static bool hits(
    Annotation annotation,
    Offset documentPoint,
    Rect pageRect, {
    required double tolerance,
    required double pageWidthInPoints,
  }) {
    Offset toDoc(Offset normalized) => PageCoordinates.toDocument(normalized, pageRect);
    Rect toDocRect(Rect normalized) => PageCoordinates.rectToDocument(normalized, pageRect);
    double strokeSlack(double points) =>
        PageCoordinates.lengthToDocument(points, pageRect, pageWidthInPoints) / 2 + tolerance;

    switch (annotation) {
      case InkAnnotation(:final strokes, :final strokeWidth):
        final slack = strokeSlack(strokeWidth);
        for (final stroke in strokes) {
          if (stroke.length == 1) {
            if ((toDoc(stroke.first) - documentPoint).distance <= slack) return true;
            continue;
          }
          for (var i = 0; i + 1 < stroke.length; i++) {
            if (_distanceToSegment(documentPoint, toDoc(stroke[i]), toDoc(stroke[i + 1])) <= slack) {
              return true;
            }
          }
        }
        return false;

      case ShapeAnnotation(:final kind, :final start, :final end, :final strokeWidth):
        final slack = strokeSlack(strokeWidth);
        final a = toDoc(start);
        final b = toDoc(end);
        return switch (kind) {
          ShapeKind.line || ShapeKind.arrow => _distanceToSegment(documentPoint, a, b) <= slack,
          // Outlined shapes are grabbed by their edge, not their empty middle,
          // so an annotation drawn around text does not swallow taps on it.
          ShapeKind.rectangle => _isNearRectEdge(documentPoint, Rect.fromPoints(a, b), slack),
          ShapeKind.ellipse => _isNearEllipseEdge(documentPoint, Rect.fromPoints(a, b), slack),
        };

      case HighlightAnnotation(:final bands):
        return bands.any((band) => toDocRect(band).inflate(tolerance).contains(documentPoint));

      case TextBoxAnnotation(:final bounds):
        return toDocRect(bounds).inflate(tolerance).contains(documentPoint);

      case StickyNoteAnnotation(:final anchor):
        final size = PageCoordinates.lengthToDocument(
          StickyNoteAnnotation.markerSize,
          pageRect,
          pageWidthInPoints,
        );
        return Rect.fromLTWH(toDoc(anchor).dx, toDoc(anchor).dy, size, size)
            .inflate(tolerance)
            .contains(documentPoint);
    }
  }

  /// Shortest distance from [point] to the segment `a`–`b`.
  static double _distanceToSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (point - a).distance;
    final t = (((point - a).dx * ab.dx + (point - a).dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    return (point - (a + ab * t)).distance;
  }

  static bool _isNearRectEdge(Offset point, Rect rect, double slack) {
    final outer = rect.inflate(slack);
    if (!outer.contains(point)) return false;
    final inner = rect.deflate(slack);
    return inner.width <= 0 || inner.height <= 0 || !inner.contains(point);
  }

  static bool _isNearEllipseEdge(Offset point, Rect rect, double slack) {
    if (rect.width <= 0 || rect.height <= 0) return false;
    final center = rect.center;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    // Normalised radius: 1.0 is exactly on the ellipse. Converting the slack
    // into that space keeps the band even on a stretched ellipse.
    final normalized = math.sqrt(
      math.pow((point.dx - center.dx) / rx, 2) + math.pow((point.dy - center.dy) / ry, 2),
    );
    final band = slack / math.min(rx, ry);
    return (normalized - 1).abs() <= band;
  }
}
