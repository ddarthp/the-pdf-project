@Tags(['pdfium'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/convert/model/picked_image.dart';
import 'package:the_pdf_project/features/convert/services/image_source_picker.dart';
import 'package:the_pdf_project/features/convert/ui/image_to_pdf_screen.dart';
import 'package:the_pdf_project/features/share/services/pdf_export_service.dart';

import '../../../support/pdfium_test_support.dart';
import '../../../support/recording_exporter.dart';
import '../../../support/test_images.dart';

/// Hands the screen a fixed set of pictures instead of opening the system
/// picker.
///
/// Ids are made unique per pick, the way the real picker does: they identify a
/// row in the list, and two rows sharing one would be a list that cannot be
/// reordered.
class _FakeImagePicker extends ImageSourcePicker {
  const _FakeImagePicker(this.images, this.calls);

  final List<PickedImage> images;
  final List<int> calls;

  @override
  Future<List<PickedImage>> pickImages({int startingId = 0}) async {
    calls.add(startingId);
    return [
      for (final image in images)
        PickedImage(
          id: '${image.id}-$startingId',
          displayName: image.displayName,
          bytes: image.bytes,
          pixelWidth: image.pixelWidth,
          pixelHeight: image.pixelHeight,
        ),
    ];
  }
}

void main() {
  setUpAll(initializePdfiumForTests);

  late RecordingExporter exporter;
  late List<int> pickerCalls;
  late Uint8List widePng;
  late Uint8List tallPng;

  setUpAll(() async {
    widePng = await testPng(width: 400, height: 200);
    tallPng = await testPng(width: 200, height: 400, color: const ui.Color(0xFFE53935));
  });

  setUp(() {
    exporter = RecordingExporter();
    pickerCalls = [];
  });

  PickedImage image(Uint8List bytes, int width, int height, String name) => PickedImage(
    id: name,
    displayName: name,
    bytes: bytes,
    pixelWidth: width,
    pixelHeight: height,
  );

  Future<Future<Uri?>> pushScreen(WidgetTester tester, List<PickedImage> images) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())),
    );
    final result = navigatorKey.currentState!.push<Uri>(
      MaterialPageRoute(
        builder: (context) => ImageToPdfScreen(
          picker: _FakeImagePicker(images, pickerCalls),
          exporter: exporter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return result;
  }

  List<PickedImage> twoImages() => [
    image(widePng, 400, 200, 'wide.png'),
    image(tallPng, 200, 400, 'tall.png'),
  ];

  documentTest('it asks for pictures as soon as it opens', (tester) async {
    await pushScreen(tester, twoImages());

    expect(pickerCalls, [0]);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('2 pages'), findsOneWidget);
  });

  documentTest('with nothing chosen it says so and offers to choose', (tester) async {
    await pushScreen(tester, const []);

    expect(find.text('No images yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Choose images'), findsOneWidget);
  });

  documentTest('an image can be taken back out', (tester) async {
    await pushScreen(tester, twoImages());

    await tester.tap(find.byTooltip('Remove image').first);
    await tester.pumpAndSettle();

    expect(find.text('1 page'), findsOneWidget);
    expect(find.text('tall.png'), findsOneWidget);
    expect(find.text('wide.png'), findsNothing);
  });

  documentTest('more images are added after the ones already chosen', (tester) async {
    await pushScreen(tester, twoImages());

    await tester.tap(find.byTooltip('Add images'));
    await tester.pumpAndSettle();

    // The picker is told how many are already there, so the new ones get
    // identities of their own.
    expect(pickerCalls, [0, 2]);
  });

  documentTest('making the PDF turns each image into a page, in order', (tester) async {
    final result = await pushScreen(tester, twoImages());

    await tester.tap(find.widgetWithText(FilledButton, 'Make PDF'));
    await pumpUntil(tester, find.text('Save to Files…'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('images.pdf'), findsOneWidget);
    expect(find.text('2 pages'), findsWidgets);
    await tester.tap(find.text('Save to Files…'));
    await pumpUntilAbsent(tester, find.byType(ImageToPdfScreen));
    await tester.pumpAndSettle();

    expect(exporter.destination, PdfExportDestination.saveToFiles);
    expect(exporter.fileName, 'images.pdf');

    final document = await tester.runAsync(
      () => PdfDocument.openData(exporter.bytes!, sourceName: 'made'),
    );
    addTearDown(() => document!.dispose());
    expect(document!.pages, hasLength(2));
    // Wide first, tall second — the order they were listed in.
    expect(document.pages[0].width, greaterThan(document.pages[0].height));
    expect(document.pages[1].width, lessThan(document.pages[1].height));
    expect(await result, Uri.file('/tmp/images.pdf'));
  });

  documentTest('one image lends the document its own name', (tester) async {
    await pushScreen(tester, [image(widePng, 400, 200, 'holiday.png')]);

    await tester.tap(find.widgetWithText(FilledButton, 'Make PDF'));
    await pumpUntil(tester, find.text('Save to Files…'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('holiday.pdf'), findsOneWidget);
  });
}
