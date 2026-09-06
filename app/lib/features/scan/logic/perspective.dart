import 'dart:ui';

import '../model/document_quad.dart';

/// Maps the unit square onto a quadrilateral.
///
/// Straightening a photographed page means knowing, for every pixel of the
/// flat result, which pixel of the photograph it came from — and a page seen
/// at an angle is a *projective* transform of a rectangle, not a stretch. The
/// closed-form solution below is Heckbert's: eight coefficients that carry the
/// unit square onto any four points, with no matrix solving.
///
/// Pure arithmetic, so the awkward cases — a square-on page, a folded quad —
/// can be checked directly.
class PerspectiveMap {
  const PerspectiveMap._(this._a, this._b, this._c, this._d, this._e, this._f, this._g, this._h);

  final double _a;
  final double _b;
  final double _c;
  final double _d;
  final double _e;
  final double _f;
  final double _g;
  final double _h;

  /// Builds the map that carries (0,0), (1,0), (1,1), (0,1) onto the quad's
  /// corners, in that order.
  factory PerspectiveMap.ontoQuad(DocumentQuad quad) {
    final p0 = quad.topLeft;
    final p1 = quad.topRight;
    final p2 = quad.bottomRight;
    final p3 = quad.bottomLeft;

    // How far the quad is from being a parallelogram. When it is one, the
    // transform is affine and the projective terms drop out.
    final dx3 = p0.dx - p1.dx + p2.dx - p3.dx;
    final dy3 = p0.dy - p1.dy + p2.dy - p3.dy;

    if (dx3.abs() < 1e-12 && dy3.abs() < 1e-12) {
      return PerspectiveMap._(
        p1.dx - p0.dx,
        p2.dx - p1.dx,
        p0.dx,
        p1.dy - p0.dy,
        p2.dy - p1.dy,
        p0.dy,
        0,
        0,
      );
    }

    final dx1 = p1.dx - p2.dx;
    final dx2 = p3.dx - p2.dx;
    final dy1 = p1.dy - p2.dy;
    final dy2 = p3.dy - p2.dy;
    final denominator = dx1 * dy2 - dx2 * dy1;
    if (denominator == 0) {
      // Three corners in a line: there is no sensible transform, so fall back
      // to leaving the picture alone.
      return const PerspectiveMap._(1, 0, 0, 0, 1, 0, 0, 0);
    }

    final g = (dx3 * dy2 - dx2 * dy3) / denominator;
    final h = (dx1 * dy3 - dx3 * dy1) / denominator;
    return PerspectiveMap._(
      p1.dx - p0.dx + g * p1.dx,
      p3.dx - p0.dx + h * p3.dx,
      p0.dx,
      p1.dy - p0.dy + g * p1.dy,
      p3.dy - p0.dy + h * p3.dy,
      p0.dy,
      g,
      h,
    );
  }

  /// Where the point [u], [v] of the unit square lands on the quad.
  Offset map(double u, double v) {
    final w = _g * u + _h * v + 1;
    if (w == 0) return Offset.zero;
    return Offset((_a * u + _b * v + _c) / w, (_d * u + _e * v + _f) / w);
  }
}
