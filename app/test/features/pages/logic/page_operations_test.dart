import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/pages/logic/page_operations.dart';
import 'package:the_pdf_project/features/pages/model/page_plan_entry.dart';

/// A plan of [count] pages from one document, ids `p0`, `p1`, …
List<PagePlanEntry> plan(int count) => [
  for (var i = 0; i < count; i++)
    SourcePageEntry(id: 'p$i', sourceId: 'doc', pageNumber: i + 1),
];

List<String> idsOf(List<PagePlanEntry> plan) => [for (final entry in plan) entry.id];

void main() {
  group('delete', () {
    test('removes the selected pages and keeps the rest in order', () {
      expect(idsOf(PageOperations.delete(plan(4), {1, 2})), ['p0', 'p3']);
    });

    test('ignores indices outside the plan', () {
      expect(idsOf(PageOperations.delete(plan(2), {5, -1})), ['p0', 'p1']);
    });

    test('leaves the input untouched', () {
      final original = plan(3);
      PageOperations.delete(original, {0});
      expect(idsOf(original), ['p0', 'p1', 'p2']);
    });
  });

  group('extract', () {
    test('keeps only the selected pages, in plan order', () {
      expect(idsOf(PageOperations.extract(plan(5), {3, 0, 1})), ['p0', 'p1', 'p3']);
    });

    test('is empty when nothing is selected', () {
      expect(PageOperations.extract(plan(3), const {}), isEmpty);
    });
  });

  group('reorder', () {
    test('moves a page downwards', () {
      expect(idsOf(PageOperations.reorder(plan(4), 0, 2)), ['p1', 'p2', 'p0', 'p3']);
    });

    test('moves a page upwards', () {
      expect(idsOf(PageOperations.reorder(plan(4), 3, 1)), ['p0', 'p3', 'p1', 'p2']);
    });

    test('is a no-op when the page does not move', () {
      expect(idsOf(PageOperations.reorder(plan(3), 1, 1)), ['p0', 'p1', 'p2']);
    });

    test('ignores an out-of-range source index', () {
      expect(idsOf(PageOperations.reorder(plan(3), 9, 0)), ['p0', 'p1', 'p2']);
    });
  });

  group('selectionAfterReorder', () {
    test('follows the moved page', () {
      expect(PageOperations.selectionAfterReorder(0, 2, {0}), {2});
    });

    test('shifts pages the move stepped over', () {
      // Moving p0 down to index 2 pulls p1 and p2 up one place each.
      expect(PageOperations.selectionAfterReorder(0, 2, {1, 2}), {0, 1});
      // Moving p3 up to index 1 pushes p1 and p2 down one place each.
      expect(PageOperations.selectionAfterReorder(3, 1, {1, 2}), {2, 3});
    });

    test('leaves untouched pages where they are', () {
      expect(PageOperations.selectionAfterReorder(0, 1, {5}), {5});
    });
  });

  group('rotate', () {
    test('turns only the selected pages', () {
      final rotated = PageOperations.rotate(plan(3), {1}, 1);

      expect(rotated[0].quarterTurns, 0);
      expect(rotated[1].quarterTurns, 1);
      expect(rotated[2].quarterTurns, 0);
    });

    test('accumulates turns and wraps at a full circle', () {
      var rotated = PageOperations.rotate(plan(1), {0}, 1);
      rotated = PageOperations.rotate(rotated, {0}, 1);
      expect(rotated.single.quarterTurns, 2);

      rotated = PageOperations.rotate(rotated, {0}, 2);
      expect(rotated.single.quarterTurns, 0);
    });

    test('turns anticlockwise for negative values', () {
      expect(PageOperations.rotate(plan(1), {0}, -1).single.quarterTurns, 3);
    });
  });

  group('insertAll and append', () {
    final blank = BlankPageEntry(id: 'blank', width: 595, height: 842);

    test('inserts in the middle', () {
      expect(idsOf(PageOperations.insertAll(plan(3), 1, [blank])), [
        'p0',
        'blank',
        'p1',
        'p2',
      ]);
    });

    test('clamps an index past the end', () {
      expect(idsOf(PageOperations.insertAll(plan(2), 99, [blank])), ['p0', 'p1', 'blank']);
    });

    test('append puts merged pages at the end', () {
      final merged = PageOperations.append(plan(2), [
        const SourcePageEntry(id: 'q0', sourceId: 'other', pageNumber: 1),
      ]);

      expect(idsOf(merged), ['p0', 'p1', 'q0']);
    });
  });

  group('insertionPointAfter', () {
    test('is the end of the plan with nothing selected', () {
      expect(PageOperations.insertionPointAfter(plan(3), const {}), 3);
    });

    test('is just past the last selected page', () {
      expect(PageOperations.insertionPointAfter(plan(5), {1, 3}), 4);
    });
  });
}
