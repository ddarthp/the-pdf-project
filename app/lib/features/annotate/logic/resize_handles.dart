import 'dart:math' as math;
import 'dart:ui';

/// Which corner of a selected annotation is being dragged.
enum ResizeHandle { topLeft, topRight, bottomLeft, bottomRight }

/// The corner handles that resize a selected annotation.
///
/// Kept as pure geometry so the fiddly part — which corner stays put, and what
/// happens when a drag crosses over it — can be tested without a gesture.
abstract final class ResizeHandles {
  /// How far the handles sit outside the annotation's own bounds, in logical
  /// pixels. Matches where [AnnotationPainter] draws them.
  static const inset = 7.5;

  /// The smallest an annotation may be dragged to, as a fraction of the page,
  /// so it cannot be shrunk into nothing and lost.
  static const minimumSize = 0.02;

  /// The handle under [point], or null if the touch was not on one.
  static ResizeHandle? at(Rect bounds, Offset point, double tolerance) {
    final outer = bounds.inflate(inset);
    final corners = {
      ResizeHandle.topLeft: outer.topLeft,
      ResizeHandle.topRight: outer.topRight,
      ResizeHandle.bottomLeft: outer.bottomLeft,
      ResizeHandle.bottomRight: outer.bottomRight,
    };

    ResizeHandle? nearest;
    var nearestDistance = double.infinity;
    for (final entry in corners.entries) {
      final distance = (entry.value - point).distance;
      if (distance <= tolerance && distance < nearestDistance) {
        nearest = entry.key;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  /// Where [bounds] ends up when [handle] is dragged to [to].
  ///
  /// The opposite corner stays put. Dragging past it flips the rectangle
  /// rather than inverting it, and nothing shrinks below [minimum].
  static Rect resize(
    Rect bounds,
    ResizeHandle handle,
    Offset to, {
    double minimum = minimumSize,
  }) {
    final anchor = switch (handle) {
      ResizeHandle.topLeft => bounds.bottomRight,
      ResizeHandle.topRight => bounds.bottomLeft,
      ResizeHandle.bottomLeft => bounds.topRight,
      ResizeHandle.bottomRight => bounds.topLeft,
    };

    final rect = Rect.fromPoints(anchor, to);
    if (rect.width >= minimum && rect.height >= minimum) return rect;

    // Too small in one direction or both: grow it back out, away from the
    // corner that is staying put.
    final width = math.max(rect.width, minimum);
    final height = math.max(rect.height, minimum);
    return Rect.fromPoints(
      anchor,
      Offset(
        to.dx >= anchor.dx ? anchor.dx + width : anchor.dx - width,
        to.dy >= anchor.dy ? anchor.dy + height : anchor.dy - height,
      ),
    );
  }
}
