@Tags(['pdfium'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/annotate/model/annotation.dart';
import 'package:the_pdf_project/features/annotate/logic/resize_handles.dart';
import 'package:the_pdf_project/features/annotate/services/annotation_store.dart';
import 'package:the_pdf_project/features/signature/logic/signature_geometry.dart';
import 'package:the_pdf_project/features/signature/model/signature_source.dart';
import 'package:the_pdf_project/features/signature/ui/signature_canvas.dart';
import 'package:the_pdf_project/features/signature/ui/signature_image_picker.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/services/last_page_store.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_screen.dart';

import '../../../support/pdfium_test_support.dart';

class _FixturePdfPicker extends PdfPicker {
  const _FixturePdfPicker();

  @override
  Future<PdfSource?> pickPdf() async =>
      const PdfFileSource(path: sampleFixture, displayName: 'sample.pdf');
}

/// Hands back a small picture instead of opening the system image picker.
class _FakeImagePicker extends SignatureImagePicker {
  const _FakeImagePicker();

  @override
  Future<PickedSignatureImage?> pick() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 80, 20),
      Paint()..color = const Color(0xFF102030),
    );
    final image = await recorder.endRecording().toImage(80, 20);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return PickedSignatureImage(
        bytes: data!.buffer.asUint8List(),
        aspectRatio: 4,
      );
    } finally {
      image.dispose();
    }
  }
}

void main() {
  setUpAll(initializePdfiumForTests);

  late InMemoryAnnotationStore store;

  setUp(() => store = InMemoryAnnotationStore());

  Future<void> openDocument(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          preferences: ViewPreferences(),
          picker: const _FixturePdfPicker(),
          lastPageStore: InMemoryLastPageStore(),
          annotationStore: store,
          signatureImagePicker: const _FakeImagePicker(),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await pumpUntil(tester, find.text('1 / 3'));
    await tester.tap(find.byTooltip('Annotate'));
    await tester.pumpAndSettle();
  }

  Future<List<Annotation>> stored(WidgetTester tester) async {
    await drainBackgroundLoading(tester);
    return store.load('file:$sampleFixture');
  }

  Future<void> selectTool(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, Offset start, Offset end, {int steps = 6}) async {
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= steps; step++) {
      await gesture.moveTo(Offset.lerp(start, end, step / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Taps the page with the signature tool and draws one on the pad.
  Future<void> placeDrawnSignatureAt(WidgetTester tester, Offset at) async {
    await selectTool(tester, 'Signature');
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.byType(SignatureCanvas), findsOneWidget);

    final canvas = tester.getRect(find.byType(SignatureCanvas));
    await drag(tester, canvas.centerLeft + const Offset(20, 20), canvas.center);
    await tester.tap(find.widgetWithText(FilledButton, 'Place'));
    await tester.pumpAndSettle();
  }

  documentTest('a drawn signature lands where it was dropped', (tester) async {
    await openDocument(tester);

    await placeDrawnSignatureAt(tester, const Offset(400, 600));

    final annotations = await stored(tester);
    expect(annotations, hasLength(1));
    final signature = annotations.single as SignatureAnnotation;
    expect(signature.pageNumber, 1);
    expect(signature.source, isA<DrawnSignature>());
    expect(signature.bounds.width, closeTo(SignatureGeometry.defaultWidthFraction, 1e-6));
    expect(signature.bounds.left, greaterThanOrEqualTo(0));
    expect(signature.bounds.right, lessThanOrEqualTo(1));
  });

  documentTest('placing a signature leaves it selected, ready to adjust', (tester) async {
    await openDocument(tester);

    await placeDrawnSignatureAt(tester, const Offset(400, 600));

    // The select tool takes over, so the next touch adjusts rather than
    // dropping another signature.
    expect(
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Delete selected'),
          matching: find.byType(IconButton),
        ),
      ).onPressed,
      isNotNull,
    );
  });

  documentTest('a typed signature keeps the name that was typed', (tester) async {
    await openDocument(tester);
    await selectTool(tester, 'Signature');
    await tester.tapAt(const Offset(400, 600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ada Lovelace');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Place'));
    await tester.pumpAndSettle();

    final signature = (await stored(tester)).single as SignatureAnnotation;
    expect(signature.source, isA<TypedSignature>());
    expect((signature.source as TypedSignature).text, 'Ada Lovelace');
  });

  documentTest('a signature can be chosen from a picture', (tester) async {
    await openDocument(tester);
    await selectTool(tester, 'Signature');
    await tester.tapAt(const Offset(400, 600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Choose image'));
    // Decoding and re-encoding the picture is real async work.
    await pumpUntil(tester, find.text('Choose another'));
    await tester.tap(find.widgetWithText(FilledButton, 'Place'));
    await tester.pumpAndSettle();

    final signature = (await stored(tester)).single as SignatureAnnotation;
    expect(signature.source, isA<ImageSignature>());
    expect((signature.source as ImageSignature).bytes, isNotEmpty);
  });

  documentTest('backing out of the pad places nothing', (tester) async {
    await openDocument(tester);
    await selectTool(tester, 'Signature');
    await tester.tapAt(const Offset(400, 600));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(await stored(tester), isEmpty);
  });

  documentTest('a placed signature can be dragged somewhere else', (tester) async {
    await openDocument(tester);
    await placeDrawnSignatureAt(tester, const Offset(400, 500));
    final before = (await stored(tester)).single.normalizedBounds;

    // Placing leaves the select tool active, so this drags the signature.
    await drag(tester, const Offset(400, 500), const Offset(400, 700));

    final after = (await stored(tester)).single.normalizedBounds;
    expect(after.top, greaterThan(before.top));
    expect(after.width, closeTo(before.width, 1e-6), reason: 'moving must not resize it');
  });

  documentTest('dragging a corner handle resizes a placed signature', (tester) async {
    await openDocument(tester);

    // Where the page sits on screen is decided by pdfrx, so work it out: drop
    // a signature at two known points and see where each one landed.
    await placeDrawnSignatureAt(tester, const Offset(400, 500));
    final first = (await stored(tester)).single.normalizedBounds.center;
    await selectTool(tester, 'Eraser');
    await tester.tapAt(const Offset(400, 500));
    await tester.pumpAndSettle();

    await placeDrawnSignatureAt(tester, const Offset(600, 700));
    final second = (await stored(tester)).single.normalizedBounds.center;

    final scaleX = (600 - 400) / (second.dx - first.dx);
    final scaleY = (700 - 500) / (second.dy - first.dy);
    Offset toScreen(Offset normalized) => Offset(
      400 + (normalized.dx - first.dx) * scaleX,
      500 + (normalized.dy - first.dy) * scaleY,
    );

    final before = (await stored(tester)).single.normalizedBounds;
    // The handles sit a fixed few pixels outside the annotation, wherever the
    // page is zoomed to; grab the bottom-right one and pull it out and down.
    final handle =
        toScreen(before.bottomRight) + const Offset(ResizeHandles.inset, ResizeHandles.inset);
    await drag(tester, handle, handle + const Offset(120, 60));

    final after = (await stored(tester)).single.normalizedBounds;
    expect(after.width, greaterThan(before.width));
    expect(after.height, greaterThan(before.height));
    // The opposite corner stayed where it was.
    expect(after.left, closeTo(before.left, 1e-6));
    expect(after.top, closeTo(before.top, 1e-6));
  });
}
