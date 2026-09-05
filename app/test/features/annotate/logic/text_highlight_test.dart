import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/logic/text_highlight.dart';

/// Character rectangles for two lines of five characters, in normalised page
/// space: line one at y 0.10–0.14, line two at y 0.20–0.24.
List<Rect> twoLines() => [
  for (var line = 0; line < 2; line++)
    for (var i = 0; i < 5; i++)
      Rect.fromLTWH(0.1 + i * 0.05, 0.1 + line * 0.1, 0.05, 0.04),
];

void main() {
  group('bandsFor', () {
    test('one band per line of text the drag crosses', () {
      final bands = TextHighlight.bandsFor(twoLines(), const Rect.fromLTRB(0.05, 0.08, 0.9, 0.26));

      expect(bands, hasLength(2));
      expect(bands[0].top, closeTo(0.10, 0.001));
      expect(bands[1].top, closeTo(0.20, 0.001));
    });

    test('a band spans only the characters actually covered', () {
      // Reaches the right edge of the third character and no further.
      final bands = TextHighlight.bandsFor(twoLines(), const Rect.fromLTRB(0.09, 0.09, 0.25, 0.15));

      expect(bands, hasLength(1));
      expect(bands.single.left, closeTo(0.10, 0.001));
      expect(bands.single.right, closeTo(0.25, 0.001));
    });

    test('bands come back ordered down the page', () {
      final bands = TextHighlight.bandsFor(twoLines(), const Rect.fromLTRB(0, 0, 1, 1));

      expect(bands[0].top, lessThan(bands[1].top));
    });

    test('a drag in any direction covers the same text', () {
      final forwards = TextHighlight.bandsFor(twoLines(), const Rect.fromLTRB(0.09, 0.09, 0.4, 0.15));
      final backwards = TextHighlight.bandsFor(twoLines(), const Rect.fromLTRB(0.4, 0.15, 0.09, 0.09));

      expect(backwards, forwards);
    });

    test('a character barely clipped by the drag is left out', () {
      // Overlaps the first character by a sliver of its height.
      final bands = TextHighlight.bandsFor(twoLines(), const Rect.fromLTRB(0.09, 0.09, 0.4, 0.104));

      expect(bands, isEmpty);
    });

    test('nothing to snap to gives no bands, so callers can fall back', () {
      expect(TextHighlight.bandsFor(const [], const Rect.fromLTRB(0, 0, 1, 1)), isEmpty);
      expect(
        TextHighlight.bandsFor(twoLines(), const Rect.fromLTRB(0.8, 0.8, 0.9, 0.9)),
        isEmpty,
      );
    });

    test('characters of differing height still group onto one line', () {
      final rects = [
        const Rect.fromLTWH(0.10, 0.10, 0.05, 0.04),
        // A taller capital on the same baseline.
        const Rect.fromLTWH(0.15, 0.09, 0.05, 0.05),
        const Rect.fromLTWH(0.20, 0.10, 0.05, 0.04),
      ];

      final bands = TextHighlight.bandsFor(rects, const Rect.fromLTRB(0, 0, 1, 1));

      expect(bands, hasLength(1));
      expect(bands.single.left, closeTo(0.10, 0.001));
      expect(bands.single.right, closeTo(0.25, 0.001));
    });
  });

  group('coveredCharIndices', () {
    test('a character only grazed by the drag does not count', () {
      // Overlaps the fourth character by a tenth of its width.
      expect(
        TextHighlight.coveredCharIndices(twoLines(), const Rect.fromLTRB(0.09, 0.09, 0.255, 0.15)),
        [0, 1, 2],
      );
      // A fifth of its width is enough.
      expect(
        TextHighlight.coveredCharIndices(twoLines(), const Rect.fromLTRB(0.09, 0.09, 0.26, 0.15)),
        [0, 1, 2, 3],
      );
    });

    test('reports which characters the drag ran across', () {
      final indices = TextHighlight.coveredCharIndices(
        twoLines(),
        const Rect.fromLTRB(0.09, 0.09, 0.25, 0.15),
      );

      expect(indices, [0, 1, 2]);
    });

    test('spans both lines when the drag does', () {
      final indices = TextHighlight.coveredCharIndices(twoLines(), const Rect.fromLTRB(0, 0, 1, 1));

      expect(indices, List.generate(10, (i) => i));
    });

    test('is empty when nothing was covered', () {
      expect(
        TextHighlight.coveredCharIndices(twoLines(), const Rect.fromLTRB(0.8, 0.8, 0.9, 0.9)),
        isEmpty,
      );
    });
  });
}
