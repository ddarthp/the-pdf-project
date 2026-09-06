@Tags(['pdfium'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/model/reading_mode.dart';
import 'package:the_pdf_project/features/viewer/model/view_rotation.dart';
import 'package:the_pdf_project/features/viewer/services/last_page_store.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';
import 'package:the_pdf_project/features/library/model/recent_document.dart';
import 'package:the_pdf_project/features/library/services/document_cache.dart';
import 'package:the_pdf_project/features/library/services/recent_document_store.dart';
import 'package:the_pdf_project/features/library/ui/recent_documents_view.dart';
import 'package:the_pdf_project/features/viewer/ui/load_error_banner.dart';
import 'package:the_pdf_project/features/viewer/ui/thumbnail_panel.dart';
import 'package:the_pdf_project/features/forms/ui/form_fill_screen.dart';
import 'package:the_pdf_project/features/share/services/pdf_export_service.dart';
import 'package:the_pdf_project/features/pages/ui/page_organizer_screen.dart';
import 'package:the_pdf_project/features/pages/ui/page_tile.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_screen.dart';

import '../../../support/pdfium_test_support.dart';
import '../../../support/recording_exporter.dart';

/// Hands the screen a fixture from disk instead of opening a native picker.
class _FixturePdfPicker extends PdfPicker {
  const _FixturePdfPicker(this.path, this.name);

  final String path;
  final String name;

  @override
  Future<PdfSource?> pickPdf() async => PdfFileSource(path: path, displayName: name);
}

void main() {
  /// Measured once outside the tests: real file I/O never completes inside a
  /// widget test's fake clock.
  late int sampleFixtureBytes;

  setUpAll(() async {
    await initializePdfiumForTests();
    sampleFixtureBytes = await File(sampleFixture).length();
  });

  late RecordingExporter exporter;
  late InMemoryRecentDocumentStore recents;
  late Directory libraryDirectory;

  setUp(() {
    exporter = RecordingExporter();
    recents = InMemoryRecentDocumentStore();
    libraryDirectory = Directory.systemTemp.createTempSync('library');
  });

  tearDown(() {
    if (libraryDirectory.existsSync()) libraryDirectory.deleteSync(recursive: true);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required ViewPreferences preferences,
    required LastPageStore store,
    String fixture = sampleFixture,
    String name = 'sample.pdf',
    // A distinct key forces a brand-new screen state, standing in for the app
    // being restarted rather than rebuilt.
    Key key = const ValueKey('viewer'),
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          key: key,
          preferences: preferences,
          picker: _FixturePdfPicker(fixture, name),
          lastPageStore: store,
          exporter: exporter,
          recentDocumentStore: recents,
          documentCache: DocumentCache(directoryProvider: () async => libraryDirectory),
        ),
      ),
    );
  }

  Future<ViewPreferences> openSample(WidgetTester tester, {LastPageStore? store}) async {
    final preferences = ViewPreferences();
    await pumpScreen(
      tester,
      preferences: preferences,
      store: store ?? InMemoryLastPageStore(),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await pumpUntil(tester, find.text('1 / 3'));
    return preferences;
  }

  documentTest('opening a PDF renders it and reveals the reading controls', (tester) async {
    await openSample(tester);

    expect(find.byType(RecentDocumentsView), findsNothing);
    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.text('sample.pdf'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  documentTest('page navigation moves through the document', (tester) async {
    await openSample(tester);

    await tester.tap(find.byTooltip('Next page'));
    await pumpUntil(tester, find.text('2 / 3'));

    await tester.tap(find.byTooltip('Last page'));
    await pumpUntil(tester, find.text('3 / 3'));

    await tester.tap(find.byTooltip('First page'));
    await pumpUntil(tester, find.text('1 / 3'));
  });

  documentTest('jump-to-page dialog goes to the requested page', (tester) async {
    await openSample(tester);

    await tester.tap(find.text('1 / 3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Go'));
    await pumpUntil(tester, find.text('3 / 3'));
  });

  documentTest('zoom and fit controls are wired up', (tester) async {
    await openSample(tester);

    for (final tooltip in ['Zoom in', 'Zoom out', 'Fit width', 'Fit height', 'Fit page']) {
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)),
            )
            .onPressed,
        isNotNull,
        reason: '\$tooltip should be enabled with a document open',
      );
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
    }

    expect(find.text('1 / 3'), findsOneWidget);
  });

  documentTest('in-document search finds a match and reports the count', (tester) async {
    await openSample(tester);

    await tester.tap(find.byTooltip('Find in document'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'haystack');
    await pumpUntil(tester, find.text('1 / 1'));
  });

  documentTest('the side panel lists page thumbnails', (tester) async {
    await openSample(tester);

    await tester.tap(find.byTooltip('Outline and thumbnails'));
    await pumpUntil(tester, find.byType(ThumbnailPanel));
    // Let the drawer finish sliding in before tapping anything inside it.
    await tester.pumpAndSettle();

    expect(find.byType(PdfPageView), findsWidgets);

    await tester.tap(find.text('Outline'));
    await pumpUntil(tester, find.text('This document has no outline.'));
  });

  for (final mode in [ReadingMode.singlePage, ReadingMode.twoPageSpread]) {
    documentTest('switching to ${mode.label} keeps the current page', (tester) async {
      final preferences = await openSample(tester);

      await tester.tap(find.byTooltip('Next page'));
      await pumpUntil(tester, find.text('2 / 3'));

      preferences.readingMode = mode;
      await pumpUntil(tester, find.text('2 / 3'));

      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
    });
  }

  documentTest('rotating the view turns the viewer without reloading it', (tester) async {
    final preferences = await openSample(tester);

    RotatedBox viewerRotation() => tester.widget<RotatedBox>(
      find.ancestor(of: find.byType(PdfViewer), matching: find.byType(RotatedBox)),
    );

    expect(viewerRotation().quarterTurns, 0);

    preferences.rotateClockwise();
    await tester.pumpAndSettle();
    expect(preferences.viewRotation, ViewRotation.clockwise90);
    expect(viewerRotation().quarterTurns, 1);

    preferences.viewRotation = ViewRotation.clockwise270;
    await tester.pumpAndSettle();
    expect(viewerRotation().quarterTurns, 3);

    // Rotation is presentation-only: the document stays loaded on its page.
    expect(find.text('1 / 3'), findsOneWidget);
  });

  documentTest('reopening a document resumes on the last page read', (tester) async {
    final store = InMemoryLastPageStore();

    await openSample(tester, store: store);
    await tester.tap(find.byTooltip('Last page'));
    await pumpUntil(tester, find.text('3 / 3'));

    // A fresh screen, as if the app had been restarted, sharing the store.
    await pumpScreen(
      tester,
      preferences: ViewPreferences(),
      store: store,
      key: const ValueKey('restarted'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RecentDocumentsView), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await pumpUntil(tester, find.text('3 / 3'));
  });

  documentTest('the viewer opens the page organiser on the current document', (tester) async {
    await openSample(tester);

    await tester.tap(find.byTooltip('Document actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organize pages…'));
    await pumpUntil(tester, find.byType(PageOrganizerScreen));
    await pumpUntil(tester, find.byType(PageTile));

    expect(find.byType(PageTile), findsNWidgets(3));
    // The viewer's own document is untouched behind the organiser.
    expect(find.text('Page 1 of sample.pdf'), findsOneWidget);
  });

  group('the library', () {
    documentTest('an opened document joins the recent list', (tester) async {
      await openSample(tester);

      final documents = await recents.load();
      expect(documents, hasLength(1));
      expect(documents.single.displayName, 'sample.pdf');
      expect(documents.single.path, sampleFixture);
      // The page count is filled in once the document has actually opened.
      expect(documents.single.pageCount, 3);
    });

    documentTest('the reader can go back to the library and open from it', (tester) async {
      await openSample(tester);
      await tester.tap(find.byTooltip('Recent files'));
      await tester.pumpAndSettle();

      // The document is put down and the library is on screen instead.
      expect(find.byType(PdfViewer), findsNothing);
      expect(find.byType(RecentDocumentsView), findsOneWidget);
      expect(find.text('sample.pdf'), findsOneWidget);
      expect(find.text('3 pages · Just now'), findsOneWidget);

      await tester.tap(find.text('sample.pdf'));
      await pumpUntil(tester, find.text('1 / 3'));
    });

    documentTest('reopening from the library resumes where it was left', (tester) async {
      final store = InMemoryLastPageStore();
      await openSample(tester, store: store);
      await tester.tap(find.byTooltip('Last page'));
      await pumpUntil(tester, find.text('3 / 3'));

      await tester.tap(find.byTooltip('Recent files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sample.pdf'));

      await pumpUntil(tester, find.text('3 / 3'));
    });

    documentTest('a document already listed moves up rather than doubling', (tester) async {
      await openSample(tester);
      await tester.tap(find.byTooltip('Recent files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sample.pdf'));
      await pumpUntil(tester, find.text('1 / 3'));

      expect(await recents.load(), hasLength(1));
    });

    documentTest('a document can be taken off the list', (tester) async {
      await openSample(tester);
      await tester.tap(find.byTooltip('Recent files'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove from recent'));
      await pumpUntilAbsent(tester, find.text('sample.pdf'));

      expect(await recents.load(), isEmpty);
      // Back to the invitation to open something.
      expect(find.widgetWithText(FilledButton, 'Open PDF'), findsOneWidget);
    });

    documentTest('a remembered document that has gone is shown as unavailable', (tester) async {
      await recents.save([
        RecentDocument(
          key: 'file:/gone/missing.pdf',
          displayName: 'missing.pdf',
          path: '/gone/missing.pdf',
          lastOpenedAt: DateTime.now(),
        ),
      ]);

      await pumpScreen(
        tester,
        preferences: ViewPreferences(),
        store: InMemoryLastPageStore(),
      );
      await pumpUntil(tester, find.text('missing.pdf'));

      expect(find.text('No longer on this device'), findsOneWidget);
    });
  });

  group('sharing the open document', () {
    Future<void> openExportSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Document actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share or print…'));
      await pumpUntil(tester, find.text('Share…'));
      await tester.pump(const Duration(milliseconds: 400));
    }

    documentTest('offers to save, share or print what is on screen', (tester) async {
      await openSample(tester);

      await openExportSheet(tester);

      expect(find.text('sample.pdf'), findsWidgets);
      expect(find.text('Save to Files…'), findsOneWidget);
      expect(find.text('Print…'), findsOneWidget);
    });

    documentTest('sharing sends the document exactly as it is on disk', (tester) async {
      await openSample(tester);
      await openExportSheet(tester);

      await tester.tap(find.text('Share…'));
      await pumpUntil(tester, find.text('Shared'));

      expect(exporter.destination, PdfExportDestination.share);
      expect(exporter.fileName, 'sample.pdf');
      expect(String.fromCharCodes(exporter.bytes!.take(5)), '%PDF-');
      expect(exporter.bytes!.length, sampleFixtureBytes);
      // The share sheet opens as a popover on a tablet, so it is told where
      // it was asked from.
      expect(exporter.originBounds, isNotNull);
    });

    documentTest('printing goes to the printer, not to a file', (tester) async {
      await openSample(tester);
      await openExportSheet(tester);

      await tester.tap(find.text('Print…'));
      await pumpUntil(tester, find.text('Sent to the printer'));

      expect(exporter.destination, PdfExportDestination.print);
    });

    documentTest('an annotated document is sent with its annotations', (tester) async {
      await openSample(tester);
      await tester.tap(find.byTooltip('Annotate'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(300, 400));
      for (var step = 1; step <= 6; step++) {
        await gesture.moveTo(Offset(300 + step * 60, 400 + step * 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Done annotating'));
      await tester.pumpAndSettle();

      await openExportSheet(tester);

      // Sending the plain file would quietly drop what is on screen, so the
      // annotated copy goes instead — and the sheet says so.
      expect(find.text('sample-annotated.pdf'), findsOneWidget);
      expect(find.text('1 annotation'), findsOneWidget);

      await tester.tap(find.text('Share…'));
      await pumpUntil(tester, find.text('Shared'));

      expect(exporter.fileName, 'sample-annotated.pdf');
      expect(
        exporter.bytes!.length,
        greaterThan(sampleFixtureBytes),
        reason: 'the annotated copy carries more than the original',
      );
    });
  });

  documentTest('the viewer opens the form filler on the current document', (tester) async {
    await openSample(tester);

    await tester.tap(find.byTooltip('Document actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill form…'));
    await pumpUntil(tester, find.byType(FormFillScreen));

    // The fixture is a plain document, so the filler says there is nothing to
    // fill rather than showing an empty form.
    await pumpUntil(tester, find.text('No form fields'));
  });

  group('password-protected documents', () {
    Future<void> openEncrypted(WidgetTester tester) async {
      await pumpScreen(
        tester,
        preferences: ViewPreferences(),
        store: InMemoryLastPageStore(),
        fixture: encryptedFixture,
        name: 'encrypted.pdf',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
      await pumpUntil(tester, find.text('Password required'));
    }

    documentTest('prompt for the password and open once it is right', (tester) async {
      await openEncrypted(tester);
      expect(find.textContaining('encrypted.pdf is protected'), findsOneWidget);

      await tester.enterText(find.byType(TextField), encryptedPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await pumpUntil(tester, find.text('1 / 1'));

      expect(find.byType(PdfViewer), findsOneWidget);
    });

    documentTest('ask again after a wrong password', (tester) async {
      await openEncrypted(tester);

      await tester.enterText(find.byType(TextField), 'not-the-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await pumpUntil(tester, find.text('Incorrect password'));

      await tester.enterText(find.byType(TextField), encryptedPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await pumpUntil(tester, find.text('1 / 1'));
    });

    documentTest('explain the lock and offer a way back in when cancelled', (tester) async {
      await openEncrypted(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await pumpUntil(tester, find.byType(LoadErrorBanner));

      expect(find.text('This PDF is locked'), findsOneWidget);

      // "Enter password" retries the load, which asks for the password again.
      await tester.tap(find.widgetWithText(FilledButton, 'Enter password'));
      await pumpUntil(tester, find.text('Password required'));

      await tester.enterText(find.byType(TextField), encryptedPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await pumpUntil(tester, find.text('1 / 1'));
    });
  });
}
