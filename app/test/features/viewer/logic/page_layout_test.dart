import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/viewer/logic/page_layout.dart';

void main() {
  group('PageLayouts.vertical', () {
    test('stacks pages top to bottom with margins between them', () {
      final result = PageLayouts.vertical(const [Size(100, 200), Size(100, 150)], 10);

      expect(result.pageRects, [
        const Rect.fromLTWH(10, 10, 100, 200),
        const Rect.fromLTWH(10, 220, 100, 150),
      ]);
      expect(result.documentSize, const Size(120, 380));
    });

    test('centres narrower pages against the widest page', () {
      final result = PageLayouts.vertical(const [Size(200, 100), Size(100, 100)], 0);

      expect(result.pageRects[0].left, 0);
      expect(result.pageRects[1].left, 50);
      expect(result.documentSize.width, 200);
    });

    test('handles an empty document', () {
      final result = PageLayouts.vertical(const [], 8);

      expect(result.pageRects, isEmpty);
      expect(result.documentSize, Size.zero);
    });
  });

  group('PageLayouts.horizontalPaged', () {
    test('gives every page an identically sized slot', () {
      final result = PageLayouts.horizontalPaged(const [Size(100, 200), Size(80, 100)], 10);

      expect(result.pageRects[0], const Rect.fromLTWH(10, 10, 100, 200));
      // Second slot starts one slot (maxWidth + margin) further right, and the
      // narrower/shorter page is centred inside it.
      expect(result.pageRects[1], const Rect.fromLTWH(130, 60, 80, 100));
      expect(result.documentSize, const Size(230, 220));
    });

    test('handles an empty document', () {
      final result = PageLayouts.horizontalPaged(const [], 8);

      expect(result.pageRects, isEmpty);
      expect(result.documentSize, Size.zero);
    });
  });

  group('PageLayouts.verticalSpreads', () {
    test('pairs pages side by side and stacks the spreads', () {
      final result = PageLayouts.verticalSpreads(
        const [Size(100, 200), Size(100, 200), Size(100, 200), Size(100, 200)],
        10,
      );

      // First spread: two columns of 100 separated by the 10pt margin.
      expect(result.pageRects[0], const Rect.fromLTWH(10, 10, 100, 200));
      expect(result.pageRects[1], const Rect.fromLTWH(120, 10, 100, 200));
      // Second spread sits below the first.
      expect(result.pageRects[2], const Rect.fromLTWH(10, 220, 100, 200));
      expect(result.pageRects[3], const Rect.fromLTWH(120, 220, 100, 200));
      expect(result.documentSize, const Size(230, 430));
    });

    test('leaves an odd final page alone in the left column', () {
      final result = PageLayouts.verticalSpreads(
        const [Size(100, 200), Size(100, 200), Size(100, 200)],
        10,
      );

      expect(result.pageRects, hasLength(3));
      expect(result.pageRects[2], const Rect.fromLTWH(10, 220, 100, 200));
      // The document is still two columns wide, so spreads stay aligned.
      expect(result.documentSize, const Size(230, 430));
    });

    test('centres pages of differing size within their row and column', () {
      final result = PageLayouts.verticalSpreads(const [Size(200, 100), Size(100, 50)], 0);

      expect(result.pageRects[0], const Rect.fromLTWH(0, 0, 200, 100));
      // Narrower and shorter page: centred in its 200-wide column and in the
      // 100-tall row.
      expect(result.pageRects[1], const Rect.fromLTWH(250, 25, 100, 50));
    });

    test('handles an empty document', () {
      final result = PageLayouts.verticalSpreads(const [], 8);

      expect(result.pageRects, isEmpty);
      expect(result.documentSize, Size.zero);
    });
  });

  group('PageLayouts.pageNumberForOffset', () {
    final rects = PageLayouts.horizontalPaged(
      const [Size(100, 100), Size(100, 100), Size(100, 100)],
      10,
    ).pageRects;

    test('returns the page whose slot centre is nearest', () {
      expect(PageLayouts.pageNumberForOffset(centerX: rects[0].center.dx, pageRects: rects), 1);
      expect(PageLayouts.pageNumberForOffset(centerX: rects[2].center.dx, pageRects: rects), 3);
    });

    test('rounds to the closer neighbour when between two pages', () {
      final justPastMiddle = (rects[0].center.dx + rects[1].center.dx) / 2 + 1;

      expect(PageLayouts.pageNumberForOffset(centerX: justPastMiddle, pageRects: rects), 2);
    });

    test('clamps beyond the ends of the document', () {
      expect(PageLayouts.pageNumberForOffset(centerX: -1000, pageRects: rects), 1);
      expect(PageLayouts.pageNumberForOffset(centerX: 100000, pageRects: rects), 3);
    });

    test('falls back to page 1 for an empty layout', () {
      expect(PageLayouts.pageNumberForOffset(centerX: 0, pageRects: const []), 1);
    });
  });
}
