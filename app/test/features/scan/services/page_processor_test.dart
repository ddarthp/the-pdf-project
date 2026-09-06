@Tags(['pdfium'])
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/scan/model/document_quad.dart';
import 'package:the_pdf_project/features/scan/model/scan_filter.dart';
import 'package:the_pdf_project/features/scan/services/page_processor.dart';

import '../../../support/pdfium_test_support.dart';
import '../../../support/scan_bitmaps.dart';

/// The processor is the one part of the scanner that needs Flutter — decoding
/// a photograph and encoding a page — so these run it end to end on synthetic
/// photographs and read the result back.
void main() {
  const processor = PageProcessor();

  setUpAll(initializePdfiumForTests);

  /// A photograph of a pale page on a dark surface.
  Future<Uint8List> photographOfPage({
    List<Offset>? corners,
    Size picture = const Size(400, 300),
    int pageShade = 235,
  }) async {
    final bitmap = TestBitmap(picture.width.toInt(), picture.height.toInt());
    bitmap.fillQuad(
      corners ??
          [
            const Offset(80, 60),
            const Offset(320, 60),
            const Offset(320, 240),
            const Offset(80, 240),
          ],
      value: pageShade,
    );
    return PageProcessor.encodePng(
      pixels: bitmap.pixels,
      width: bitmap.width,
      height: bitmap.height,
    );
  }

  /// Reads a processed page back as pixels.
  Future<TestBitmap> decode(Uint8List png) async {
    final codec = await instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final bitmap = TestBitmap(image.width, image.height);
      bitmap.pixels.setAll(0, data!.buffer.asUint8List());
      return bitmap;
    } finally {
      image.dispose();
    }
  }

  test('finds the page and crops the background away', () async {
    final page = await processor.process(
      photograph: await photographOfPage(),
      id: 'a',
      filter: ScanFilter.colour,
    );

    // The detected page is the middle of the frame, not the whole thing.
    expect(page.quad.topLeft.dx, closeTo(0.2, 0.05));
    expect(page.quad.bottomRight.dy, closeTo(0.8, 0.05));

    // And what comes out is all page: no dark border left over.
    final result = await decode(page.processedBytes);
    expect(result.luminanceAt(result.width ~/ 2, result.height ~/ 2), greaterThan(200));
    expect(result.luminanceAt(2, 2), greaterThan(180));
  });

  test('the straightened page keeps the shape it had on the desk', () async {
    final page = await processor.process(
      photograph: await photographOfPage(),
      id: 'a',
      filter: ScanFilter.colour,
    );

    // The page in the photograph is 240 x 180, so 4:3.
    expect(page.processedWidth / page.processedHeight, closeTo(4 / 3, 0.08));
  });

  test('a page photographed at an angle comes out square', () async {
    final page = await processor.process(
      photograph: await photographOfPage(
        corners: TestBitmap.rotatedRect(
          picture: const Size(400, 300),
          rect: const Size(240, 180),
          degrees: 10,
        ),
      ),
      id: 'a',
      filter: ScanFilter.colour,
    );

    final result = await decode(page.processedBytes);
    // Straightened, the corners of the result are page rather than background.
    for (final (x, y) in [
      (4, 4),
      (result.width - 5, 4),
      (4, result.height - 5),
      (result.width - 5, result.height - 5),
    ]) {
      expect(
        result.luminanceAt(x, y),
        greaterThan(150),
        reason: 'corner $x,$y should be page, not desk',
      );
    }
  });

  test('a photograph with no page in it is kept whole', () async {
    final blank = TestBitmap(200, 200, background: 90);
    final page = await processor.process(
      photograph: await PageProcessor.encodePng(
        pixels: blank.pixels,
        width: 200,
        height: 200,
      ),
      id: 'a',
      filter: ScanFilter.colour,
    );

    expect(page.quad, DocumentQuad.full);
  });

  test('the corners can be moved afterwards and the page redone', () async {
    final page = await processor.process(
      photograph: await photographOfPage(),
      id: 'a',
      filter: ScanFilter.colour,
    );

    final narrowed = await processor.reprocess(
      page,
      quad: const DocumentQuad(
        topLeft: Offset(0.25, 0.25),
        topRight: Offset(0.5, 0.25),
        bottomRight: Offset(0.5, 0.75),
        bottomLeft: Offset(0.25, 0.75),
      ),
    );

    expect(narrowed.id, page.id);
    expect(narrowed.originalBytes, page.originalBytes);
    // Half as wide as it is tall now, where before it was wider than tall.
    expect(narrowed.processedWidth, lessThan(narrowed.processedHeight));
  });

  test('the filter can be changed afterwards', () async {
    final page = await processor.process(
      photograph: await photographOfPage(),
      id: 'a',
      filter: ScanFilter.colour,
    );

    final blackAndWhite = await processor.reprocess(page, filter: ScanFilter.blackAndWhite);

    expect(blackAndWhite.filter, ScanFilter.blackAndWhite);
    expect(blackAndWhite.quad, page.quad, reason: 'the corners are not disturbed');
    final result = await decode(blackAndWhite.processedBytes);
    for (final value in [
      result.luminanceAt(result.width ~/ 2, result.height ~/ 2),
      result.luminanceAt(4, 4),
    ]) {
      expect(value == 0 || value == 255, isTrue, reason: 'two tones only, got $value');
    }
  });

  test('a page is never blown up beyond the detail the photograph had', () async {
    final page = await processor.process(
      photograph: await photographOfPage(),
      id: 'a',
      filter: ScanFilter.colour,
    );

    expect(page.processedWidth, lessThanOrEqualTo(400));
    expect(page.processedWidth, lessThanOrEqualTo(PageProcessor.maxOutputSide));
  });
}
