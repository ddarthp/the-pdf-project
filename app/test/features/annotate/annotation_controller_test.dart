import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/annotate/annotation_controller.dart';
import 'package:the_pdf_project/features/annotate/model/annotation.dart';
import 'package:the_pdf_project/features/annotate/model/annotation_style.dart';
import 'package:the_pdf_project/features/annotate/model/annotation_tool.dart';
import 'package:the_pdf_project/features/annotate/services/annotation_store.dart';

InkAnnotation ink(String id, {int pageNumber = 1, Color color = const Color(0xFF000000)}) =>
    InkAnnotation(
      id: id,
      pageNumber: pageNumber,
      color: color,
      opacity: 1,
      createdAt: DateTime(2026),
      strokes: const [
        [Offset(0.1, 0.1), Offset(0.2, 0.2)],
      ],
      strokeWidth: 3,
    );

void main() {
  late InMemoryAnnotationStore store;
  late AnnotationController controller;

  setUp(() {
    store = InMemoryAnnotationStore();
    // No debounce, so a test can assert on the store straight after an edit.
    controller = AnnotationController(store: store, saveDebounce: Duration.zero);
  });

  tearDown(() => controller.dispose());

  group('editing', () {
    test('adds an annotation and selects it', () {
      controller.add(ink('a'));

      expect(controller.annotations.single.id, 'a');
      expect(controller.selectedId, 'a');
    });

    test('replaces an annotation in place, keeping the order', () {
      controller
        ..add(ink('a'))
        ..add(ink('b'))
        ..replace(ink('a', color: const Color(0xFF1E88E5)));

      expect([for (final a in controller.annotations) a.id], ['a', 'b']);
      expect(controller.annotations.first.color, const Color(0xFF1E88E5));
    });

    test('ignores a replacement for something that is not there', () {
      controller
        ..add(ink('a'))
        ..replace(ink('ghost'));

      expect(controller.annotations, hasLength(1));
    });

    test('removes an annotation and drops the selection with it', () {
      controller
        ..add(ink('a'))
        ..remove('a');

      expect(controller.annotations, isEmpty);
      expect(controller.selectedId, isNull);
    });

    test('removes everything at once', () {
      controller
        ..add(ink('a'))
        ..add(ink('b'))
        ..removeAll();

      expect(controller.hasAnnotations, isFalse);
    });

    test('moves the selection without touching anything else', () {
      controller
        ..add(ink('a'))
        ..add(ink('b'))
        ..select('a')
        ..moveSelectedBy(const Offset(0.1, 0));

      final moved = controller.annotations.first as InkAnnotation;
      final untouched = controller.annotations.last as InkAnnotation;
      expect(moved.strokes.first.first.dx, closeTo(0.2, 1e-9));
      expect(untouched.strokes.first.first.dx, closeTo(0.1, 1e-9));
    });

    test('moving with nothing selected does nothing', () {
      controller
        ..add(ink('a'))
        ..select(null)
        ..moveSelectedBy(const Offset(0.5, 0.5));

      expect((controller.annotations.single as InkAnnotation).strokes.first.first.dx, 0.1);
    });
  });

  group('per page', () {
    test('lists only the annotations on that page', () {
      controller
        ..add(ink('a', pageNumber: 1))
        ..add(ink('b', pageNumber: 2))
        ..add(ink('c', pageNumber: 1));

      expect([for (final a in controller.forPage(1)) a.id], ['a', 'c']);
      expect([for (final a in controller.forPage(2)) a.id], ['b']);
    });

    test('includes the draft so it is painted while being drawn', () {
      controller.setDraft(ink('draft', pageNumber: 2));

      expect(controller.forPage(2), hasLength(1));
      expect(controller.forPage(1), isEmpty);
      expect(controller.annotations, isEmpty, reason: 'a draft is not committed');
    });

    test('committing clears the draft', () {
      controller
        ..setDraft(ink('draft'))
        ..add(ink('a'));

      expect(controller.draft, isNull);
      expect(controller.forPage(1), hasLength(1));
    });
  });

  group('tools and style', () {
    test('changing tool clears the selection unless it is the select tool', () {
      controller
        ..add(ink('a'))
        ..tool = AnnotationTool.eraser;
      expect(controller.selectedId, isNull);

      controller
        ..select('a')
        ..tool = AnnotationTool.select;
      expect(controller.selectedId, 'a');
    });

    test('turning annotation mode off clears the selection', () {
      controller
        ..isEnabled = true
        ..add(ink('a'))
        ..isEnabled = false;

      expect(controller.selectedId, isNull);
    });

    test('restyling applies to the selected annotation as well as the next one', () {
      controller
        ..add(ink('a'))
        ..select('a')
        ..style = const AnnotationStyle(color: Color(0xFF43A047), strokeWidth: 12, opacity: 0.5);

      final restyled = controller.annotations.single as InkAnnotation;
      expect(restyled.color, const Color(0xFF43A047));
      expect(restyled.strokeWidth, 12);
      expect(restyled.opacity, 0.5);
    });

    test('restyling with nothing selected only affects what comes next', () {
      controller
        ..add(ink('a'))
        ..select(null)
        ..style = const AnnotationStyle(color: Color(0xFF43A047));

      expect(controller.annotations.single.color, const Color(0xFF000000));
      expect(controller.style.color, const Color(0xFF43A047));
    });

    test('ids are unique', () {
      final ids = {for (var i = 0; i < 50; i++) controller.newId()};

      expect(ids, hasLength(50));
    });
  });

  group('persistence', () {
    test('writes edits back to the store', () async {
      await controller.loadFor('doc-1');
      controller.add(ink('a'));
      await controller.flush();

      expect(await store.load('doc-1'), hasLength(1));
    });

    test('loads what was stored for a document', () async {
      await store.save('doc-1', [ink('a'), ink('b')]);

      await controller.loadFor('doc-1');

      expect(controller.annotations, hasLength(2));
    });

    test('switching document saves the old one and loads the new', () async {
      await controller.loadFor('doc-1');
      controller.add(ink('a'));

      await controller.loadFor('doc-2');

      expect(controller.annotations, isEmpty);
      expect(await store.load('doc-1'), hasLength(1));
    });

    test('does not write annotations before a document is open', () async {
      controller.add(ink('a'));
      await controller.flush();

      expect(await store.load('doc-1'), isEmpty);
    });

    test('clear empties the screen', () async {
      await controller.loadFor('doc-1');
      controller
        ..add(ink('a'))
        ..clear();

      expect(controller.annotations, isEmpty);
      expect(controller.selectedId, isNull);
    });
  });
}
