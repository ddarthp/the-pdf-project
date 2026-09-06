import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The four corners of a document within a photograph.
///
/// Corners are fractions of the picture, in reading order: top-left,
/// top-right, bottom-right, bottom-left. Fractions rather than pixels so the
/// same quad describes the document whether it is being drawn over a
/// thumbnail, dragged on screen, or used to straighten the full-size photo.
@immutable
class DocumentQuad {
  const DocumentQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// The whole picture — what a scan falls back to when no document stands
  /// out from its background.
  static const full = DocumentQuad(
    topLeft: Offset(0, 0),
    topRight: Offset(1, 0),
    bottomRight: Offset(1, 1),
    bottomLeft: Offset(0, 1),
  );

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  /// The corner at [index] in reading order.
  Offset operator [](int index) => corners[index];

  /// A copy with one corner moved, clamped to the picture.
  DocumentQuad withCorner(int index, Offset position) {
    final moved = [...corners];
    moved[index] = Offset(position.dx.clamp(0.0, 1.0), position.dy.clamp(0.0, 1.0));
    return DocumentQuad(
      topLeft: moved[0],
      topRight: moved[1],
      bottomRight: moved[2],
      bottomLeft: moved[3],
    );
  }

  /// How much of the picture the document covers, 0 to 1.
  ///
  /// Used to decide whether a detected shape is worth trusting: a document
  /// that fills a sliver of the frame is more likely to be a shadow.
  double get area {
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  /// Whether the corners still make a sensible four-sided shape.
  ///
  /// A quad whose corners have been dragged across each other would produce a
  /// folded, unreadable page.
  bool get isConvex {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final c = corners[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross == 0) continue;
      final current = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = current;
      } else if (sign != current) {
        return false;
      }
    }
    return sign != 0;
  }

  /// The straightened page's shape, from the longer of each pair of opposite
  /// edges — the side nearer the camera is the longer one, and cropping to the
  /// shorter would lose part of the page.
  double aspectRatioIn(Size pictureSize) {
    double distance(Offset a, Offset b) => math.sqrt(
      math.pow((a.dx - b.dx) * pictureSize.width, 2) +
          math.pow((a.dy - b.dy) * pictureSize.height, 2),
    );

    final width = math.max(distance(topLeft, topRight), distance(bottomLeft, bottomRight));
    final height = math.max(distance(topLeft, bottomLeft), distance(topRight, bottomRight));
    return height <= 0 ? 1 : width / height;
  }

  Map<String, Object?> toJson() => {
    'corners': [
      for (final corner in corners) [corner.dx, corner.dy],
    ],
  };

  static Offset _offsetFrom(List<Object?> json) =>
      Offset((json[0]! as num).toDouble(), (json[1]! as num).toDouble());

  static DocumentQuad fromJson(Map<String, Object?> json) {
    final corners = [
      for (final corner in json['corners']! as List<Object?>)
        _offsetFrom(corner! as List<Object?>),
    ];
    return DocumentQuad(
      topLeft: corners[0],
      topRight: corners[1],
      bottomRight: corners[2],
      bottomLeft: corners[3],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentQuad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => 'DocumentQuad($topLeft, $topRight, $bottomRight, $bottomLeft)';
}
