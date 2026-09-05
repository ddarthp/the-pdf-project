@Tags(['pdfium'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/model/reading_mode.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';
import 'package:the_pdf_project/features/viewer/ui/empty_state.dart';
import 'package:the_pdf_project/features/viewer/ui/thumbnail_panel.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_screen.dart';

/// Hands the screen the three-page fixture instead of opening a native picker.
class _FixturePdfPicker extends PdfPicker {
  const _FixturePdfPicker();

  @override
  Future<PdfSource?> pickPdf() async => const PdfFileSource(
    path: 'test/fixtures/sample.pdf',
    displayName: 'sample.pdf',
  );
}

/// Pumps until [finder] matches, letting real async work (file I/O, PDFium
/// calls, image decoding) run between frames. `pumpAndSettle` alone is not
/// enough: loading a document schedules no frames while it waits on I/O.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $finder');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfrx_test_cache').path;
    await pdfrxFlutterInitialize();
  });

  Future<ViewPreferences> openFixture(WidgetTester tester) async {
    final preferences = ViewPreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(preferences: preferences, picker: const _FixturePdfPicker()),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await pumpUntil(tester, find.text('1 / 3'));
    return preferences;
  }

  testWidgets('opening a PDF renders it and reveals the reading controls', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openFixture(tester);

    expect(find.byType(ViewerEmptyState), findsNothing);
    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.text('sample.pdf'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('page navigation moves through the document', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openFixture(tester);

    await tester.tap(find.byTooltip('Next page'));
    await pumpUntil(tester, find.text('2 / 3'));

    await tester.tap(find.byTooltip('Last page'));
    await pumpUntil(tester, find.text('3 / 3'));

    await tester.tap(find.byTooltip('First page'));
    await pumpUntil(tester, find.text('1 / 3'));
  });

  testWidgets('jump-to-page dialog goes to the requested page', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openFixture(tester);

    await tester.tap(find.text('1 / 3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Go'));
    await pumpUntil(tester, find.text('3 / 3'));
  });

  testWidgets('in-document search finds a match and reports the count', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openFixture(tester);

    await tester.tap(find.byTooltip('Find in document'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'haystack');
    await pumpUntil(tester, find.text('1 / 1'));
  });

  testWidgets('the side panel lists page thumbnails', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openFixture(tester);

    await tester.tap(find.byTooltip('Outline and thumbnails'));
    await pumpUntil(tester, find.byType(ThumbnailPanel));
    // Let the drawer finish sliding in before tapping anything inside it.
    await tester.pumpAndSettle();

    expect(find.byType(PdfPageView), findsWidgets);

    await tester.tap(find.text('Outline'));
    await pumpUntil(tester, find.text('This document has no outline.'));
  });

  testWidgets('switching to single-page mode keeps the current page', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final preferences = await openFixture(tester);

    await tester.tap(find.byTooltip('Next page'));
    await pumpUntil(tester, find.text('2 / 3'));

    preferences.readingMode = ReadingMode.singlePage;
    await pumpUntil(tester, find.text('2 / 3'));

    expect(find.text('2 / 3'), findsOneWidget);
  });
}
