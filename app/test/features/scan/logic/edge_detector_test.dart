import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/scan/logic/edge_detector.dart';

import '../../../support/scan_bitmaps.dart';

GreyBitmap greyOf(TestBitmap bitmap) => GreyBitmap.fromRgba(
  rgba: bitmap.pixels,
  width: bitmap.width,
  height: bitmap.height,
);

void main() {
  group('GreyBitmap', () {
    test('reduces colour to how bright it looks', () {
      final bitmap = TestBitmap(4, 4, background: 0)..fillRect(0, 0, 4, 4, value: 255);

      final grey = greyOf(bitmap);

      expect(grey.at(0, 0), 255);
    });

    test('shrinks a large picture, keeping its shape', () {
      final bitmap = TestBitmap(1200, 900);

      final grey = GreyBitmap.fromRgba(
        rgba: bitmap.pixels,
        width: 1200,
        height: 900,
        longestSide: 240,
      );

      expect(grey.width, lessThanOrEqualTo(240));
      expect(grey.width / grey.height, closeTo(1200 / 900, 0.05));
    });

    test('leaves a small picture alone', () {
      final grey = GreyBitmap.fromRgba(
        rgba: TestBitmap(100, 80).pixels,
        width: 100,
        height: 80,
        longestSide: 240,
      );

      expect(grey.width, 100);
      expect(grey.height, 80);
    });
  });

  group('otsuThreshold', () {
    test('lands between two clearly separated groups', () {
      final bitmap = TestBitmap(40, 40, background: 30)..fillRect(0, 0, 40, 20, value: 220);

      final threshold = EdgeDetector.otsuThreshold(greyOf(bitmap));

      // Pixels above the threshold are the bright group, so the split sits at
      // or above the dark shade and below the light one.
      expect(threshold, greaterThanOrEqualTo(30));
      expect(threshold, lessThan(220));
    });
  });

  group('detect', () {
    test('finds an upright page against a darker background', () {
      final bitmap = TestBitmap(400, 300)..fillRect(80, 60, 320, 240);

      final quad = EdgeDetector.detect(greyOf(bitmap))!;

      expect(quad.topLeft.dx, closeTo(80 / 400, 0.03));
      expect(quad.topLeft.dy, closeTo(60 / 300, 0.03));
      expect(quad.bottomRight.dx, closeTo(320 / 400, 0.03));
      expect(quad.bottomRight.dy, closeTo(240 / 300, 0.03));
    });

    test('finds a page photographed at an angle', () {
      final corners = TestBitmap.rotatedRect(
        picture: const Size(400, 300),
        rect: const Size(240, 180),
        degrees: 12,
      );
      final bitmap = TestBitmap(400, 300)..fillQuad(corners);

      final quad = EdgeDetector.detect(greyOf(bitmap))!;

      // Each detected corner should be near the one it came from.
      for (var i = 0; i < 4; i++) {
        final expected = Offset(corners[i].dx / 400, corners[i].dy / 300);
        expect(
          (quad[i] - expected).distance,
          lessThan(0.06),
          reason: 'corner $i: ${quad[i]} vs $expected',
        );
      }
    });

    test('the corners come back in reading order', () {
      final bitmap = TestBitmap(400, 300)..fillRect(80, 60, 320, 240);

      final quad = EdgeDetector.detect(greyOf(bitmap))!;

      expect(quad.topLeft.dx, lessThan(quad.topRight.dx));
      expect(quad.topLeft.dy, lessThan(quad.bottomLeft.dy));
      expect(quad.bottomRight.dx, greaterThan(quad.bottomLeft.dx));
      expect(quad.isConvex, isTrue);
    });

    test('ignores a speck too small to be a page', () {
      final bitmap = TestBitmap(400, 300)..fillRect(190, 140, 210, 160);

      expect(EdgeDetector.detect(greyOf(bitmap)), isNull);
    });

    test('gives up on a picture that is all one shade', () {
      expect(EdgeDetector.detect(greyOf(TestBitmap(200, 200))), isNull);
    });

    test('gives up when the page fills the frame, since cropping gains nothing', () {
      final bitmap = TestBitmap(200, 200)..fillRect(0, 0, 200, 200);

      expect(EdgeDetector.detect(greyOf(bitmap)), isNull);
    });

    test('picks the page over a smaller bright thing beside it', () {
      final bitmap = TestBitmap(400, 300)
        ..fillRect(40, 40, 240, 260)
        ..fillRect(300, 40, 340, 80);

      final quad = EdgeDetector.detect(greyOf(bitmap))!;

      expect(quad.bottomRight.dx, lessThan(0.7), reason: 'the small square is not the page');
    });

    test('a picture too small to hold a page yields nothing', () {
      expect(EdgeDetector.detect(greyOf(TestBitmap(4, 4))), isNull);
    });
  });
}
