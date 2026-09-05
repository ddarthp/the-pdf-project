import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/signature/logic/signature_geometry.dart';

void main() {
  group('tighten', () {
    test('crops a drawing to what was actually drawn', () {
      // A stroke in the middle of a 100x100 pad.
      final tightened = SignatureGeometry.tighten([
        const [Offset(20, 40), Offset(60, 40), Offset(60, 60)],
      ])!;

      // The stroke's own box is 40 wide and 20 tall, so its corners become
      // 0 and 1 whatever the pad around it was.
      expect(tightened.strokes.single, const [Offset(0, 0), Offset(1, 0), Offset(1, 1)]);
      expect(tightened.aspectRatio, 2);
      // The box is also reported in the pad's own pixels, so a pad-sized
      // stroke width can be turned into a fraction of the signature.
      expect(tightened.width, 40);
      expect(tightened.height, 20);
    });

    test('keeps several strokes in one shared box', () {
      final tightened = SignatureGeometry.tighten([
        const [Offset(0, 0), Offset(50, 0)],
        const [Offset(50, 100), Offset(100, 100)],
      ])!;

      expect(tightened.strokes[0], const [Offset(0, 0), Offset(0.5, 0)]);
      expect(tightened.strokes[1], const [Offset(0.5, 1), Offset(1, 1)]);
      expect(tightened.aspectRatio, 1);
    });

    test('handles a perfectly flat stroke without dividing by zero', () {
      final tightened = SignatureGeometry.tighten([
        const [Offset(0, 50), Offset(100, 50)],
      ])!;

      for (final point in tightened.strokes.single) {
        expect(point.dy, 0.5);
      }
      expect(tightened.aspectRatio.isFinite, isTrue);
      expect(tightened.aspectRatio, greaterThan(1));
    });

    test('handles a single dot', () {
      final tightened = SignatureGeometry.tighten([
        const [Offset(10, 10)],
      ])!;

      expect(tightened.strokes.single.single, const Offset(0.5, 0.5));
      expect(tightened.aspectRatio, 1);
    });

    test('reports nothing when nothing was drawn', () {
      expect(SignatureGeometry.tighten(const []), isNull);
      expect(SignatureGeometry.tighten(const [[]]), isNull);
    });
  });

  group('clampAspectRatio', () {
    test('leaves a sensible ratio alone', () {
      expect(SignatureGeometry.clampAspectRatio(3), 3);
    });

    test('reins in something absurdly thin or wide', () {
      expect(SignatureGeometry.clampAspectRatio(1000), 20);
      expect(SignatureGeometry.clampAspectRatio(0.0001), 0.05);
    });

    test('falls back to a square for a ratio that is not a number', () {
      expect(SignatureGeometry.clampAspectRatio(double.nan), 1);
      expect(SignatureGeometry.clampAspectRatio(0), 1);
    });
  });

  group('placementBounds', () {
    // A4 in portrait: wider than it is tall by 595/842.
    const a4 = 595 / 842;

    test('centres the signature on where it was dropped', () {
      final bounds = SignatureGeometry.placementBounds(
        at: const Offset(0.5, 0.5),
        aspectRatio: 3,
        pageAspectRatio: a4,
      );

      expect(bounds.center.dx, closeTo(0.5, 1e-9));
      expect(bounds.center.dy, closeTo(0.5, 1e-9));
    });

    test('takes a fixed share of the page width', () {
      final bounds = SignatureGeometry.placementBounds(
        at: const Offset(0.5, 0.5),
        aspectRatio: 3,
        pageAspectRatio: a4,
      );

      expect(bounds.width, closeTo(SignatureGeometry.defaultWidthFraction, 1e-9));
    });

    test('comes out the right shape once the page proportions are applied', () {
      const aspectRatio = 3.0;
      final bounds = SignatureGeometry.placementBounds(
        at: const Offset(0.5, 0.5),
        aspectRatio: aspectRatio,
        pageAspectRatio: a4,
      );

      // Normalised units are stretched: a square on the page is not a square
      // in these numbers. Converting back to page units must give the shape
      // the signature was captured in.
      expect((bounds.width * 595) / (bounds.height * 842), closeTo(aspectRatio, 1e-6));
    });

    test('nudges a signature dropped at the edge back onto the page', () {
      for (final at in const [Offset(0, 0), Offset(1, 1), Offset(0.02, 0.98)]) {
        final bounds = SignatureGeometry.placementBounds(
          at: at,
          aspectRatio: 3,
          pageAspectRatio: a4,
        );

        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(1 + 1e-9));
        expect(bounds.bottom, lessThanOrEqualTo(1 + 1e-9));
      }
    });

    test('a tall signature stays on the page rather than overflowing it', () {
      final bounds = SignatureGeometry.placementBounds(
        at: const Offset(0.5, 0.5),
        aspectRatio: 0.05,
        pageAspectRatio: a4,
      );

      expect(bounds.height, lessThanOrEqualTo(1));
    });
  });
}
