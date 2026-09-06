@Tags(['pdfium'])
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/convert/model/picked_image.dart';
import 'package:the_pdf_project/features/convert/services/image_pdf_builder.dart';

import '../../../support/pdfium_test_support.dart';
import '../../../support/test_images.dart';

/// End-to-end: build a PDF from pictures, then reopen it and look at what came
/// out — page count, page shape, and whether the picture is on it.
void main() {
  const builder = ImagePdfBuilder();

  setUpAll(initializePdfiumForTests);

  late Uint8List landscapePng;
  late Uint8List portraitPng;
  late Uint8List squarePng;

  setUpAll(() async {
    landscapePng = await testPng(width: 400, height: 200);
    portraitPng = await testPng(width: 200, height: 400, color: const Color(0xFFE53935));
    squarePng = await testPng(width: 300, height: 300, color: const Color(0xFF43A047));
  });

  PickedImage image(Uint8List bytes, int width, int height, {String name = 'photo.png'}) =>
      PickedImage(
        id: name,
        displayName: name,
        bytes: bytes,
        pixelWidth: width,
        pixelHeight: height,
      );

  Future<PdfDocument> buildAndOpen(List<PickedImage> images) async {
    final bytes = await builder.build(images);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final document = await PdfDocument.openData(
      bytes,
      sourceName: 'images-${bytes.length}-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(document.dispose);
    return document;
  }

  /// How much of a rendered page is not white.
  ///
  /// Rendered at the page's own shape: asking for a square picture of a tall
  /// page squashes it, and every measurement taken from that is meaningless.
  Future<double> inkedFraction(PdfPage page, {int width = 220}) async {
    final height = (width / page.width * page.height).round();
    final rendered = await page.render(width: width, height: height);
    try {
      var inked = 0;
      final pixels = rendered!.pixels;
      for (var i = 0; i + 3 < pixels.length; i += 4) {
        if (pixels[i] != 0xFF || pixels[i + 1] != 0xFF || pixels[i + 2] != 0xFF) inked++;
      }
      return inked / (pixels.length / 4);
    } finally {
      rendered?.dispose();
    }
  }

  test('one image becomes a one-page PDF', () async {
    final document = await buildAndOpen([image(landscapePng, 400, 200)]);

    expect(document.pages, hasLength(1));
  });

  test('several images become a page each, in the order given', () async {
    final document = await buildAndOpen([
      image(landscapePng, 400, 200, name: 'wide.png'),
      image(portraitPng, 200, 400, name: 'tall.png'),
      image(squarePng, 300, 300, name: 'square.png'),
    ]);

    expect(document.pages, hasLength(3));
    // The order shows in the page shapes: wide, tall, square.
    expect(document.pages[0].width, greaterThan(document.pages[0].height));
    expect(document.pages[1].width, lessThan(document.pages[1].height));
    expect(document.pages[2].width, closeTo(document.pages[2].height, 0.5));
  });

  test('an empty list is refused rather than written as a broken PDF', () {
    expect(() => builder.build(const []), throwsA(isA<StateError>()));
  });

  group('the page', () {
    test('takes the image\'s shape', () async {
      final document = await buildAndOpen([
        image(landscapePng, 400, 200, name: 'wide.png'),
        image(portraitPng, 200, 400, name: 'tall.png'),
      ]);

      expect(document.pages[0].width / document.pages[0].height, closeTo(2, 0.01));
      expect(document.pages[1].width / document.pages[1].height, closeTo(0.5, 0.01));
    });

    test('is a familiar size however many pixels the image has', () async {
      final document = await buildAndOpen([image(landscapePng, 400, 200)]);

      // The long side matches A4's, so pages from different cameras come out
      // comparable rather than measured in thousands of points.
      expect(document.pages.single.width, closeTo(841.89, 0.5));
    });

    test('is covered by the image, edge to edge', () async {
      final document = await buildAndOpen([
        image(landscapePng, 400, 200, name: 'wide.png'),
        image(portraitPng, 200, 400, name: 'tall.png'),
        image(squarePng, 300, 300, name: 'square.png'),
      ]);

      for (final page in document.pages) {
        expect(
          await inkedFraction(page),
          greaterThan(0.99),
          reason: 'page ${page.pageNumber} should be filled by its picture',
        );
      }
    });
  });

  test('the image goes in as it stands, so the document stays small', () async {
    final bytes = await builder.build([image(landscapePng, 400, 200)]);

    // A flat 400x200 picture is a few kilobytes; anything much larger would
    // mean it had been decoded and written out again.
    expect(bytes.length, lessThan(64 * 1024));
  });
}
