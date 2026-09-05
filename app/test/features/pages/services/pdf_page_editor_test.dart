@Tags(['pdfium'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/pages/logic/page_operations.dart';
import 'package:the_pdf_project/features/pages/model/page_plan_entry.dart';
import 'package:the_pdf_project/features/pages/services/pdf_page_editor.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';

/// End-to-end page operations: build a plan, encode it with PDFium, then
/// reopen the result and check the document that actually came out.
void main() {
  const sample = PdfFileSource(path: 'test/fixtures/sample.pdf', displayName: 'sample.pdf');
  const encrypted = PdfFileSource(
    path: 'test/fixtures/encrypted.pdf',
    displayName: 'encrypted.pdf',
  );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfrx_pages').path;
    await pdfrxFlutterInitialize();
  });

  late PdfPageEditor editor;

  setUp(() => editor = PdfPageEditor());
  tearDown(() => editor.dispose());

  /// Opens encoded bytes so assertions run against a real, reparsed document.
  Future<PdfDocument> reopen(Uint8List bytes) async {
    final document = await PdfDocument.openData(bytes, sourceName: 'result-${bytes.length}');
    addTearDown(document.dispose);
    return document;
  }

  Future<List<String>> pageTexts(PdfDocument document) async => [
    for (final page in document.pages) (await page.loadStructuredText()).fullText,
  ];

  test('encoding an untouched plan reproduces the document', () async {
    final plan = await editor.addSource(sample);

    final result = await reopen(await editor.encode(plan));

    expect(result.pages, hasLength(3));
    expect(await pageTexts(result), [
      contains('Page 1'),
      contains('Page 2'),
      contains('Page 3'),
    ]);
  });

  test('delete drops the page from the encoded document', () async {
    final plan = await editor.addSource(sample);

    final result = await reopen(await editor.encode(PageOperations.delete(plan, {1})));

    expect(result.pages, hasLength(2));
    expect(await pageTexts(result), [contains('Page 1'), contains('Page 3')]);
  });

  test('reorder changes the page order in the encoded document', () async {
    final plan = await editor.addSource(sample);

    final result = await reopen(await editor.encode(PageOperations.reorder(plan, 2, 0)));

    expect(await pageTexts(result), [
      contains('Page 3'),
      contains('Page 1'),
      contains('Page 2'),
    ]);
  });

  test('rotate turns the page a quarter turn, swapping its dimensions', () async {
    final plan = await editor.addSource(sample);
    final original = editor.documentFor(sample.key)!.pages.first;

    final result = await reopen(await editor.encode(PageOperations.rotate(plan, {0}, 1)));

    expect(result.pages.first.rotation, PdfPageRotation.clockwise90);
    expect(result.pages.first.width, closeTo(original.height, 0.5));
    expect(result.pages.first.height, closeTo(original.width, 0.5));
    // The other pages are untouched.
    expect(result.pages[1].rotation, PdfPageRotation.none);
    expect(result.pages[1].width, closeTo(original.width, 0.5));
  });

  test('two quarter turns land on 180 degrees without swapping dimensions', () async {
    final plan = await editor.addSource(sample);
    final original = editor.documentFor(sample.key)!.pages.first;

    final result = await reopen(await editor.encode(PageOperations.rotate(plan, {0}, 2)));

    expect(result.pages.first.rotation, PdfPageRotation.clockwise180);
    expect(result.pages.first.width, closeTo(original.width, 0.5));
  });

  test('insert blank adds an empty page the size of its neighbour', () async {
    final plan = await editor.addSource(sample);
    final blank = editor.newBlankEntry(plan: plan, index: 0);

    final result = await reopen(
      await editor.encode(PageOperations.insertAll(plan, 1, [blank])),
    );

    expect(result.pages, hasLength(4));
    expect((await pageTexts(result))[1].trim(), isEmpty);
    expect(result.pages[1].width, closeTo(result.pages[0].width, 0.5));
    expect(result.pages[1].height, closeTo(result.pages[0].height, 0.5));
    // The original pages are still in order around it.
    expect(await pageTexts(result), [
      contains('Page 1'),
      anything,
      contains('Page 2'),
      contains('Page 3'),
    ]);
  });

  test('merge appends the pages of another document', () async {
    final passwordEditor = PdfPageEditor(passwordProvider: () => 'letmein');
    addTearDown(passwordEditor.dispose);

    final plan = await passwordEditor.addSource(sample);
    final merged = PageOperations.append(plan, await passwordEditor.addSource(encrypted));

    final result = await reopen(await passwordEditor.encode(merged));

    expect(result.pages, hasLength(4));
    expect(await pageTexts(result), [
      contains('Page 1'),
      contains('Page 2'),
      contains('Page 3'),
      contains('Locked'),
    ]);
  });

  test('merging a document into itself duplicates its pages', () async {
    final plan = await editor.addSource(sample);
    final merged = PageOperations.append(plan, await editor.addSource(sample));

    final result = await reopen(await editor.encode(merged));

    expect(result.pages, hasLength(6));
  });

  test('split keeps only the extracted range', () async {
    final plan = await editor.addSource(sample);

    final result = await reopen(await editor.encode(PageOperations.extract(plan, {1, 2})));

    expect(await pageTexts(result), [contains('Page 2'), contains('Page 3')]);
  });

  test('operations combine: delete, rotate, blank and reorder in one plan', () async {
    List<PagePlanEntry> plan = await editor.addSource(sample);
    plan = PageOperations.delete(plan, {1}); // 1, 3
    plan = PageOperations.rotate(plan, {1}, 1); // page 3 turned
    plan = PageOperations.insertAll(plan, 1, [
      editor.newBlankEntry(plan: plan, index: 0),
    ]); // 1, blank, 3
    plan = PageOperations.reorder(plan, 2, 0); // 3, 1, blank

    final result = await reopen(await editor.encode(plan));

    expect(result.pages, hasLength(3));
    expect(result.pages.first.rotation, PdfPageRotation.clockwise90);
    final texts = await pageTexts(result);
    expect(texts[0], contains('Page 3'));
    expect(texts[1], contains('Page 1'));
    expect(texts[2].trim(), isEmpty);
  });

  test('encoding an empty plan is refused rather than writing a broken PDF', () async {
    await editor.addSource(sample);

    expect(() => editor.encode(const []), throwsA(isA<StateError>()));
  });
}
