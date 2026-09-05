import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/logic/annotation_appearance.dart';

const _blue = Color(0xFF1E88E5);

void main() {
  group('line', () {
    final stream = AnnotationAppearance.line(
      from: const Offset(100, 200),
      to: const Offset(400, 200),
      color: _blue,
      strokeWidth: 3,
    );

    test('moves to the start and draws to the end', () {
      expect(stream.content, contains('100 200 m'));
      expect(stream.content, contains('400 200 l'));
    });

    test('strokes exactly once', () {
      expect('S\n'.allMatches(stream.content), hasLength(1));
    });

    test('sets the stroke colour as PDF components from 0 to 1', () {
      // 0x1E = 30, 0x88 = 136, 0xE5 = 229, each over 255.
      expect(stream.content, contains('0.118 0.533 0.898 RG'));
    });

    test('sets the width and round caps', () {
      expect(stream.content, contains('3 w'));
      expect(stream.content, contains('1 J 1 j'));
    });

    test('balances its graphics state', () {
      expect(stream.content, startsWith('q\n'));
      expect(stream.content.trimRight(), endsWith('Q'));
    });

    test('reports the points it touches', () {
      expect(stream.extent, const [Offset(100, 200), Offset(400, 200)]);
    });
  });

  group('arrow', () {
    final stream = AnnotationAppearance.arrow(
      from: const Offset(100, 200),
      to: const Offset(400, 200),
      color: _blue,
      strokeWidth: 3,
    );

    test('draws the shaft and two barbs', () {
      expect('S\n'.allMatches(stream.content), hasLength(3));
    });

    test('reports the barbs as well as the endpoints, so the box holds them', () {
      expect(stream.extent, hasLength(4));
      // The barbs trail back from the tip and spread either side of the shaft.
      final barbs = stream.extent.skip(2);
      for (final barb in barbs) {
        expect(barb.dx, lessThan(400));
        expect(barb.dx, greaterThan(100));
      }
      expect(barbs.first.dy, isNot(barbs.last.dy));
    });
  });

  group('arrowHead', () {
    test('has no barbs for a zero-length arrow', () {
      expect(
        AnnotationAppearance.arrowHead(
          from: const Offset(10, 10),
          to: const Offset(10, 10),
          strokeWidth: 3,
        ),
        isEmpty,
      );
    });

    test('points back along the shaft, whichever way it runs', () {
      for (final to in const [Offset(200, 100), Offset(0, 100), Offset(100, 300)]) {
        final barbs = AnnotationAppearance.arrowHead(
          from: const Offset(100, 100),
          to: to,
          strokeWidth: 3,
        );

        for (final barb in barbs) {
          // Every barb sits back towards the shaft, not beyond the tip.
          expect((barb - const Offset(100, 100)).distance, lessThan((to - const Offset(100, 100)).distance));
        }
      }
    });

    test('grows with the stroke width', () {
      double reach(double strokeWidth) => AnnotationAppearance.arrowHead(
        from: const Offset(0, 0),
        to: const Offset(300, 0),
        strokeWidth: strokeWidth,
      ).map((barb) => (barb - const Offset(300, 0)).distance).first;

      expect(reach(20), greaterThan(reach(1)));
    });
  });

  test('numbers are written plainly, with no exponents or trailing zeros', () {
    final stream = AnnotationAppearance.line(
      from: const Offset(0.0000001, 12.5),
      to: const Offset(1234.56789, 0),
      color: const Color(0xFF000000),
      strokeWidth: 1,
    );

    expect(stream.content, contains('0 12.5 m'));
    expect(stream.content, contains('1234.568 0 l'));
    expect(stream.content, isNot(contains('e')));
  });
}
