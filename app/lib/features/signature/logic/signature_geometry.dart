import 'dart:math' as math;
import 'dart:ui';

/// Strokes cropped to what was actually drawn, plus the shape of that crop.
class TightenedStrokes {
  const TightenedStrokes({
    required this.strokes,
    required this.aspectRatio,
    required this.width,
    required this.height,
  });

  /// Strokes as fractions of their own bounding box.
  final List<List<Offset>> strokes;

  /// Width over height of that box.
  final double aspectRatio;

  /// The box's size in the units the strokes came in — the pad's own pixels.
  /// Lets the caller express a pad-sized stroke width as a fraction of the
  /// signature, without having to measure the widget.
  final double width;
  final double height;
}

/// Geometry for capturing and placing a signature.
///
/// Free of Flutter widgets so the awkward parts — cropping a drawing to what
/// was drawn, and giving a signature the right shape wherever it lands — can
/// be tested directly.
abstract final class SignatureGeometry {
  /// A signature is never taller than this relative to its width, nor wider
  /// than this relative to its height, so a stray dot cannot produce an
  /// absurdly thin shape.
  static const _aspectLimit = 20.0;

  /// Fraction of the page's width a signature takes when first placed.
  static const defaultWidthFraction = 0.35;

  /// Crops [strokes] to what was drawn and rescales them into their own box.
  ///
  /// A signature drawn in one corner of the pad should not arrive on the page
  /// with all that empty space around it. Returns null when nothing was drawn.
  static TightenedStrokes? tighten(List<List<Offset>> strokes) {
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    var count = 0;
    for (final stroke in strokes) {
      for (final point in stroke) {
        left = math.min(left, point.dx);
        right = math.max(right, point.dx);
        top = math.min(top, point.dy);
        bottom = math.max(bottom, point.dy);
        count++;
      }
    }
    if (count == 0) return null;

    // A single dot, or a perfectly straight line, has no extent one way; give
    // it a little so it still scales onto a rectangle.
    final width = right - left;
    final height = bottom - top;
    final safeWidth = width > 0 ? width : math.max(height / _aspectLimit, 1.0);
    final safeHeight = height > 0 ? height : math.max(width / _aspectLimit, 1.0);

    return TightenedStrokes(
      strokes: [
        for (final stroke in strokes)
          if (stroke.isNotEmpty)
            [
              for (final point in stroke)
                Offset(
                  width > 0 ? (point.dx - left) / width : 0.5,
                  height > 0 ? (point.dy - top) / height : 0.5,
                ),
            ],
      ],
      aspectRatio: clampAspectRatio(safeWidth / safeHeight),
      width: safeWidth,
      height: safeHeight,
    );
  }

  /// Keeps an aspect ratio within something a page can sensibly hold.
  static double clampAspectRatio(double aspectRatio) {
    if (!aspectRatio.isFinite || aspectRatio <= 0) return 1;
    return aspectRatio.clamp(1 / _aspectLimit, _aspectLimit);
  }

  /// Where a signature lands when it is dropped at [at].
  ///
  /// The rectangle is in normalised page space but has to *look* like
  /// [aspectRatio] on the page, so the page's own proportions come into it:
  /// a normalised square on A4 is a tall rectangle. Centred on the drop point
  /// and nudged back onto the page if it would hang over an edge.
  static Rect placementBounds({
    required Offset at,
    required double aspectRatio,
    required double pageAspectRatio,
    double widthFraction = defaultWidthFraction,
  }) {
    final width = widthFraction.clamp(0.05, 1.0);
    final height = (width / clampAspectRatio(aspectRatio) * pageAspectRatio).clamp(0.01, 1.0);

    var left = at.dx - width / 2;
    var top = at.dy - height / 2;
    left = left.clamp(0.0, math.max(0.0, 1 - width));
    top = top.clamp(0.0, math.max(0.0, 1 - height));
    return Rect.fromLTWH(left, top, width, height);
  }
}
