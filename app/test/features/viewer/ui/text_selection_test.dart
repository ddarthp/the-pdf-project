@Tags(['pdfium'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/library/services/document_cache.dart';
import 'package:the_pdf_project/features/library/services/recent_document_store.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/services/last_page_store.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_screen.dart';

import '../../../support/pdfium_test_support.dart';

/// Hands the screen a fixture from disk instead of opening a native picker.
class _FixturePdfPicker extends PdfPicker {
  const _FixturePdfPicker(this.path, this.name);

  final String path;
  final String name;

  @override
  Future<PdfSource?> pickPdf() async => PdfFileSource(path: path, displayName: name);
}

void main() {
  setUpAll(initializePdfiumForTests);
  setUpAll(silenceIncomingDocuments);

  late InMemoryRecentDocumentStore recents;
  late Directory libraryDirectory;
  late List<String> clipboardWrites;

  setUp(() {
    recents = InMemoryRecentDocumentStore();
    libraryDirectory = Directory.systemTemp.createTempSync('library');
    clipboardWrites = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
  });

  tearDown(() {
    if (libraryDirectory.existsSync()) libraryDirectory.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<void> openSample(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          preferences: ViewPreferences(),
          picker: const _FixturePdfPicker(sampleFixture, 'sample.pdf'),
          lastPageStore: InMemoryLastPageStore(),
          recentDocumentStore: recents,
          documentCache: DocumentCache(directoryProvider: () async => libraryDirectory),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await pumpUntil(tester, find.text('1 / 3'));
  }

  PdfViewerController controllerOf(WidgetTester tester) =>
      tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;

  /// The centre of every character of [word] on [pageNumber], in global
  /// coordinates.
  ///
  /// Text positions come from the document itself rather than from guessed
  /// pixel coordinates, so the tests keep working if the layout shifts.
  Future<List<Offset>> globalCharCenters(
    WidgetTester tester,
    String word, {
    int pageNumber = 1,
  }) async {
    final controller = controllerOf(tester);
    final page = controller.pages[pageNumber - 1];
    late PdfPageText text;
    await tester.runAsync(() async => text = await page.loadStructuredText());
    final start = text.fullText.indexOf(word);
    expect(start, isNot(-1), reason: 'the fixture should contain "$word" on page $pageNumber');
    final pageRect = controller.layout.pageLayouts[pageNumber - 1];
    return [
      for (var i = start; i < start + word.length; i++)
        controller.documentToGlobal(
          text.charRects[i].toRectInDocument(page: page, pageRect: pageRect).center,
        )!,
    ];
  }

  Future<String> selectedText(WidgetTester tester) async {
    final delegate = controllerOf(tester).textSelectionDelegate;
    late String text;
    await tester.runAsync(() async => text = await delegate.getSelectedText());
    return text;
  }

  /// Selection is asynchronous twice over: pdfrx reads the page text off the
  /// main isolate, then debounces its selection-changed notification by 300ms.
  /// Frames alone are not enough — the test has to give it real time too.
  Future<void> settleSelection(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  documentTest('long-pressing a word selects it and offers Copy and Select all', (tester) async {
    await openSample(tester);
    final word = await globalCharCenters(tester, 'quick');

    await tester.longPressAt(word[2]);
    await settleSelection(tester);

    expect(controllerOf(tester).textSelectionDelegate.hasSelectedText, isTrue);
    expect(await selectedText(tester), 'quick');
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
  });

  documentTest('dragging a selection handle extends the selection', (tester) async {
    await openSample(tester);
    final quick = await globalCharCenters(tester, 'quick');
    final jumps = await globalCharCenters(tester, 'jumps');

    await tester.longPressAt(quick[2]);
    await settleSelection(tester);
    expect(await selectedText(tester), 'quick');

    // The trailing handle is what the reader grabs to drag the selection
    // further along the line.
    final handle = find.byKey(const Key('anchorB'));
    expect(handle, findsOneWidget, reason: 'a touch selection should show drag handles');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(jumps.last);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await settleSelection(tester);

    // The single word has grown into the run of words the handle was dragged
    // over. The exact final character depends on where the handle lands, so
    // the assertion is on the run that has to be inside it.
    expect(await selectedText(tester), startsWith('quick brown fox jump'));
  });

  documentTest('Copy puts the selected text on the clipboard', (tester) async {
    await openSample(tester);
    final word = await globalCharCenters(tester, 'brown');

    await tester.longPressAt(word[2]);
    await settleSelection(tester);

    await tester.tap(find.text('Copy'));
    await settleSelection(tester);

    expect(clipboardWrites, ['brown']);
    // Copying puts the selection down, as it does everywhere else.
    expect(controllerOf(tester).textSelectionDelegate.hasSelectedText, isFalse);
  });

  documentTest('Select all reaches text on every page', (tester) async {
    await openSample(tester);
    final word = await globalCharCenters(tester, 'quick');

    await tester.longPressAt(word[2]);
    await settleSelection(tester);
    await tester.tap(find.text('Select all'));
    await settleSelection(tester);

    final all = await selectedText(tester);
    expect(all, contains('quick brown fox'));
    expect(all, contains('haystack'));
    expect(all, contains('the sample document'));

    // With everything already selected there is nothing left to select, so the
    // menu offers Copy alone.
    expect(find.text('Select all'), findsNothing);
    await tester.tap(find.text('Copy'));
    await settleSelection(tester);
    expect(clipboardWrites.single, contains('haystack'));
  });

  documentTest('an annotation tool takes the drag instead of the selection', (tester) async {
    await openSample(tester);
    final word = await globalCharCenters(tester, 'quick');

    await tester.tap(find.byTooltip('Annotate'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(word.first);
    await tester.pump(const Duration(milliseconds: 50));
    for (final centre in word.skip(1)) {
      await gesture.moveTo(centre);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settleSelection(tester);

    // The stroke was drawn — the toolbar's save button only wakes up once the
    // document has an annotation — and nothing was selected behind it.
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Save a copy with annotations'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(controllerOf(tester).textSelectionDelegate.hasSelectedText, isFalse);
  });
}
