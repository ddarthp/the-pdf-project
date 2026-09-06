import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/logic/resize_handles.dart';

void main() {
  const bounds = Rect.fromLTRB(100, 100, 300, 200);

  group('at', () {
    test('finds each corner handle, which sits just outside the bounds', () {
      const inset = ResizeHandles.inset;

      expect(
        ResizeHandles.at(bounds, const Offset(100 - inset, 100 - inset), 5),
        ResizeHandle.topLeft,
      );
      expect(
        ResizeHandles.at(bounds, const Offset(300 + inset, 100 - inset), 5),
        ResizeHandle.topRight,
      );
      expect(
        ResizeHandles.at(bounds, const Offset(100 - inset, 200 + inset), 5),
        ResizeHandle.bottomLeft,
      );
      expect(
        ResizeHandles.at(bounds, const Offset(300 + inset, 200 + inset), 5),
        ResizeHandle.bottomRight,
      );
    });

    test('allows a touch within the tolerance', () {
      expect(ResizeHandles.at(bounds, const Offset(96, 96), 12), ResizeHandle.topLeft);
    });

    test('finds nothing in the middle or well outside', () {
      expect(ResizeHandles.at(bounds, const Offset(200, 150), 12), isNull);
      expect(ResizeHandles.at(bounds, const Offset(0, 0), 12), isNull);
    });

    test('picks the nearer of two handles when they are close together', () {
      const thin = Rect.fromLTRB(100, 100, 110, 200);

      expect(ResizeHandles.at(thin, const Offset(99, 92), 30), ResizeHandle.topLeft);
      expect(ResizeHandles.at(thin, const Offset(120, 92), 30), ResizeHandle.topRight);
    });
  });

  group('resize', () {
    test('drags a corner while the opposite one stays put', () {
      final resized = ResizeHandles.resize(bounds, ResizeHandle.bottomRight, const Offset(400, 260));

      expect(resized, const Rect.fromLTRB(100, 100, 400, 260));
    });

    test('dragging the top-left leaves the bottom-right where it was', () {
      final resized = ResizeHandles.resize(bounds, ResizeHandle.topLeft, const Offset(50, 40));

      expect(resized, const Rect.fromLTRB(50, 40, 300, 200));
    });

    test('dragging past the opposite corner flips rather than inverts', () {
      final resized = ResizeHandles.resize(bounds, ResizeHandle.topLeft, const Offset(400, 300));

      expect(resized.left, 300);
      expect(resized.top, 200);
      expect(resized.width, 100);
      expect(resized.height, 100);
    });

    test('never shrinks below the minimum, in either direction', () {
      final tiny = ResizeHandles.resize(
        bounds,
        ResizeHandle.bottomRight,
        const Offset(100, 100),
        minimum: 20,
      );

      expect(tiny.width, 20);
      expect(tiny.height, 20);
      // Still anchored to the corner that was staying put.
      expect(tiny.topLeft, const Offset(100, 100));
    });

    test('keeps the minimum on the correct side of a flipped drag', () {
      final flipped = ResizeHandles.resize(
        bounds,
        ResizeHandle.topLeft,
        const Offset(299, 199),
        minimum: 20,
      );

      // Anchored at the bottom-right, so the minimum grows up and left.
      expect(flipped, const Rect.fromLTRB(280, 180, 300, 200));
    });
  });
}
