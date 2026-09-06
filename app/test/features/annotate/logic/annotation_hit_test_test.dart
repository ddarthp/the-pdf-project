import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/logic/annotation_hit_test.dart';
import 'package:the_pdf_project/features/annotate/model/annotation.dart';

/// A page drawn at its natural size, so document units are PDF points and the
/// numbers in these tests read as real distances.
const pageRect = Rect.fromLTWH(0, 0, 600, 800);
const pageWidth = 600.0;

final _createdAt = DateTime(2026);

bool hits(Annotation annotation, Offset point, {double tolerance = 4}) => AnnotationHitTest.hits(
  annotation,
  point,
  pageRect,
  tolerance: tolerance,
  pageWidthInPoints: pageWidth,
);

InkAnnotation ink({required List<List<Offset>> strokes, double strokeWidth = 4}) => InkAnnotation(
  id: 'ink',
  pageNumber: 1,
  color: const Color(0xFF000000),
  opacity: 1,
  createdAt: _createdAt,
  strokes: strokes,
  strokeWidth: strokeWidth,
);

ShapeAnnotation shape(ShapeKind kind, Offset start, Offset end, {String id = 'shape'}) =>
    ShapeAnnotation(
      id: id,
      pageNumber: 1,
      color: const Color(0xFF000000),
      opacity: 1,
      createdAt: _createdAt,
      kind: kind,
      start: start,
      end: end,
      strokeWidth: 4,
    );

void main() {
  group('ink', () {
    // A horizontal stroke across the middle of the page: y = 400 document.
    final stroke = ink(strokes: [
      const [Offset(0.2, 0.5), Offset(0.8, 0.5)],
    ]);

    test('hits a point on the line', () {
      expect(hits(stroke, const Offset(300, 400)), isTrue);
    });

    test('hits just off the line, within the stroke and tolerance', () {
      expect(hits(stroke, const Offset(300, 405)), isTrue);
    });

    test('misses a point clear of the line', () {
      expect(hits(stroke, const Offset(300, 430)), isFalse);
    });

    test('misses past the ends of the stroke', () {
      expect(hits(stroke, const Offset(60, 400)), isFalse);
    });

    test('a thicker stroke is easier to hit', () {
      final thin = ink(strokes: [const [Offset(0.2, 0.5), Offset(0.8, 0.5)]], strokeWidth: 2);
      final thick = ink(strokes: [const [Offset(0.2, 0.5), Offset(0.8, 0.5)]], strokeWidth: 40);

      expect(hits(thin, const Offset(300, 415)), isFalse);
      expect(hits(thick, const Offset(300, 415)), isTrue);
    });

    test('a single-point stroke is a dot that can still be hit', () {
      final dot = ink(strokes: [const [Offset(0.5, 0.5)]]);

      expect(hits(dot, const Offset(300, 400)), isTrue);
      expect(hits(dot, const Offset(340, 400)), isFalse);
    });
  });

  group('shapes', () {
    test('a line is hit along its length', () {
      final line = shape(ShapeKind.line, const Offset(0.2, 0.2), const Offset(0.8, 0.8));

      expect(hits(line, const Offset(300, 400)), isTrue);
      expect(hits(line, const Offset(300, 600)), isFalse);
    });

    test('a rectangle is grabbed by its edge, not its empty middle', () {
      final rect = shape(ShapeKind.rectangle, const Offset(0.2, 0.2), const Offset(0.8, 0.8));

      expect(hits(rect, const Offset(120, 300)), isTrue, reason: 'on the left edge');
      expect(hits(rect, const Offset(300, 160)), isTrue, reason: 'on the top edge');
      expect(hits(rect, const Offset(300, 400)), isFalse, reason: 'in the middle');
    });

    test('an ellipse is grabbed by its outline', () {
      final ellipse = shape(ShapeKind.ellipse, const Offset(0.2, 0.2), const Offset(0.8, 0.8));

      // Centre (300, 400), radii (180, 240).
      expect(hits(ellipse, const Offset(120, 400)), isTrue, reason: 'left extreme');
      expect(hits(ellipse, const Offset(300, 160)), isTrue, reason: 'top extreme');
      expect(hits(ellipse, const Offset(300, 400)), isFalse, reason: 'centre');
      expect(hits(ellipse, const Offset(130, 170)), isFalse, reason: 'outside the corner');
    });

    test('an arrow behaves like a line', () {
      final arrow = shape(ShapeKind.arrow, const Offset(0.1, 0.1), const Offset(0.9, 0.1));

      expect(hits(arrow, const Offset(300, 80)), isTrue);
      expect(hits(arrow, const Offset(300, 200)), isFalse);
    });
  });

  test('a highlight is hit anywhere inside one of its bands', () {
    final highlight = HighlightAnnotation(
      id: 'h',
      pageNumber: 1,
      color: const Color(0xFFFDD835),
      opacity: 0.4,
      createdAt: _createdAt,
      bands: const [Rect.fromLTRB(0.1, 0.1, 0.9, 0.15), Rect.fromLTRB(0.1, 0.2, 0.5, 0.25)],
    );

    expect(hits(highlight, const Offset(300, 96)), isTrue, reason: 'first band');
    expect(hits(highlight, const Offset(200, 180)), isTrue, reason: 'second band');
    expect(hits(highlight, const Offset(500, 180)), isFalse, reason: 'past the second band');
  });

  test('a sticky note is hit on its marker', () {
    final note = StickyNoteAnnotation(
      id: 'n',
      pageNumber: 1,
      color: const Color(0xFFFB8C00),
      opacity: 1,
      createdAt: _createdAt,
      anchor: const Offset(0.5, 0.5),
      text: 'hello',
    );

    // The marker hangs down and right from its anchor at (300, 400).
    expect(hits(note, const Offset(305, 405)), isTrue);
    expect(hits(note, const Offset(300 - 30, 400)), isFalse);
  });

  test('a text box is hit anywhere inside it', () {
    final box = TextBoxAnnotation(
      id: 't',
      pageNumber: 1,
      color: const Color(0xFF000000),
      opacity: 1,
      createdAt: _createdAt,
      bounds: const Rect.fromLTRB(0.1, 0.1, 0.5, 0.2),
      text: 'note',
      fontSize: 12,
    );

    expect(hits(box, const Offset(200, 120)), isTrue);
    expect(hits(box, const Offset(400, 120)), isFalse);
  });

  group('topmostAt', () {
    test('picks the annotation drawn last where two overlap', () {
      final under = shape(ShapeKind.line, const Offset(0.1, 0.5), const Offset(0.9, 0.5), id: 'under');
      final over = shape(ShapeKind.line, const Offset(0.1, 0.5), const Offset(0.9, 0.5), id: 'over');

      final hit = AnnotationHitTest.topmostAt(
        [under, over],
        const Offset(300, 400),
        pageRect,
        tolerance: 4,
        pageWidthInPoints: pageWidth,
      );

      expect(hit?.id, 'over');
    });

    test('returns nothing when the touch missed everything', () {
      final hit = AnnotationHitTest.topmostAt(
        [shape(ShapeKind.line, const Offset(0.1, 0.1), const Offset(0.2, 0.1))],
        const Offset(500, 700),
        pageRect,
        tolerance: 4,
        pageWidthInPoints: pageWidth,
      );

      expect(hit, isNull);
    });
  });

  test('a bigger tolerance widens what counts as a hit', () {
    final line = shape(ShapeKind.line, const Offset(0.1, 0.5), const Offset(0.9, 0.5));

    expect(hits(line, const Offset(300, 415), tolerance: 4), isFalse);
    expect(hits(line, const Offset(300, 415), tolerance: 20), isTrue);
  });
}
