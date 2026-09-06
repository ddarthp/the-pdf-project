import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/model/annotation.dart';
import 'package:the_pdf_project/features/annotate/services/annotation_store.dart';

InkAnnotation ink(String id) => InkAnnotation(
  id: id,
  pageNumber: 1,
  color: const Color(0xFFE53935),
  opacity: 1,
  createdAt: DateTime.utc(2026),
  strokes: const [
    [Offset(0.1, 0.1), Offset(0.2, 0.2)],
  ],
  strokeWidth: 3,
);

void main() {
  group('encode and decode', () {
    test('a document of annotations survives the round trip', () {
      final annotations = [ink('a'), ink('b')];

      final restored = SharedPreferencesAnnotationStore.decode(
        SharedPreferencesAnnotationStore.encode(annotations),
      );

      expect([for (final a in restored) a.id], ['a', 'b']);
    });

    test('an empty document round-trips to nothing', () {
      expect(SharedPreferencesAnnotationStore.decode(SharedPreferencesAnnotationStore.encode([])), isEmpty);
    });

    test('one unreadable record does not take the rest down with it', () {
      final good = jsonDecode(SharedPreferencesAnnotationStore.encode([ink('a')])) as List<Object?>;
      final raw = jsonEncode([
        good.single,
        {'type': 'not-a-thing', 'id': 'bad', 'page': 1, 'color': 0, 'opacity': 1.0,
         'createdAt': '2026-01-01T00:00:00.000Z'},
      ]);

      final restored = SharedPreferencesAnnotationStore.decode(raw);

      expect(restored, hasLength(1));
      expect(restored.single.id, 'a');
    });
  });

  group('InMemoryAnnotationStore', () {
    test('keeps annotations apart per document', () async {
      final store = InMemoryAnnotationStore();

      await store.save('doc-1', [ink('a')]);
      await store.save('doc-2', [ink('b'), ink('c')]);

      expect(await store.load('doc-1'), hasLength(1));
      expect(await store.load('doc-2'), hasLength(2));
    });

    test('reports nothing for a document never annotated', () async {
      expect(await InMemoryAnnotationStore().load('doc-1'), isEmpty);
    });

    test('hands back a copy, so the caller cannot mutate the store', () async {
      final store = InMemoryAnnotationStore();
      await store.save('doc-1', [ink('a')]);

      (await store.load('doc-1')).clear();

      expect(await store.load('doc-1'), hasLength(1));
    });
  });
}
