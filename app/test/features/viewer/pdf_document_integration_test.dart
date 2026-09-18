@Tags(['pdfium'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/viewer/logic/pdfrx_layout_adapter.dart';
import 'package:the_pdf_project/features/viewer/model/reading_mode.dart';

import '../../support/pdfium_test_support.dart';

/// End-to-end check that the PDFium engine is wired up: open a real PDF from
/// disk, read its structure and pull text out of it — the same path the viewer
/// uses for rendering, the outline panel and in-document search.
///
/// Regenerate the fixtures with:
///   dart run tool/generate_fixture_pdf.dart test/fixtures/sample.pdf
///   dart run tool/generate_encrypted_fixture_pdf.dart test/fixtures/encrypted.pdf
void main() {
  const fixture = 'test/fixtures/sample.pdf';
  const encryptedFixture = 'test/fixtures/encrypted.pdf';
  const encryptedPassword = 'letmein';

  setUpAll(initializePdfiumForTests);

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

  group('password-protected documents', () {
    test('open once the right password is supplied', () async {
      final document = await PdfDocument.openFile(
        encryptedFixture,
        passwordProvider: () => encryptedPassword,
      );
      addTearDown(document.dispose);

      expect(document.isEncrypted, isTrue);
      expect(document.pages, hasLength(1));
      expect((await document.pages.first.loadStructuredText()).fullText, contains('Locked'));
    });

    test('report a password error when the reader gives up', () async {
      await expectLater(
        PdfDocument.openFile(encryptedFixture, passwordProvider: () => null),
        throwsA(isA<PdfPasswordException>()),
      );
    });

    test('keep asking until the provider returns the right password', () async {
      final attempts = <String?>[];
      final passwords = <String?>['wrong', 'alsowrong', encryptedPassword];

      final document = await PdfDocument.openFile(
        encryptedFixture,
        passwordProvider: () {
          final next = passwords.removeAt(0);
          attempts.add(next);
          return next;
        },
      );
      addTearDown(document.dispose);

      expect(attempts, ['wrong', 'alsowrong', encryptedPassword]);
      expect(document.pages, hasLength(1));
    });
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
    final spread = PdfrxLayoutAdapter.layout(ReadingMode.twoPageSpread, document.pages, params);

    expect(continuous.pageLayouts, hasLength(3));
    expect(single.pageLayouts, hasLength(3));
    expect(spread.pageLayouts, hasLength(3));
    // Spreads put pages 1 and 2 on the same row and push page 3 to the next.
    expect(spread.pageLayouts[1].top, spread.pageLayouts[0].top);
    expect(spread.pageLayouts[1].left, greaterThan(spread.pageLayouts[0].left));
    expect(spread.pageLayouts[2].top, greaterThan(spread.pageLayouts[1].top));
    expect(spread.pageLayouts[2].left, spread.pageLayouts[0].left);
    // Continuous stacks downwards; single page runs left to right.
    expect(continuous.pageLayouts[1].top, greaterThan(continuous.pageLayouts[0].top));
    expect(continuous.pageLayouts[1].left, continuous.pageLayouts[0].left);
    expect(single.pageLayouts[1].left, greaterThan(single.pageLayouts[0].left));
    expect(single.pageLayouts[1].top, single.pageLayouts[0].top);
    expect(continuous.documentSize.height, greaterThan(single.documentSize.height));
    expect(single.documentSize.width, greaterThan(continuous.documentSize.width));
  });
}
