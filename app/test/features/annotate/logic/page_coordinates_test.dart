import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/logic/page_coordinates.dart';

void main() {
  // A page laid out 200 units right, 100 down, 400 wide and 800 tall — the
  // kind of rectangle pdfrx hands over for a page part-way down a document.
  const pageRect = Rect.fromLTWH(200, 100, 400, 800);

  group('toNormalized', () {
    test('maps the corners to 0 and 1', () {
      expect(PageCoordinates.toNormalized(pageRect.topLeft, pageRect), Offset.zero);
      expect(PageCoordinates.toNormalized(pageRect.bottomRight, pageRect), const Offset(1, 1));
    });

    test('maps the centre to the middle of the page', () {
      expect(PageCoordinates.toNormalized(pageRect.center, pageRect), const Offset(0.5, 0.5));
    });

    test('reports points off the page as outside 0-1', () {
      expect(PageCoordinates.toNormalized(const Offset(100, 100), pageRect).dx, -0.25);
    });

    test('is safe on a zero-sized page', () {
      expect(PageCoordinates.toNormalized(Offset.zero, Rect.zero), Offset.zero);
    });
  });

  group('round trips', () {
    test('a point survives the trip to normalised space and back', () {
      const point = Offset(321, 456);

      final normalized = PageCoordinates.toNormalized(point, pageRect);

      expect(PageCoordinates.toDocument(normalized, pageRect), point);
    });

    test('a rectangle survives the trip', () {
      const rect = Rect.fromLTWH(250, 300, 120, 200);

      final normalized = PageCoordinates.rectToNormalized(rect, pageRect);

      expect(PageCoordinates.rectToDocument(normalized, pageRect), rect);
    });

    test('the same normalised point lands correctly on a scaled page', () {
      // The same page, zoomed in and scrolled: only the rectangle changes.
      const zoomed = Rect.fromLTWH(-500, -1200, 1600, 3200);
      const normalized = Offset(0.25, 0.75);

      expect(PageCoordinates.toDocument(normalized, pageRect), const Offset(300, 700));
      expect(PageCoordinates.toDocument(normalized, zoomed), const Offset(-100, 1200));
      // Which is the point: the stored coordinates never changed.
      expect(PageCoordinates.toNormalized(const Offset(-100, 1200), zoomed), normalized);
    });
  });

  group('clamping', () {
    test('keeps a stray point on the page', () {
      expect(PageCoordinates.clampToPage(const Offset(-0.4, 1.9)), const Offset(0, 1));
      expect(PageCoordinates.clampToPage(const Offset(0.3, 0.7)), const Offset(0.3, 0.7));
    });

    test('trims a rectangle that hangs off the edge', () {
      expect(
        PageCoordinates.clampRectToPage(const Rect.fromLTRB(-0.2, 0.5, 0.6, 1.4)),
        const Rect.fromLTRB(0, 0.5, 0.6, 1),
      );
    });
  });

  group('finding the page', () {
    const layout = [
      Rect.fromLTWH(0, 0, 400, 800),
      Rect.fromLTWH(0, 810, 400, 800),
      Rect.fromLTWH(0, 1620, 400, 800),
    ];

    test('reports the page a point is on, 1-based', () {
      expect(PageCoordinates.pageNumberAt(const Offset(10, 10), layout), 1);
      expect(PageCoordinates.pageNumberAt(const Offset(10, 900), layout), 2);
      expect(PageCoordinates.pageNumberAt(const Offset(10, 1700), layout), 3);
    });

    test('reports nothing for the gap between pages', () {
      expect(PageCoordinates.pageNumberAt(const Offset(10, 805), layout), isNull);
    });

    test('falls back to the nearest page for a point in the margin', () {
      expect(PageCoordinates.nearestPageNumber(const Offset(10, 805), layout), 1);
      expect(PageCoordinates.nearestPageNumber(const Offset(10, 809), layout), 2);
      expect(PageCoordinates.nearestPageNumber(const Offset(-100, 5000), layout), 3);
    });

    test('has no nearest page in an empty layout', () {
      expect(PageCoordinates.nearestPageNumber(Offset.zero, const []), isNull);
    });
  });

  group('lengthToDocument', () {
    test('scales a thickness in points by how big the page is drawn', () {
      // A 595pt-wide page drawn 1190 units wide is at 2x, so a 3pt stroke is
      // 6 units thick.
      expect(
        PageCoordinates.lengthToDocument(3, const Rect.fromLTWH(0, 0, 1190, 1684), 595),
        6,
      );
    });

    test('is 1:1 when the page is drawn at its natural size', () {
      expect(
        PageCoordinates.lengthToDocument(3, const Rect.fromLTWH(0, 0, 595, 842), 595),
        3,
      );
    });

    test('falls back to the raw value for a page with no width', () {
      expect(PageCoordinates.lengthToDocument(3, pageRect, 0), 3);
    });
  });
}
