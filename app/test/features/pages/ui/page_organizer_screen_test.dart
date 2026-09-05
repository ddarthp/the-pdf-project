@Tags(['pdfium'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/pages/ui/page_organizer_screen.dart';
import 'package:the_pdf_project/features/pages/ui/page_tile.dart';
import 'package:the_pdf_project/features/share/services/pdf_export_service.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';

import '../../../support/pdfium_test_support.dart';
import '../../../support/recording_exporter.dart';

const _sample = PdfFileSource(path: sampleFixture, displayName: 'sample.pdf');

/// Adds the encrypted fixture when the organiser asks for more PDFs.
class _MergePicker extends PdfPicker {
  const _MergePicker();

  @override
  Future<List<PdfSource>> pickPdfs() async => const [
    PdfFileSource(path: sampleFixture, displayName: 'sample.pdf'),
  ];
}

void main() {
  setUpAll(initializePdfiumForTests);

  /// Pushes the organiser onto a real route so "save then pop" behaves as it
  /// does in the app, and returns the future that carries the saved location.
  Future<Future<Uri?>> pushOrganizer(
    WidgetTester tester, {
    PdfPicker picker = const PdfPicker(),
    PdfExportService? exporter,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())),
    );
    final result = navigatorKey.currentState!.push<Uri>(
      MaterialPageRoute(
        builder: (context) => PageOrganizerScreen(
          source: _sample,
          picker: picker,
          exporter: exporter ?? const PdfExportService(),
        ),
      ),
    );
    await pumpUntil(tester, find.byType(PageTile));
    await tester.pumpAndSettle();
    return result;
  }

  documentTest('lists a tile per page of the opened document', (tester) async {
    await pushOrganizer(tester);

    expect(find.byType(PageTile), findsNWidgets(3));
    expect(find.text('Page 1 of sample.pdf'), findsOneWidget);
    expect(find.text('3 pages'), findsOneWidget);
  });

  documentTest('deleting the selected pages removes them from the plan', (tester) async {
    await pushOrganizer(tester);

    await tester.tap(find.text('Page 1 of sample.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete pages'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsNWidgets(2));
    expect(find.text('2 pages'), findsOneWidget);
    // The remaining pages are renumbered but keep their source page numbers.
    expect(find.text('Page 2 of sample.pdf'), findsOneWidget);
    expect(find.text('Page 1 of sample.pdf'), findsNothing);
  });

  documentTest('undo brings deleted pages back', (tester) async {
    await pushOrganizer(tester);

    await tester.tap(find.text('Page 1 of sample.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete pages'));
    await tester.pumpAndSettle();
    expect(find.byType(PageTile), findsNWidgets(2));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsNWidgets(3));
    expect(find.text('Page 1 of sample.pdf'), findsOneWidget);
  });

  documentTest('deleting every page is refused', (tester) async {
    await pushOrganizer(tester);

    await tester.tap(find.byTooltip('More page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete pages'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsNWidgets(3));
    expect(find.text('A PDF needs at least one page.'), findsOneWidget);
  });

  documentTest('rotating a page shows how far it has been turned', (tester) async {
    await pushOrganizer(tester);

    await tester.tap(find.text('Page 2 of sample.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rotate right'));
    await tester.pumpAndSettle();
    expect(find.text('Rotated 90°'), findsOneWidget);

    // The selection survives so the page can be turned further.
    await tester.tap(find.byTooltip('Rotate right'));
    await tester.pumpAndSettle();
    expect(find.text('Rotated 180°'), findsOneWidget);

    await tester.tap(find.byTooltip('Rotate left'));
    await tester.pumpAndSettle();
    expect(find.text('Rotated 90°'), findsOneWidget);
  });

  documentTest('inserting a blank page adds it after the selection', (tester) async {
    await pushOrganizer(tester);

    await tester.tap(find.text('Page 1 of sample.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert blank page'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsNWidgets(4));
    expect(find.text('Blank page'), findsOneWidget);
    // It landed in second place, right after the page that was selected.
    final labels = tester
        .widgetList<PageTile>(find.byType(PageTile))
        .map((tile) => tile.sourceLabel)
        .toList();
    expect(labels[1], 'Blank page');
  });

  documentTest('dragging a page by its handle reorders the plan', (tester) async {
    await pushOrganizer(tester);

    List<String> labels() => tester
        .widgetList<PageTile>(find.byType(PageTile))
        .map((tile) => tile.sourceLabel)
        .toList();

    expect(labels(), [
      'Page 1 of sample.pdf',
      'Page 2 of sample.pdf',
      'Page 3 of sample.pdf',
    ]);

    // The handle starts a drag immediately; a tap anywhere else selects.
    final handle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    // Move in tile-sized steps so the list can open a gap as we go, the way a
    // real drag does; a single large jump only shifts the item one place.
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(const Offset(0, PageTile.height));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(labels(), [
      'Page 2 of sample.pdf',
      'Page 3 of sample.pdf',
      'Page 1 of sample.pdf',
    ]);
  });

  documentTest('merging appends the pages of another PDF', (tester) async {
    await pushOrganizer(tester, picker: const _MergePicker());

    await tester.tap(find.byTooltip('More page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add PDF…'));
    await pumpUntil(tester, find.text('6 pages'));

    expect(find.byType(PageTile), findsNWidgets(6));
  });

  documentTest('select range picks out the pages named', (tester) async {
    await pushOrganizer(tester);

    await tester.tap(find.byTooltip('More page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select range…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2-3');
    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
  });

  documentTest('split keeps only the selected pages', (tester) async {
    await pushOrganizer(tester);

    await tester.tap(find.text('Page 3 of sample.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split: keep only selection'));
    await tester.pumpAndSettle();

    expect(find.byType(PageTile), findsOneWidget);
    expect(find.text('Page 3 of sample.pdf'), findsOneWidget);
  });

  documentTest('saving encodes the plan and reports where it went', (tester) async {
    final exporter = RecordingExporter();
    final result = await pushOrganizer(tester, exporter: exporter);

    await tester.tap(find.text('Page 1 of sample.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete pages'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save PDF'));
    // Encoding happens before the destination sheet appears.
    await pumpUntil(tester, find.text('Save to Files…'));
    // Let the sheet finish sliding up before reaching into it. Waiting for
    // quiescence is no good here: the page thumbnails keep asking for frames.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 pages'), findsWidgets, reason: 'the sheet says what is being saved');
    await tester.tap(find.text('Save to Files…'));

    // A successful save closes the organiser and hands back the destination.
    await pumpUntilAbsent(tester, find.byType(PageOrganizerScreen));
    await tester.pumpAndSettle();

    expect(exporter.destination, PdfExportDestination.saveToFiles);
    expect(exporter.fileName, 'sample-edited.pdf');
    expect(exporter.bytes, isNotNull);
    expect(String.fromCharCodes(exporter.bytes!.take(5)), '%PDF-');
    expect(await result, Uri.file('/tmp/sample-edited.pdf'));
  });
}
