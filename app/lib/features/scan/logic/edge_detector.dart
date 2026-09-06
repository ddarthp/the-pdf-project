import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../model/document_quad.dart';

/// A picture reduced to one brightness value per pixel.
///
/// The detector works on this rather than on colour: paper is defined by being
/// lighter than what it sits on, and dropping to brightness makes that the
/// only thing being measured.
class GreyBitmap {
  const GreyBitmap({required this.pixels, required this.width, required this.height});

  /// One byte per pixel, row by row from the top.
  final Uint8List pixels;

  final int width;
  final int height;

  int at(int x, int y) => pixels[y * width + x];

  /// Builds a brightness map from raw RGBA, shrinking as it goes.
  ///
  /// Detection does not need detail — it needs the shape of a large pale
  /// region — and working at a few hundred pixels keeps it quick on a phone.
  factory GreyBitmap.fromRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    int longestSide = 240,
  }) {
    final step = math.max(1, (math.max(width, height) / longestSide).ceil());
    final scaledWidth = math.max(1, width ~/ step);
    final scaledHeight = math.max(1, height ~/ step);
    final pixels = Uint8List(scaledWidth * scaledHeight);

    for (var y = 0; y < scaledHeight; y++) {
      for (var x = 0; x < scaledWidth; x++) {
        final source = ((y * step) * width + x * step) * 4;
        // Rec. 601 luma: how bright a colour looks, not its average.
        pixels[y * scaledWidth + x] =
            (rgba[source] * 0.299 + rgba[source + 1] * 0.587 + rgba[source + 2] * 0.114)
                .round()
                .clamp(0, 255);
      }
    }
    return GreyBitmap(pixels: pixels, width: scaledWidth, height: scaledHeight);
  }
}

/// Finds the page in a photograph.
///
/// Documents are photographed as a pale rectangle against a darker background,
/// so the page is the largest bright region and its corners are the four
/// points of that region furthest towards each corner of the frame. That is
/// far less machinery than tracing edges and fitting lines, and it is what
/// makes the whole thing a pure function over a bitmap — testable without a
/// camera, a plugin, or a photograph.
///
/// It gives up rather than guessing: a region that is too small, too ragged or
/// nearly the whole frame yields nothing, and the caller keeps the picture
/// whole.
abstract final class EdgeDetector {
  /// A detected page must cover at least this much of the frame to be
  /// believed. Less than this and it is more likely a highlight or a shadow.
  static const minimumArea = 0.12;

  /// Above this it is not a page against a background — it is the whole
  /// photograph, and cropping to it would achieve nothing.
  static const maximumArea = 0.985;

  /// The page in [bitmap], or null if none stands out.
  static DocumentQuad? detect(GreyBitmap bitmap) {
    if (bitmap.width < 8 || bitmap.height < 8) return null;

    final threshold = otsuThreshold(bitmap);
    final region = _largestBrightRegion(bitmap, threshold);
    if (region == null) return null;

    final quad = _cornersOf(region, bitmap);
    if (!quad.isConvex) return null;
    if (quad.area < minimumArea || quad.area > maximumArea) return null;
    return quad;
  }

  /// The brightness that best separates a picture into two groups.
  ///
  /// Otsu's method: the split where the two sides are each as uniform as
  /// possible. It needs no tuning, which matters when the same code has to
  /// cope with a page on a desk and a page in shadow.
  static int otsuThreshold(GreyBitmap bitmap) {
    final histogram = List<int>.filled(256, 0);
    for (final value in bitmap.pixels) {
      histogram[value]++;
    }

    final total = bitmap.pixels.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    var backgroundWeight = 0;
    var backgroundSum = 0.0;
    var bestVariance = -1.0;
    var best = 127;

    for (var t = 0; t < 256; t++) {
      backgroundWeight += histogram[t];
      if (backgroundWeight == 0) continue;
      final foregroundWeight = total - backgroundWeight;
      if (foregroundWeight == 0) break;

      backgroundSum += t * histogram[t];
      final backgroundMean = backgroundSum / backgroundWeight;
      final foregroundMean = (sum - backgroundSum) / foregroundWeight;
      final variance =
          backgroundWeight * foregroundWeight * math.pow(backgroundMean - foregroundMean, 2);
      if (variance > bestVariance) {
        bestVariance = variance.toDouble();
        best = t;
      }
    }
    return best;
  }

  /// The pixels of the largest connected group brighter than [threshold].
  ///
  /// Flood filled from every unvisited bright pixel; the biggest group wins.
  static List<int>? _largestBrightRegion(GreyBitmap bitmap, int threshold) {
    final visited = Uint8List(bitmap.width * bitmap.height);
    List<int>? largest;

    for (var start = 0; start < visited.length; start++) {
      if (visited[start] == 1 || bitmap.pixels[start] <= threshold) continue;

      final region = <int>[];
      final queue = <int>[start];
      visited[start] = 1;
      while (queue.isNotEmpty) {
        final index = queue.removeLast();
        region.add(index);
        final x = index % bitmap.width;
        final y = index ~/ bitmap.width;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= bitmap.width || ny >= bitmap.height) continue;
          final neighbour = ny * bitmap.width + nx;
          if (visited[neighbour] == 1 || bitmap.pixels[neighbour] <= threshold) continue;
          visited[neighbour] = 1;
          queue.add(neighbour);
        }
      }

      if (largest == null || region.length > largest.length) largest = region;
    }
    return largest;
  }

  /// The four corners of a region.
  ///
  /// The corner nearest the frame's top-left is the point with the smallest
  /// x + y; the bottom-right has the largest. The other two fall out of x - y
  /// the same way. It costs one pass and, for anything roughly rectangular,
  /// lands on the actual corners.
  static DocumentQuad _cornersOf(List<int> region, GreyBitmap bitmap) {
    var topLeft = region.first;
    var bottomRight = region.first;
    var topRight = region.first;
    var bottomLeft = region.first;

    int sumOf(int index) => index % bitmap.width + index ~/ bitmap.width;
    int differenceOf(int index) => index % bitmap.width - index ~/ bitmap.width;

    for (final index in region) {
      if (sumOf(index) < sumOf(topLeft)) topLeft = index;
      if (sumOf(index) > sumOf(bottomRight)) bottomRight = index;
      if (differenceOf(index) > differenceOf(topRight)) topRight = index;
      if (differenceOf(index) < differenceOf(bottomLeft)) bottomLeft = index;
    }

    Offset toFraction(int index) => Offset(
      (index % bitmap.width + 0.5) / bitmap.width,
      (index ~/ bitmap.width + 0.5) / bitmap.height,
    );

    return DocumentQuad(
      topLeft: toFraction(topLeft),
      topRight: toFraction(topRight),
      bottomRight: toFraction(bottomRight),
      bottomLeft: toFraction(bottomLeft),
    );
  }
}
