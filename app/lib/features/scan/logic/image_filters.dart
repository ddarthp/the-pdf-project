import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/scan_filter.dart';

/// Turns a photograph of a page into something that reads like a scan.
///
/// Every filter is a pass over raw RGBA, in place on a copy, so each is a pure
/// function of the pixels going in — no decoding, no canvas, nothing to mock.
abstract final class ImageFilters {
  /// Applies [filter] and returns new pixels; the input is left alone.
  static Uint8List apply(Uint8List rgba, ScanFilter filter) => switch (filter) {
    ScanFilter.colour => Uint8List.fromList(rgba),
    ScanFilter.greyscale => _greyscale(rgba),
    ScanFilter.blackAndWhite => _blackAndWhite(rgba),
    ScanFilter.enhance => _enhance(rgba),
  };

  /// How bright a colour looks, weighted the way an eye sees it.
  static int luminanceOf(int red, int green, int blue) =>
      (red * 0.299 + green * 0.587 + blue * 0.114).round().clamp(0, 255);

  static Uint8List _greyscale(Uint8List rgba) {
    final out = Uint8List.fromList(rgba);
    for (var i = 0; i + 3 < out.length; i += 4) {
      final grey = luminanceOf(out[i], out[i + 1], out[i + 2]);
      out[i] = grey;
      out[i + 1] = grey;
      out[i + 2] = grey;
    }
    return out;
  }

  /// Two tones, split at the brightness that best separates ink from paper.
  ///
  /// The threshold is measured from this page rather than fixed, so a photo
  /// taken in poor light does not come out entirely black.
  static Uint8List _blackAndWhite(Uint8List rgba) {
    final threshold = otsuThresholdOf(rgba);
    final out = Uint8List.fromList(rgba);
    for (var i = 0; i + 3 < out.length; i += 4) {
      final value = luminanceOf(out[i], out[i + 1], out[i + 2]) > threshold ? 255 : 0;
      out[i] = value;
      out[i + 1] = value;
      out[i + 2] = value;
    }
    return out;
  }

  /// Colour, with the paper pushed to white and the ink to black.
  ///
  /// The stretch runs between the fifth and ninety-fifth percentiles rather
  /// than the darkest and lightest pixels, so one glare spot or one speck of
  /// dust cannot decide the whole page's contrast.
  static Uint8List _enhance(Uint8List rgba) {
    final (low, high) = _percentiles(rgba, 0.05, 0.95);
    final range = high - low;
    final out = Uint8List.fromList(rgba);
    if (range < 8) return out;

    // A lookup table costs 256 sums instead of one per pixel.
    final curve = Uint8List(256);
    for (var value = 0; value < 256; value++) {
      curve[value] = (((value - low) / range) * 255).round().clamp(0, 255);
    }
    for (var i = 0; i + 3 < out.length; i += 4) {
      out[i] = curve[out[i]];
      out[i + 1] = curve[out[i + 1]];
      out[i + 2] = curve[out[i + 2]];
    }
    return out;
  }

  /// The brightness levels below which [lower] and [upper] of the picture sit.
  static (int, int) _percentiles(Uint8List rgba, double lower, double upper) {
    final histogram = List<int>.filled(256, 0);
    var count = 0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      histogram[luminanceOf(rgba[i], rgba[i + 1], rgba[i + 2])]++;
      count++;
    }
    if (count == 0) return (0, 255);

    var low = 0;
    var high = 255;
    var seen = 0;
    for (var value = 0; value < 256; value++) {
      seen += histogram[value];
      if (seen >= count * lower) {
        low = value;
        break;
      }
    }
    seen = 0;
    for (var value = 255; value >= 0; value--) {
      seen += histogram[value];
      if (seen >= count * (1 - upper)) {
        high = value;
        break;
      }
    }
    return (low, math.max(high, low + 1));
  }

  /// The brightness that best separates a picture into two groups, by Otsu's
  /// method. Shared with the edge detector's idea of paper against its background.
  static int otsuThresholdOf(Uint8List rgba) {
    final histogram = List<int>.filled(256, 0);
    var total = 0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      histogram[luminanceOf(rgba[i], rgba[i + 1], rgba[i + 2])]++;
      total++;
    }
    if (total == 0) return 127;

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
      final variance =
          backgroundWeight *
          foregroundWeight *
          math.pow(backgroundSum / backgroundWeight - (sum - backgroundSum) / foregroundWeight, 2);
      if (variance > bestVariance) {
        bestVariance = variance.toDouble();
        best = t;
      }
    }
    return best;
  }
}
