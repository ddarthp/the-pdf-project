@Tags(['pdfium'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/viewer/logic/pdfrx_layout_adapter.dart';
import 'package:the_pdf_project/features/viewer/model/reading_mode.dart';

/// End-to-end check that the PDFium engine is wired up: open a real PDF from
/// disk, read its structure and pull text out of it — the same path the viewer
/// uses for rendering, the outline panel and in-document search.
///
/// Regenerate the fixture with:
///   dart run tool/generate_fixture_pdf.dart test/fixtures/sample.pdf
void main() {
  const fixture = 'test/fixtures/sample.pdf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // path_provider has no implementation under `flutter test`, so point
    // PDFium's cache at a temp directory before initialising it.
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp
        .createTempSync('pdfrx_test_cache')
        .path;
    await pdfrxFlutterInitialize();
  });

  test('opens a document and reports its pages', () async {
    final document = await PdfDocument.openFile(fixture);
    addTearDown(document.dispose);

    expect(document.pages, hasLength(3));
    expect(document.pages.first.width, greaterThan(0));
    expect(document.pages.first.height, greaterThan(0));
    expect(document.isEncrypted, isFalse);
  });

  test('extracts page text, which is what in-document search searches', () async {
    final document = await PdfDocument.openFile(fixture);
    addTearDown(document.dispose);

    final pageText = await document.pages[1].loadStructuredText();

    expect(pageText.fullText, contains('haystack'));
  });

  test('reports an empty outline for a document without bookmarks', () async {
    final document = await PdfDocument.openFile(fixture);
    addTearDown(document.dispose);

    expect(await document.loadOutline(), isEmpty);
  });

  test('lays real pages out differently per reading mode', () async {
    final document = await PdfDocument.openFile(fixture);
    addTearDown(document.dispose);
    const params = PdfViewerParams();

    final continuous = PdfrxLayoutAdapter.layout(
      ReadingMode.continuousScroll,
      document.pages,
      params,
    );
    final single = PdfrxLayoutAdapter.layout(ReadingMode.singlePage, document.pages, params);

    expect(continuous.pageLayouts, hasLength(3));
    expect(single.pageLayouts, hasLength(3));
    // Continuous stacks downwards; single page runs left to right.
    expect(continuous.pageLayouts[1].top, greaterThan(continuous.pageLayouts[0].top));
    expect(continuous.pageLayouts[1].left, continuous.pageLayouts[0].left);
    expect(single.pageLayouts[1].left, greaterThan(single.pageLayouts[0].left));
    expect(single.pageLayouts[1].top, single.pageLayouts[0].top);
    expect(continuous.documentSize.height, greaterThan(single.documentSize.height));
    expect(single.documentSize.width, greaterThan(continuous.documentSize.width));
  });
}
