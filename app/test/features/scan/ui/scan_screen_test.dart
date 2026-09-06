@Tags(['pdfium'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/scan/model/scan_filter.dart';
import 'package:the_pdf_project/features/scan/services/document_camera.dart';
import 'package:the_pdf_project/features/scan/services/page_processor.dart';
import 'package:the_pdf_project/features/scan/ui/scan_review_screen.dart';
import 'package:the_pdf_project/features/scan/ui/scan_screen.dart';
import 'package:the_pdf_project/features/share/services/pdf_export_service.dart';

import '../../../support/pdfium_test_support.dart';
import '../../../support/recording_exporter.dart';
import '../../../support/scan_bitmaps.dart';

/// Hands the scanner a photograph instead of opening the camera.
class _FakeCamera extends DocumentCamera {
  const _FakeCamera(this.photographs, this.captures);

  /// One per call, so a test can scan several different pages.
  final List<Uint8List?> photographs;
  final List<String> captures;

  @override
  Future<Uint8List?> capture() async {
    captures.add('camera');
    return _next();
  }

  @override
  Future<Uint8List?> chooseExisting() async {
    captures.add('gallery');
    return _next();
  }

  Uint8List? _next() =>
      photographs.isEmpty ? null : photographs.removeAt(0);
}

void main() {
  setUpAll(initializePdfiumForTests);

  late RecordingExporter exporter;
  late List<String> captures;
  late Uint8List pagePhotograph;

  setUpAll(() async {
    final bitmap = TestBitmap(400, 300)
      ..fillRect(80, 60, 320, 240)
      // Some "text" so the page is not a featureless block.
      ..fillRect(110, 100, 290, 110, value: 20)
      ..fillRect(110, 130, 250, 140, value: 20);
    pagePhotograph = await PageProcessor.encodePng(
      pixels: bitmap.pixels,
      width: bitmap.width,
      height: bitmap.height,
    );
  });

  setUp(() {
    exporter = RecordingExporter();
    captures = [];
  });

  Future<Future<Uri?>> pushScanner(WidgetTester tester, {int photographs = 1}) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())),
    );
    final result = navigatorKey.currentState!.push<Uri>(
      MaterialPageRoute(
        builder: (context) => ScanScreen(
          camera: _FakeCamera(
            [for (var i = 0; i < photographs; i++) pagePhotograph],
            captures,
          ),
          exporter: exporter,
        ),
      ),
    );
    await pumpUntil(tester, find.byType(ScanScreen));
    return result;
  }

  documentTest('it reaches for the camera as soon as it opens', (tester) async {
    await pushScanner(tester);
    await pumpUntil(tester, find.text('Page 1'));

    expect(captures, ['camera']);
    expect(find.text('1 page'), findsOneWidget);
    // Cleaned up by default rather than left as photographed.
    expect(find.text(ScanFilter.enhance.label), findsOneWidget);
  });

  documentTest('backing out of the camera leaves nothing scanned', (tester) async {
    await pushScanner(tester, photographs: 0);
    await pumpUntil(tester, find.text('Nothing scanned yet'));

    expect(find.widgetWithText(FilledButton, 'Scan a page'), findsOneWidget);
  });

  documentTest('a photograph already taken can be used instead', (tester) async {
    await pushScanner(tester, photographs: 2);
    await pumpUntil(tester, find.text('Page 1'));
    // Let the route finish arriving before reaching for the toolbar.
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('Use a photo already taken'));
    await pumpUntil(tester, find.text('Page 2'));

    expect(captures, ['camera', 'gallery']);
  });

  documentTest('pages can be scanned and taken away again', (tester) async {
    await pushScanner(tester, photographs: 3);
    await pumpUntil(tester, find.text('Page 1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Scan another page'));
    await pumpUntil(tester, find.text('Page 2'));

    await tester.tap(find.byTooltip('Remove page').first);
    await tester.pumpAndSettle();

    expect(find.text('1 page'), findsOneWidget);
  });

  documentTest('a page can be checked over and its filter changed', (tester) async {
    await pushScanner(tester);
    await pumpUntil(tester, find.text('Page 1'));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Page 1'));
    await pumpUntil(tester, find.byType(ScanReviewScreen));
    await tester.pumpAndSettle();

    expect(find.text('Up to date'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, ScanFilter.blackAndWhite.label));
    await tester.pumpAndSettle();
    expect(find.text('Not applied yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await pumpUntilAbsent(tester, find.byType(ScanReviewScreen));
    await tester.pumpAndSettle();

    // The change followed the page back to the list.
    expect(find.text(ScanFilter.blackAndWhite.label), findsOneWidget);
  });

  documentTest('the scanned pages become one PDF, in order', (tester) async {
    final result = await pushScanner(tester, photographs: 2);
    await pumpUntil(tester, find.text('Page 1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Scan another page'));
    await pumpUntil(tester, find.text('Page 2'));

    await tester.tap(find.widgetWithText(FilledButton, 'Make PDF'));
    await pumpUntil(tester, find.text('Save to Files…'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('scan.pdf'), findsOneWidget);
    await tester.tap(find.text('Save to Files…'));
    await pumpUntilAbsent(tester, find.byType(ScanScreen));
    await tester.pumpAndSettle();

    expect(exporter.destination, PdfExportDestination.saveToFiles);
    expect(exporter.fileName, 'scan.pdf');

    final document = await tester.runAsync(
      () => PdfDocument.openData(exporter.bytes!, sourceName: 'scanned'),
    );
    addTearDown(() => document!.dispose());
    expect(document!.pages, hasLength(2));
    // Each page took the shape of the straightened page, not of the
    // photograph it was cut out of.
    expect(document.pages.first.width / document.pages.first.height, closeTo(4 / 3, 0.1));
    expect(await result, Uri.file('/tmp/scan.pdf'));
  });
}
