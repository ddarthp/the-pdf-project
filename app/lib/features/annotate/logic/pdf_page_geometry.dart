import 'dart:ui';

/// Converts normalised page coordinates into PDF page coordinates.
///
/// The two spaces disagree on almost everything. Annotations are stored as a
/// fraction of the page *as displayed*, with the origin at the top-left and y
/// growing downwards. A PDF page measures in points from the bottom-left with
/// y growing upwards, and stores everything **unrotated** — a page carrying
/// `/Rotate 90` is written the tall way round and turned only when shown.
///
/// This is the one place that gap is bridged, kept free of FFI so it can be
/// tested on its own.
class PdfPageGeometry {
  const PdfPageGeometry({
    required this.displayWidth,
    required this.displayHeight,
    required this.quarterTurns,
  });

  /// Page width as displayed, in points — what pdfrx reports as `page.width`.
  final double displayWidth;

  /// Page height as displayed, in points.
  final double displayHeight;

  /// The page's own `/Rotate`, in clockwise quarter turns (0–3).
  final int quarterTurns;

  bool get _isTurnedOnItsSide => quarterTurns.isOdd;

  /// Page width before rotation, which is what PDF coordinates use.
  double get pageWidth => _isTurnedOnItsSide ? displayHeight : displayWidth;

  /// Page height before rotation.
  double get pageHeight => _isTurnedOnItsSide ? displayWidth : displayHeight;

  /// A point on the displayed page, as a PDF page coordinate in points.
  Offset toPdfPoint(Offset normalized) {
    final (ux, uy) = _unrotate(normalized);
    return Offset(ux * pageWidth, (1 - uy) * pageHeight);
  }

  /// A rectangle on the displayed page, as PDF page coordinates.
  ///
  /// Rotation can swap which corner is which, so the result is normalised back
  /// into left ≤ right and bottom ≤ top.
  PdfPointRect toPdfRect(Rect normalized) {
    final a = toPdfPoint(normalized.topLeft);
    final b = toPdfPoint(normalized.bottomRight);
    return PdfPointRect(
      left: a.dx < b.dx ? a.dx : b.dx,
      bottom: a.dy < b.dy ? a.dy : b.dy,
      right: a.dx > b.dx ? a.dx : b.dx,
      top: a.dy > b.dy ? a.dy : b.dy,
    );
  }

  /// Undoes the page's rotation: where a displayed point sits on the page as
  /// it is actually stored.
  (double, double) _unrotate(Offset normalized) => switch (quarterTurns & 3) {
    1 => (normalized.dy, 1 - normalized.dx),
    2 => (1 - normalized.dx, 1 - normalized.dy),
    3 => (1 - normalized.dy, normalized.dx),
    _ => (normalized.dx, normalized.dy),
  };
}

/// A rectangle in PDF page coordinates: y grows upwards, so [top] is the
/// larger value. Deliberately not a [Rect], which assumes the opposite.
class PdfPointRect {
  const PdfPointRect({
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
  });

  /// The rectangle covering every point in [points].
  factory PdfPointRect.containing(Iterable<Offset> points) {
    var left = double.infinity;
    var bottom = double.infinity;
    var right = double.negativeInfinity;
    var top = double.negativeInfinity;
    for (final point in points) {
      if (point.dx < left) left = point.dx;
      if (point.dx > right) right = point.dx;
      if (point.dy < bottom) bottom = point.dy;
      if (point.dy > top) top = point.dy;
    }
    if (left > right) return const PdfPointRect(left: 0, bottom: 0, right: 0, top: 0);
    return PdfPointRect(left: left, bottom: bottom, right: right, top: top);
  }

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;

  double get height => top - bottom;

  /// Grows the rectangle by [amount] on every side, so a stroke drawn on the
  /// boundary is not clipped by the annotation's own bounding box.
  PdfPointRect inflate(double amount) => PdfPointRect(
    left: left - amount,
    bottom: bottom - amount,
    right: right + amount,
    top: top + amount,
  );

  /// Keeps the rectangle inside a page [width] × [height] points.
  PdfPointRect clampToPage(double width, double height) => PdfPointRect(
    left: left.clamp(0.0, width),
    bottom: bottom.clamp(0.0, height),
    right: right.clamp(0.0, width),
    top: top.clamp(0.0, height),
  );

  @override
  bool operator ==(Object other) =>
      other is PdfPointRect &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, bottom, right, top);

  @override
  String toString() => 'PdfPointRect(l: $left, b: $bottom, r: $right, t: $top)';
}
