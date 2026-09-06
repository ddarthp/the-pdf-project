import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/library/logic/recent_documents.dart';
import 'package:the_pdf_project/features/library/model/recent_document.dart';

RecentDocument document(String name, {int minutesAgo = 0, int? pageCount}) => RecentDocument(
  key: 'file:/docs/$name.pdf',
  displayName: '$name.pdf',
  path: '/docs/$name.pdf',
  lastOpenedAt: DateTime.utc(2026, 9, 6, 12).subtract(Duration(minutes: minutesAgo)),
  pageCount: pageCount,
);

List<String> namesOf(List<RecentDocument> documents) =>
    [for (final document in documents) document.displayName];

void main() {
  group('promote', () {
    test('puts the newest document first', () {
      final list = RecentDocuments.promote([document('a'), document('b')], document('c'));

      expect(namesOf(list), ['c.pdf', 'a.pdf', 'b.pdf']);
    });

    test('moves a document already in the list rather than duplicating it', () {
      final list = RecentDocuments.promote(
        [document('a'), document('b'), document('c')],
        document('c', minutesAgo: -5),
      );

      expect(namesOf(list), ['c.pdf', 'a.pdf', 'b.pdf']);
    });

    test('keeps the newer timestamp when a document is reopened', () {
      final reopened = document('a', minutesAgo: -30);

      final list = RecentDocuments.promote([document('a', minutesAgo: 60)], reopened);

      expect(list.single.lastOpenedAt, reopened.lastOpenedAt);
    });

    test('drops the oldest once the list is full', () {
      var list = <RecentDocument>[];
      for (var i = 0; i < 5; i++) {
        list = RecentDocuments.promote(list, document('doc$i'), maxEntries: 3);
      }

      expect(namesOf(list), ['doc4.pdf', 'doc3.pdf', 'doc2.pdf']);
    });

    test('leaves the original list alone', () {
      final original = [document('a')];

      RecentDocuments.promote(original, document('b'));

      expect(original, hasLength(1));
    });
  });

  group('remove', () {
    test('takes a document out by key', () {
      final list = RecentDocuments.remove([document('a'), document('b')], 'file:/docs/a.pdf');

      expect(namesOf(list), ['b.pdf']);
    });

    test('ignores a key that is not there', () {
      final list = RecentDocuments.remove([document('a')], 'file:/docs/ghost.pdf');

      expect(list, hasLength(1));
    });
  });

  group('withPageCount', () {
    test('fills in the count for one document', () {
      final list = RecentDocuments.withPageCount(
        [document('a'), document('b')],
        'file:/docs/a.pdf',
        12,
      );

      expect(list.first.pageCount, 12);
      expect(list.last.pageCount, isNull);
    });

    test('changes nothing for a document that is not listed', () {
      final original = [document('a', pageCount: 3)];

      expect(RecentDocuments.withPageCount(original, 'file:/docs/ghost.pdf', 9), original);
    });
  });

  group('droppedPaths', () {
    test('reports what the list no longer refers to', () {
      final before = [document('a'), document('b'), document('c')];
      final after = [document('a'), document('c')];

      expect(RecentDocuments.droppedPaths(before, after), ['/docs/b.pdf']);
    });

    test('reports nothing when the list only grew', () {
      final before = [document('a')];
      final after = [document('b'), document('a')];

      expect(RecentDocuments.droppedPaths(before, after), isEmpty);
    });

    test('does not report a path that is still there under a promoted entry', () {
      final before = [document('a', minutesAgo: 60)];
      final after = RecentDocuments.promote(before, document('a'));

      expect(RecentDocuments.droppedPaths(before, after), isEmpty);
    });
  });
}
