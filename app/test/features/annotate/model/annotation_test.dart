import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/model/annotation.dart';

final _createdAt = DateTime.utc(2026, 9, 5, 12, 30);

final samples = <String, Annotation>{
  'ink': InkAnnotation(
    id: 'a1',
    pageNumber: 2,
    color: const Color(0xFFE53935),
    opacity: 0.9,
    createdAt: _createdAt,
    strokes: const [
      [Offset(0.1, 0.2), Offset(0.3, 0.4)],
      [Offset(0.5, 0.6)],
    ],
    strokeWidth: 3,
  ),
  'shape': ShapeAnnotation(
    id: 'a2',
    pageNumber: 1,
    color: const Color(0xFF1E88E5),
    opacity: 1,
    createdAt: _createdAt,
    kind: ShapeKind.arrow,
    start: const Offset(0.1, 0.1),
    end: const Offset(0.8, 0.6),
    strokeWidth: 6,
  ),
  'highlight': HighlightAnnotation(
    id: 'a3',
    pageNumber: 3,
    color: const Color(0xFFFDD835),
    opacity: 0.4,
    createdAt: _createdAt,
    bands: const [Rect.fromLTRB(0.1, 0.2, 0.9, 0.24)],
    text: 'the quick brown fox',
  ),
  'textBox': TextBoxAnnotation(
    id: 'a4',
    pageNumber: 1,
    color: const Color(0xFF000000),
    opacity: 1,
    createdAt: _createdAt,
    bounds: const Rect.fromLTRB(0.1, 0.1, 0.6, 0.2),
    text: 'remember this',
    fontSize: 12,
  ),
  'stickyNote': StickyNoteAnnotation(
    id: 'a5',
    pageNumber: 4,
    color: const Color(0xFFFB8C00),
    opacity: 1,
    createdAt: _createdAt,
    anchor: const Offset(0.44, 0.55),
    text: 'ask about this',
  ),
};

void main() {
  group('serialisation', () {
    for (final entry in samples.entries) {
      test('${entry.key} survives a JSON round trip', () {
        final restored = Annotation.fromJson(entry.value.toJson());

        expect(restored.runtimeType, entry.value.runtimeType);
        expect(restored.id, entry.value.id);
        expect(restored.pageNumber, entry.value.pageNumber);
        expect(restored.color, entry.value.color);
        expect(restored.opacity, entry.value.opacity);
        expect(restored.createdAt, entry.value.createdAt);
        // Geometry is what matters most; compare the serialised form again so
        // every field is covered without hand-listing them per type.
        expect(restored.toJson(), entry.value.toJson());
      });
    }

    test('an unknown type is rejected rather than silently dropped', () {
      expect(
        () => Annotation.fromJson({
          'type': 'hologram',
          'id': 'x',
          'page': 1,
          'color': 0xFF000000,
          'opacity': 1.0,
          'createdAt': _createdAt.toIso8601String(),
        }),
        throwsFormatException,
      );
    });
  });

  group('movedBy', () {
    test('shifts every ink point', () {
      final moved = samples['ink']!.movedBy(const Offset(0.1, -0.05)) as InkAnnotation;

      expect(moved.strokes[0][0].dx, closeTo(0.2, 1e-9));
      expect(moved.strokes[0][0].dy, closeTo(0.15, 1e-9));
      expect(moved.strokes[1][0].dx, closeTo(0.6, 1e-9));
      expect(moved.strokes[1][0].dy, closeTo(0.55, 1e-9));
    });

    test('shifts both ends of a shape', () {
      final moved = samples['shape']!.movedBy(const Offset(0.1, 0.1)) as ShapeAnnotation;

      expect(moved.start, const Offset(0.2, 0.2));
      expect(moved.end.dx, closeTo(0.9, 1e-9));
    });

    test('shifts every highlight band', () {
      final moved = samples['highlight']!.movedBy(const Offset(0, 0.1)) as HighlightAnnotation;

      expect(moved.bands.single.top, closeTo(0.3, 1e-9));
    });

    test('keeps identity, page and text', () {
      final moved = samples['stickyNote']!.movedBy(const Offset(0.1, 0.1));

      expect(moved.id, 'a5');
      expect(moved.pageNumber, 4);
      expect((moved as StickyNoteAnnotation).text, 'ask about this');
    });
  });

  group('restyled', () {
    test('recolours without moving anything', () {
      final restyled = samples['ink']!.restyled(color: const Color(0xFF43A047), opacity: 0.5);

      expect(restyled.color, const Color(0xFF43A047));
      expect(restyled.opacity, 0.5);
      expect(restyled.normalizedBounds, samples['ink']!.normalizedBounds);
    });

    test('changes stroke width on ink and shapes', () {
      expect((samples['ink']!.restyled(strokeWidth: 12) as InkAnnotation).strokeWidth, 12);
      expect((samples['shape']!.restyled(strokeWidth: 1) as ShapeAnnotation).strokeWidth, 1);
    });

    test('thickness resizes the lettering of a text box', () {
      final restyled = samples['textBox']!.restyled(strokeWidth: 6) as TextBoxAnnotation;

      expect(restyled.fontSize, 24);
    });
  });

  group('normalizedBounds', () {
    test('wraps every ink point', () {
      expect(samples['ink']!.normalizedBounds, const Rect.fromLTRB(0.1, 0.2, 0.5, 0.6));
    });

    test('wraps every highlight band', () {
      expect(samples['highlight']!.normalizedBounds, const Rect.fromLTRB(0.1, 0.2, 0.9, 0.24));
    });

    test('is a point for a sticky note, which is anchored not sized', () {
      expect(samples['stickyNote']!.normalizedBounds.size, Size.zero);
    });
  });

  group('summary', () {
    test('shows the text of a note', () {
      expect(samples['stickyNote']!.summary, 'ask about this');
    });

    test('shows the highlighted text', () {
      expect(samples['highlight']!.summary, 'the quick brown fox');
    });

    test('falls back to the kind of thing it is', () {
      expect(samples['ink']!.summary, 'Drawing');
      expect(samples['shape']!.summary, 'Arrow');
    });
  });
}
