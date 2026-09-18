@Tags(['pdfium'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/library/services/recent_document_store.dart';
import 'package:the_pdf_project/features/library/ui/recent_documents_view.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/services/incoming_documents.dart';
import 'package:the_pdf_project/features/viewer/services/last_page_store.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_screen.dart';

import '../../../support/pdfium_test_support.dart';

/// The viewer opening documents handed over by another app — "Open with" from
/// a file manager, an attachment, or the share sheet.
///
/// Driven through the real [IncomingDocuments] against mocked platform
/// channels, so the wiring under test is the one that ships.
void main() {
  setUpAll(initializePdfiumForTests);

  late TestDefaultBinaryMessenger messenger;
  late InMemoryRecentDocumentStore recents;
  Object? launchPayload;
  Object? launchError;

  const methods = MethodChannel(IncomingDocuments.methodChannelName);
  const events = MethodChannel(IncomingDocuments.eventChannelName);
  const codec = StandardMethodCodec();

  setUp(() {
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    recents = InMemoryRecentDocumentStore();
    launchPayload = const <Object?>[];
    launchError = null;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (launchError != null) throw launchError!;
      return launchPayload;
    });
    messenger.setMockMethodCallHandler(events, (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  /// One document, the way the platform announces it.
  Map<String, String> entry(String path, String name) => {'path': path, 'name': name};

  /// Hands a batch to the running app, the way a second "Open with" does.
  void share(List<Map<String, String>> documents) {
    messenger.handlePlatformMessage(
      IncomingDocuments.eventChannelName,
      codec.encodeSuccessEnvelope(documents),
      (_) {},
    );
  }

  Future<void> pumpScreen(WidgetTester tester, {LastPageStore? store}) {
    return tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          preferences: ViewPreferences(),
          lastPageStore: store ?? InMemoryLastPageStore(),
          recentDocumentStore: recents,
        ),
      ),
    );
  }

  documentTest('a document the app was opened with is read instead of the library', (tester) async {
    launchPayload = [entry(sampleFixture, 'sample.pdf')];

    await pumpScreen(tester);
    await pumpUntil(tester, find.text('1 / 3'));

    expect(find.byType(RecentDocumentsView), findsNothing);
    expect(find.text('sample.pdf'), findsOneWidget);
  });

  documentTest('a document the app was opened with joins the recent list', (tester) async {
    launchPayload = [entry(sampleFixture, 'sample.pdf')];

    await pumpScreen(tester);
    await pumpUntil(tester, find.text('1 / 3'));

    final documents = await recents.load();
    expect(documents, hasLength(1));
    expect(documents.single.path, sampleFixture);
  });

  documentTest('a document the app was opened with resumes on its last page', (tester) async {
    final store = InMemoryLastPageStore();
    await store.saveLastPage(
      const PdfFileSource(path: sampleFixture, displayName: 'sample.pdf').key,
      3,
    );
    launchPayload = [entry(sampleFixture, 'sample.pdf')];

    await pumpScreen(tester, store: store);

    await pumpUntil(tester, find.text('3 / 3'));
  });

  documentTest('a plain launch still opens on the library', (tester) async {
    launchPayload = const <Object?>[];

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(RecentDocumentsView), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open PDF'), findsOneWidget);
  });

  documentTest('a document shared while another is open takes its place', (tester) async {
    launchPayload = [entry(sampleFixture, 'sample.pdf')];
    await pumpScreen(tester);
    await pumpUntil(tester, find.text('1 / 3'));

    share([entry(formFixture, 'form.pdf')]);
    await pumpUntil(tester, find.text('1 / 1'));

    expect(find.text('form.pdf'), findsOneWidget);
    // The document it replaced is still one tap away.
    expect([for (final document in await recents.load()) document.displayName], [
      'form.pdf',
      'sample.pdf',
    ]);
  });

  documentTest('a document shared into the library opens it', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.byType(RecentDocumentsView), findsOneWidget);

    share([entry(sampleFixture, 'sample.pdf')]);
    await pumpUntil(tester, find.text('1 / 3'));

    expect(find.byType(RecentDocumentsView), findsNothing);
  });

  documentTest('several documents shared at once open one and remember the rest', (tester) async {
    launchPayload = [entry(sampleFixture, 'sample.pdf'), entry(formFixture, 'form.pdf')];

    await pumpScreen(tester);
    await pumpUntil(tester, find.text('1 / 3'));

    expect(find.text('sample.pdf'), findsOneWidget);
    // The one that was opened leads, the rest are waiting in the library.
    expect([for (final document in await recents.load()) document.displayName], [
      'sample.pdf',
      'form.pdf',
    ]);
  });

  documentTest('a platform that cannot hand a document over still launches', (tester) async {
    launchError = PlatformException(code: 'unreadable', message: 'could not be copied');

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(RecentDocumentsView), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open PDF'), findsOneWidget);
  });
}
