import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/scan/logic/image_filters.dart';
import 'package:the_pdf_project/features/scan/model/scan_filter.dart';

/// Builds RGBA pixels from a list of (red, green, blue) triples.
Uint8List pixelsOf(List<(int, int, int)> colours) {
  final out = Uint8List(colours.length * 4);
  for (var i = 0; i < colours.length; i++) {
    out[i * 4] = colours[i].$1;
    out[i * 4 + 1] = colours[i].$2;
    out[i * 4 + 2] = colours[i].$3;
    out[i * 4 + 3] = 255;
  }
  return out;
}

(int, int, int) colourAt(Uint8List pixels, int index) =>
    (pixels[index * 4], pixels[index * 4 + 1], pixels[index * 4 + 2]);

void main() {
  test('luminance weights green most, the way an eye does', () {
    expect(ImageFilters.luminanceOf(255, 0, 0), lessThan(ImageFilters.luminanceOf(0, 255, 0)));
    expect(ImageFilters.luminanceOf(0, 0, 255), lessThan(ImageFilters.luminanceOf(255, 0, 0)));
    expect(ImageFilters.luminanceOf(255, 255, 255), 255);
    expect(ImageFilters.luminanceOf(0, 0, 0), 0);
  });

  test('every filter leaves the picture it was given alone', () {
    final original = pixelsOf([(10, 20, 30), (200, 210, 220)]);
    final copy = Uint8List.fromList(original);

    for (final filter in ScanFilter.values) {
      ImageFilters.apply(original, filter);
    }

    expect(original, copy);
  });

  test('every filter keeps the picture the same size and fully opaque', () {
    final original = pixelsOf([(10, 20, 30), (200, 210, 220), (128, 64, 32)]);

    for (final filter in ScanFilter.values) {
      final result = ImageFilters.apply(original, filter);

      expect(result.length, original.length, reason: filter.label);
      for (var i = 3; i < result.length; i += 4) {
        expect(result[i], 255, reason: '${filter.label} should not touch transparency');
      }
    }
  });

  group('colour', () {
    test('changes nothing', () {
      final original = pixelsOf([(10, 20, 30), (200, 210, 220)]);

      expect(ImageFilters.apply(original, ScanFilter.colour), original);
    });
  });

  group('greyscale', () {
    test('gives every pixel one shade', () {
      final result = ImageFilters.apply(
        pixelsOf([(255, 0, 0), (0, 255, 0), (0, 0, 255)]),
        ScanFilter.greyscale,
      );

      for (var i = 0; i < 3; i++) {
        final (red, green, blue) = colourAt(result, i);
        expect(red, green);
        expect(green, blue);
      }
    });

    test('keeps a light thing lighter than a dark one', () {
      final result = ImageFilters.apply(
        pixelsOf([(30, 30, 30), (220, 220, 220)]),
        ScanFilter.greyscale,
      );

      expect(colourAt(result, 0).$1, lessThan(colourAt(result, 1).$1));
    });
  });

  group('black and white', () {
    test('leaves only two tones', () {
      final result = ImageFilters.apply(
        pixelsOf([(20, 20, 20), (90, 90, 90), (180, 180, 180), (250, 250, 250)]),
        ScanFilter.blackAndWhite,
      );

      for (var i = 0; i < 4; i++) {
        final value = colourAt(result, i).$1;
        expect(value == 0 || value == 255, isTrue, reason: 'got $value');
      }
    });

    test('puts the ink on one side and the paper on the other', () {
      final result = ImageFilters.apply(
        pixelsOf([(20, 20, 20), (20, 20, 20), (240, 240, 240), (240, 240, 240)]),
        ScanFilter.blackAndWhite,
      );

      expect(colourAt(result, 0).$1, 0);
      expect(colourAt(result, 3).$1, 255);
    });

    test('a page photographed dimly does not come out solid black', () {
      // Nothing here is bright, but there is still ink and paper.
      final result = ImageFilters.apply(
        pixelsOf([(40, 40, 40), (40, 40, 40), (110, 110, 110), (110, 110, 110)]),
        ScanFilter.blackAndWhite,
      );

      expect(colourAt(result, 0).$1, 0);
      expect(colourAt(result, 3).$1, 255);
    });
  });

  group('enhance', () {
    test('pushes the paper towards white and the ink towards black', () {
      final greyish = <(int, int, int)>[
        for (var i = 0; i < 50; i++) (90, 90, 90),
        for (var i = 0; i < 50; i++) (170, 170, 170),
      ];

      final result = ImageFilters.apply(pixelsOf(greyish), ScanFilter.enhance);

      expect(colourAt(result, 0).$1, lessThan(90));
      expect(colourAt(result, 99).$1, greaterThan(170));
    });

    test('keeps colour rather than flattening it to grey', () {
      final result = ImageFilters.apply(
        pixelsOf([
          for (var i = 0; i < 50; i++) (60, 90, 30),
          for (var i = 0; i < 50; i++) (200, 180, 220),
        ]),
        ScanFilter.enhance,
      );

      final (red, green, blue) = colourAt(result, 0);
      expect(red == green && green == blue, isFalse);
    });

    test('leaves a picture with nothing to stretch alone', () {
      final flat = pixelsOf([for (var i = 0; i < 20; i++) (128, 128, 128)]);

      expect(ImageFilters.apply(flat, ScanFilter.enhance), flat);
    });

    test('one blown-out speck does not decide the whole page', () {
      List<(int, int, int)> page({bool withSpeck = false}) => [
        for (var i = 0; i < 50; i++) (80, 80, 80),
        for (var i = 0; i < (withSpeck ? 49 : 50); i++) (180, 180, 180),
        if (withSpeck) (255, 255, 255),
      ];

      final plain = ImageFilters.apply(pixelsOf(page()), ScanFilter.enhance);
      final speckled = ImageFilters.apply(pixelsOf(page(withSpeck: true)), ScanFilter.enhance);

      // The stretch is measured between percentiles, not extremes, so one
      // glare spot leaves the rest of the page where it was.
      expect(colourAt(speckled, 0).$1, colourAt(plain, 0).$1);
      expect(colourAt(speckled, 60).$1, colourAt(plain, 60).$1);
    });
  });

  test('an empty picture is handled without complaint', () {
    for (final filter in ScanFilter.values) {
      expect(ImageFilters.apply(Uint8List(0), filter), isEmpty, reason: filter.label);
    }
  });
}
