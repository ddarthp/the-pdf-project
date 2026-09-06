import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../logic/edge_detector.dart';
import '../logic/image_filters.dart';
import '../logic/perspective.dart';
import '../model/document_quad.dart';
import '../model/scan_filter.dart';
import '../model/scanned_page.dart';

/// Turns a photograph of a page into a scan.
///
/// Decoding and encoding are the only parts that need Flutter; the finding,
/// straightening and filtering are all pure functions this class strings
/// together, which is why they can be tested without a camera.
class PageProcessor {
  const PageProcessor();

  /// The longest side of a straightened page, in pixels.
  ///
  /// Enough to read small print, without turning a ten-page scan into
  /// something too big to send.
  static const maxOutputSide = 2200;

  /// Reads a photograph, finds the page in it, and straightens and filters it.
  Future<ScannedPage> process({
    required Uint8List photograph,
    required String id,
    DocumentQuad? quad,
    ScanFilter filter = ScanFilter.enhance,
  }) async {
    final source = await _decode(photograph);
    try {
      final found =
          quad ??
          EdgeDetector.detect(
            GreyBitmap.fromRgba(
              rgba: source.pixels,
              width: source.width,
              height: source.height,
            ),
          ) ??
          DocumentQuad.full;

      final straightened = straighten(source: source, quad: found);
      final filtered = ImageFilters.apply(straightened.pixels, filter);
      final bytes = await encodePng(
        pixels: filtered,
        width: straightened.width,
        height: straightened.height,
      );

      return ScannedPage(
        id: id,
        originalBytes: photograph,
        originalWidth: source.width,
        originalHeight: source.height,
        quad: found,
        filter: filter,
        processedBytes: bytes,
        processedWidth: straightened.width,
        processedHeight: straightened.height,
      );
    } finally {
      // Nothing to release: the pixels are plain bytes by this point.
    }
  }

  /// Redoes a page with different corners or a different filter, without
  /// touching the camera again.
  Future<ScannedPage> reprocess(
    ScannedPage page, {
    DocumentQuad? quad,
    ScanFilter? filter,
  }) => process(
    photograph: page.originalBytes,
    id: page.id,
    quad: quad ?? page.quad,
    filter: filter ?? page.filter,
  );

  /// Pulls the quadrilateral out of the photograph as a flat rectangle.
  ///
  /// For each pixel of the result, the matching point in the photograph is
  /// found through the perspective map and sampled with its four neighbours,
  /// so the page comes out smooth rather than stepped.
  static RawImage straighten({required RawImage source, required DocumentQuad quad}) {
    final aspectRatio = quad.aspectRatioIn(
      ui.Size(source.width.toDouble(), source.height.toDouble()),
    );
    final (width, height) = _outputSize(source, aspectRatio);

    final map = PerspectiveMap.ontoQuad(quad);
    final out = Uint8List(width * height * 4);

    for (var y = 0; y < height; y++) {
      final v = (y + 0.5) / height;
      for (var x = 0; x < width; x++) {
        final point = map.map((x + 0.5) / width, v);
        _sample(
          source,
          point.dx * source.width - 0.5,
          point.dy * source.height - 0.5,
          out,
          (y * width + x) * 4,
        );
      }
    }
    return RawImage(pixels: out, width: width, height: height);
  }

  /// A result no bigger than the page was in the photograph, and no bigger
  /// than [maxOutputSide]: making it larger would invent detail.
  static (int, int) _outputSize(RawImage source, double aspectRatio) {
    final longest = math.min(math.max(source.width, source.height), maxOutputSide);
    return aspectRatio >= 1
        ? (longest, math.max(1, (longest / aspectRatio).round()))
        : (math.max(1, (longest * aspectRatio).round()), longest);
  }

  /// Bilinear sample: the weighted blend of the four pixels around a point.
  static void _sample(RawImage source, double x, double y, Uint8List out, int offset) {
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;

    for (var channel = 0; channel < 4; channel++) {
      final topLeft = _channelAt(source, x0, y0, channel);
      final topRight = _channelAt(source, x0 + 1, y0, channel);
      final bottomLeft = _channelAt(source, x0, y0 + 1, channel);
      final bottomRight = _channelAt(source, x0 + 1, y0 + 1, channel);
      final top = topLeft + (topRight - topLeft) * fx;
      final bottom = bottomLeft + (bottomRight - bottomLeft) * fx;
      out[offset + channel] = (top + (bottom - top) * fy).round().clamp(0, 255);
    }
  }

  /// One channel of one pixel, with points outside the picture taking the
  /// value of the nearest edge rather than reading past the end.
  static double _channelAt(RawImage source, int x, int y, int channel) {
    final clampedX = x.clamp(0, source.width - 1);
    final clampedY = y.clamp(0, source.height - 1);
    return source.pixels[(clampedY * source.width + clampedX) * 4 + channel].toDouble();
  }

  Future<RawImage> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('That photograph could not be read.');
      return RawImage(
        pixels: data.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }

  /// Encodes raw pixels as PNG.
  ///
  /// Lossless, which matters for a page of text: the blocking a lossy format
  /// leaves around letters is exactly what makes a scan hard to read.
  static Future<Uint8List> encodePng({
    required Uint8List pixels,
    required int width,
    required int height,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('That page could not be saved.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

/// A picture as plain bytes: four channels per pixel, row by row.
class RawImage {
  const RawImage({required this.pixels, required this.width, required this.height});

  final Uint8List pixels;
  final int width;
  final int height;
}
