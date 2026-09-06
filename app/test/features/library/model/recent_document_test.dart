import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/library/model/recent_document.dart';
import 'package:the_pdf_project/features/library/services/recent_document_store.dart';

final _document = RecentDocument(
  key: 'file:/docs/report.pdf',
  displayName: 'report.pdf',
  path: '/docs/report.pdf',
  lastOpenedAt: DateTime.utc(2026, 9, 6, 9, 30),
  pageCount: 12,
);

void main() {
  group('serialisation', () {
    test('survives a round trip', () {
      final restored = RecentDocument.fromJson(_document.toJson());

      expect(restored, _document);
    });

    test('copes with a document whose page count is not known yet', () {
      final unopened = RecentDocument(
        key: _document.key,
        displayName: _document.displayName,
        path: _document.path,
        lastOpenedAt: _document.lastOpenedAt,
      );

      expect(RecentDocument.fromJson(unopened.toJson()).pageCount, isNull);
    });
  });

  group('the store', () {
    test('encodes and decodes a whole list', () {
      final list = [_document, _document.copyWith(pageCount: 3)];

      final restored = SharedPreferencesRecentDocumentStore.decode(
        SharedPreferencesRecentDocumentStore.encode(list),
      );

      expect(restored, list);
    });

    test('one unreadable entry does not lose the rest', () {
      final raw = '[${SharedPreferencesRecentDocumentStore.encode([_document]).substring(1, SharedPreferencesRecentDocumentStore.encode([_document]).length - 1)},'
          '{"key":"broken"}]';

      final restored = SharedPreferencesRecentDocumentStore.decode(raw);

      expect(restored, hasLength(1));
      expect(restored.single.displayName, 'report.pdf');
    });

    test('an in-memory store hands back a copy', () async {
      final store = InMemoryRecentDocumentStore([_document]);

      (await store.load()).clear();

      expect(await store.load(), hasLength(1));
    });
  });

  test('copyWith keeps everything it was not asked to change', () {
    final updated = _document.copyWith(pageCount: 40);

    expect(updated.key, _document.key);
    expect(updated.path, _document.path);
    expect(updated.lastOpenedAt, _document.lastOpenedAt);
    expect(updated.pageCount, 40);
  });
}
