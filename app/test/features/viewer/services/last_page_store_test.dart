import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/viewer/services/last_page_store.dart';

void main() {
  test('reports no bookmark for an unseen document', () async {
    final store = InMemoryLastPageStore();

    expect(await store.lastPage('file:/a.pdf'), isNull);
  });

  test('keeps a separate page per document', () async {
    final store = InMemoryLastPageStore();

    await store.saveLastPage('file:/a.pdf', 7);
    await store.saveLastPage('file:/b.pdf', 2);

    expect(await store.lastPage('file:/a.pdf'), 7);
    expect(await store.lastPage('file:/b.pdf'), 2);
  });

  test('overwrites the page as the reader moves on', () async {
    final store = InMemoryLastPageStore();

    await store.saveLastPage('file:/a.pdf', 7);
    await store.saveLastPage('file:/a.pdf', 8);

    expect(await store.lastPage('file:/a.pdf'), 8);
  });
}
