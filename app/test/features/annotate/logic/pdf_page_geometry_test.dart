import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/logic/pdf_page_geometry.dart';

void main() {
  // A4 the right way up: 595 x 842 points.
  const upright = PdfPageGeometry(displayWidth: 595, displayHeight: 842, quarterTurns: 0);

  group('an unrotated page', () {
    test('keeps its displayed size', () {
      expect(upright.pageWidth, 595);
      expect(upright.pageHeight, 842);
    });

    test('puts the top-left of the display at the top-left of the page', () {
      // PDF y grows upwards, so the top of the page is y = height.
      expect(upright.toPdfPoint(Offset.zero), const Offset(0, 842));
    });

    test('puts the bottom-right at the origin', () {
      expect(upright.toPdfPoint(const Offset(1, 1)), const Offset(595, 0));
    });

    test('maps the centre to the centre', () {
      expect(upright.toPdfPoint(const Offset(0.5, 0.5)), const Offset(297.5, 421));
    });

    test('turns a rectangle the right way up', () {
      final rect = upright.toPdfRect(const Rect.fromLTRB(0.2, 0.1, 0.6, 0.4));

      expect(rect.left, closeTo(119, 0.001));
      expect(rect.right, closeTo(357, 0.001));
      // The top of the display is the larger y.
      expect(rect.top, closeTo(842 * 0.9, 0.001));
      expect(rect.bottom, closeTo(842 * 0.6, 0.001));
    });
  });

  group('a page carrying /Rotate', () {
    // Displayed landscape, but stored upright: the stored page is 595 x 842.
    const turned90 = PdfPageGeometry(displayWidth: 842, displayHeight: 595, quarterTurns: 1);
    const turned180 = PdfPageGeometry(displayWidth: 595, displayHeight: 842, quarterTurns: 2);
    const turned270 = PdfPageGeometry(displayWidth: 842, displayHeight: 595, quarterTurns: 3);

    test('reports the size the page is stored at, not the size shown', () {
      expect(turned90.pageWidth, 595);
      expect(turned90.pageHeight, 842);
      expect(turned270.pageWidth, 595);
      expect(turned270.pageHeight, 842);
      // Half a turn does not swap anything.
      expect(turned180.pageWidth, 595);
      expect(turned180.pageHeight, 842);
    });

    test('a quarter turn clockwise maps each display corner back to its page corner', () {
      // Turning the stored page 90° clockwise puts its top-left corner at the
      // top-right of the display. Reading that backwards: the display's
      // top-left came from the page's bottom-left, which in PDF coordinates
      // is the origin.
      expect(turned90.toPdfPoint(Offset.zero), const Offset(0, 0));
      // Display top-right ← page top-left, which is y = height.
      expect(turned90.toPdfPoint(const Offset(1, 0)), const Offset(0, 842));
      // Display bottom-right ← page top-right.
      expect(turned90.toPdfPoint(const Offset(1, 1)), const Offset(595, 842));
      // Display bottom-left ← page bottom-right.
      expect(turned90.toPdfPoint(const Offset(0, 1)), const Offset(595, 0));
    });

    test('half a turn flips both axes', () {
      expect(turned180.toPdfPoint(Offset.zero), const Offset(595, 0));
      expect(turned180.toPdfPoint(const Offset(1, 1)), const Offset(0, 842));
    });

    test('three quarter turns are the mirror of one', () {
      expect(turned270.toPdfPoint(Offset.zero), const Offset(595, 842));
      expect(turned270.toPdfPoint(const Offset(1, 1)), const Offset(0, 0));
    });

    test('a rectangle keeps left below right whichever way the page turns', () {
      for (final geometry in [turned90, turned180, turned270]) {
        final rect = geometry.toPdfRect(const Rect.fromLTRB(0.2, 0.1, 0.6, 0.4));

        expect(rect.left, lessThan(rect.right), reason: '$geometry');
        expect(rect.bottom, lessThan(rect.top), reason: '$geometry');
      }
    });

    test('every corner of the display lands inside the stored page', () {
      for (final geometry in [turned90, turned180, turned270]) {
        for (final corner in const [
          Offset.zero,
          Offset(1, 0),
          Offset(0, 1),
          Offset(1, 1),
        ]) {
          final point = geometry.toPdfPoint(corner);
          expect(point.dx, inInclusiveRange(0, geometry.pageWidth));
          expect(point.dy, inInclusiveRange(0, geometry.pageHeight));
        }
      }
    });
  });

  group('PdfPointRect', () {
    test('wraps a set of points', () {
      final rect = PdfPointRect.containing(const [
        Offset(10, 20),
        Offset(50, 5),
        Offset(30, 40),
      ]);

      expect(rect.left, 10);
      expect(rect.right, 50);
      expect(rect.bottom, 5);
      expect(rect.top, 40);
    });

    test('collapses to nothing for no points', () {
      expect(
        PdfPointRect.containing(const []),
        const PdfPointRect(left: 0, bottom: 0, right: 0, top: 0),
      );
    });

    test('inflate grows every side, so a stroke is not clipped', () {
      const rect = PdfPointRect(left: 10, bottom: 10, right: 20, top: 20);

      expect(rect.inflate(5), const PdfPointRect(left: 5, bottom: 5, right: 25, top: 25));
      expect(rect.inflate(5).width, 20);
    });

    test('clampToPage keeps a rectangle on the page', () {
      const rect = PdfPointRect(left: -10, bottom: -10, right: 700, top: 900);

      expect(
        rect.clampToPage(595, 842),
        const PdfPointRect(left: 0, bottom: 0, right: 595, top: 842),
      );
    });
  });
}
