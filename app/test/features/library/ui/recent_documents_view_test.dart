import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/library/model/recent_document.dart';
import 'package:the_pdf_project/features/library/ui/recent_documents_view.dart';

RecentDocument document(String name, {String? path, int? pageCount, Duration? ago}) =>
    RecentDocument(
      key: 'file:/docs/$name.pdf',
      displayName: '$name.pdf',
      path: path ?? '/docs/$name.pdf',
      lastOpenedAt: DateTime.now().subtract(ago ?? const Duration(minutes: 5)),
      pageCount: pageCount,
    );

void main() {
  Future<
    ({
      List<RecentDocument> opened,
      List<RecentDocument> removed,
      int openPresses,
      int imagePresses,
      int scanPresses,
    })
  >
  pumpView(
    WidgetTester tester, {
    List<RecentDocument> documents = const [],
    Set<String> missingPaths = const {},
  }) async {
    final opened = <RecentDocument>[];
    final removed = <RecentDocument>[];
    var openPresses = 0;
    var imagePresses = 0;
    var scanPresses = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentDocumentsView(
            documents: documents,
            missingPaths: missingPaths,
            isOpening: false,
            onOpenPressed: () => openPresses++,
            onImagesPressed: () => imagePresses++,
            onScanPressed: () => scanPresses++,
            onDocumentSelected: opened.add,
            onDocumentRemoved: removed.add,
          ),
        ),
      ),
    );
    return (
      opened: opened,
      removed: removed,
      openPresses: openPresses,
      imagePresses: imagePresses,
      scanPresses: scanPresses,
    );
  }

  testWidgets('an empty library invites you to open something', (tester) async {
    await pumpView(tester);

    expect(find.text('The PDF Project'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open PDF'), findsOneWidget);
  });

  testWidgets('lists what has been read, newest first', (tester) async {
    await pumpView(tester, documents: [document('recent'), document('older')]);

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('recent.pdf'), findsOneWidget);
    expect(find.text('older.pdf'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('recent.pdf')).dy,
      lessThan(tester.getTopLeft(find.text('older.pdf')).dy),
    );
  });

  testWidgets('says how long ago and how long a document is', (tester) async {
    await pumpView(tester, documents: [document('a', pageCount: 12, ago: const Duration(hours: 3))]);

    expect(find.text('12 pages · 3 hours ago'), findsOneWidget);
  });

  testWidgets('tapping one opens it', (tester) async {
    final result = await pumpView(tester, documents: [document('a')]);

    await tester.tap(find.text('a.pdf'));
    await tester.pumpAndSettle();

    expect(result.opened.single.displayName, 'a.pdf');
  });

  testWidgets('a document that has gone is shown but not openable', (tester) async {
    final result = await pumpView(
      tester,
      documents: [document('gone')],
      missingPaths: {'/docs/gone.pdf'},
    );

    expect(find.text('No longer on this device'), findsOneWidget);
    await tester.tap(find.text('gone.pdf'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(result.opened, isEmpty);
  });

  testWidgets('a document that has gone can still be cleared away', (tester) async {
    final result = await pumpView(
      tester,
      documents: [document('gone')],
      missingPaths: {'/docs/gone.pdf'},
    );

    await tester.tap(find.byTooltip('Remove from recent'));
    await tester.pumpAndSettle();

    expect(result.removed.single.displayName, 'gone.pdf');
  });

  testWidgets('the open button is there whether or not the list is', (tester) async {
    await pumpView(tester, documents: [document('a')]);

    expect(find.widgetWithText(FilledButton, 'Open PDF'), findsOneWidget);
  });

  testWidgets('a new document can be started either way, list or no list', (tester) async {
    for (final documents in [const <RecentDocument>[], [document('a')]]) {
      await pumpView(tester, documents: documents);

      expect(find.widgetWithText(OutlinedButton, 'Images to PDF'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Scan'), findsOneWidget);
    }
  });

  group('describeWhen', () {
    final now = DateTime.utc(2026, 9, 6, 12);
    String describe(Duration ago) => describeWhen(now.subtract(ago), now: now);

    test('reads naturally at every distance', () {
      expect(describe(const Duration(seconds: 20)), 'Just now');
      expect(describe(const Duration(minutes: 1)), '1 minute ago');
      expect(describe(const Duration(minutes: 42)), '42 minutes ago');
      expect(describe(const Duration(hours: 1)), '1 hour ago');
      expect(describe(const Duration(hours: 5)), '5 hours ago');
      expect(describe(const Duration(days: 1)), 'Yesterday');
      expect(describe(const Duration(days: 4)), '4 days ago');
      expect(describe(const Duration(days: 8)), '1 week ago');
      expect(describe(const Duration(days: 20)), '2 weeks ago');
      expect(describe(const Duration(days: 90)), '3 months ago');
    });
  });
}
