@Tags(['pdfium'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/model/reading_mode.dart';
import 'package:the_pdf_project/features/viewer/model/view_rotation.dart';
import 'package:the_pdf_project/features/viewer/services/last_page_store.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';
import 'package:the_pdf_project/features/viewer/ui/empty_state.dart';
import 'package:the_pdf_project/features/viewer/ui/load_error_banner.dart';
import 'package:the_pdf_project/features/viewer/ui/thumbnail_panel.dart';
import 'package:the_pdf_project/features/pages/ui/page_organizer_screen.dart';
import 'package:the_pdf_project/features/pages/ui/page_tile.dart';
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

    expect(find.byType(ViewerEmptyState), findsNothing);
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
    expect(find.byType(ViewerEmptyState), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await pumpUntil(tester, find.text('3 / 3'));
  });

  documentTest('the viewer opens the page organiser on the current document', (tester) async {
    await openSample(tester);

    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Organize pages'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip('Organize pages'));
    await pumpUntil(tester, find.byType(PageOrganizerScreen));
    await pumpUntil(tester, find.byType(PageTile));

    expect(find.byType(PageTile), findsNWidgets(3));
    // The viewer's own document is untouched behind the organiser.
    expect(find.text('Page 1 of sample.pdf'), findsOneWidget);
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
