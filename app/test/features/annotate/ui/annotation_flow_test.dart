@Tags(['pdfium'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/annotate/model/annotation.dart';
import 'package:the_pdf_project/features/annotate/services/annotation_store.dart';
import 'package:the_pdf_project/features/annotate/ui/annotations_panel.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/services/last_page_store.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_bottom_bar.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_screen.dart';

import '../../../support/pdfium_test_support.dart';

class _FixturePdfPicker extends PdfPicker {
  const _FixturePdfPicker();

  @override
  Future<PdfSource?> pickPdf() async =>
      const PdfFileSource(path: sampleFixture, displayName: 'sample.pdf');
}

void main() {
  setUpAll(initializePdfiumForTests);

  late InMemoryAnnotationStore store;

  setUp(() => store = InMemoryAnnotationStore());

  Future<void> pumpViewer(WidgetTester tester, {Key key = const ValueKey('viewer')}) {
    return tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          key: key,
          preferences: ViewPreferences(),
          picker: const _FixturePdfPicker(),
          lastPageStore: InMemoryLastPageStore(),
          annotationStore: store,
        ),
      ),
    );
  }

  Future<void> openDocument(WidgetTester tester, {Key key = const ValueKey('viewer')}) async {
    await pumpViewer(tester, key: key);
    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await pumpUntil(tester, find.text('1 / 3'));
  }

  Future<void> enterAnnotationMode(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Annotate'));
    await tester.pumpAndSettle();
  }

  Future<void> selectTool(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
  }

  /// Drags across the page the way a finger would, in several steps, so the
  /// layer sees the move events a real stroke produces.
  Future<void> drag(WidgetTester tester, Offset start, Offset end, {int steps = 6}) async {
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= steps; step++) {
      await gesture.moveTo(Offset.lerp(start, end, step / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Lets pending work finish — reading a page's text for a highlight, and
  /// the controller's save debounce — then reads the stored result.
  Future<List<Annotation>> storedAnnotations(WidgetTester tester) async {
    await drainBackgroundLoading(tester);
    return store.load('file:$sampleFixture');
  }

  documentTest('the toolbar takes over the bottom bar while annotating', (tester) async {
    await openDocument(tester);

    expect(find.byType(ViewerBottomBar), findsOneWidget);

    await enterAnnotationMode(tester);
    expect(find.byType(ViewerBottomBar), findsNothing);
    expect(find.byTooltip('Draw'), findsOneWidget);
    expect(find.byTooltip('Eraser'), findsOneWidget);

    await tester.tap(find.byTooltip('Done annotating'));
    await tester.pumpAndSettle();
    expect(find.byType(ViewerBottomBar), findsOneWidget);
  });

  documentTest('drawing stores a stroke on the page in normalised coordinates', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);

    await drag(tester, const Offset(300, 400), const Offset(700, 600));

    final annotations = await storedAnnotations(tester);
    expect(annotations, hasLength(1));
    final stroke = annotations.single as InkAnnotation;
    expect(stroke.pageNumber, 1);
    expect(stroke.strokes.single.length, greaterThan(2));
    for (final point in stroke.strokes.single) {
      expect(point.dx, inInclusiveRange(0, 1));
      expect(point.dy, inInclusiveRange(0, 1));
    }
    // The stroke ran down and to the right, and covers real ground.
    expect(stroke.normalizedBounds.width, greaterThan(0.1));
    expect(stroke.normalizedBounds.height, greaterThan(0.02));
  });

  documentTest('the same drag covers less of the page when zoomed in', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 600));
    final atFit = (await storedAnnotations(tester)).single.normalizedBounds;

    // A fresh screen, zoomed in before annotating.
    store = InMemoryAnnotationStore();
    await openDocument(tester, key: const ValueKey('zoomed'));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 600));
    final zoomedIn = (await storedAnnotations(tester)).single.normalizedBounds;

    // The same swipe across the glass covers less of the page once the page is
    // drawn bigger — which is the whole point of storing page fractions.
    expect(zoomedIn.width, lessThan(atFit.width));
  });

  documentTest('the eraser removes a stroke it is dragged over', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 400));
    expect(await storedAnnotations(tester), hasLength(1));

    await selectTool(tester, 'Eraser');
    await tester.tapAt(const Offset(500, 400));
    await tester.pumpAndSettle();

    expect(await storedAnnotations(tester), isEmpty);
  });

  documentTest('an annotation can be selected and dragged somewhere else', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 400));
    final before = (await storedAnnotations(tester)).single.normalizedBounds;

    await selectTool(tester, 'Select');
    await drag(tester, const Offset(500, 400), const Offset(500, 600));

    final after = (await storedAnnotations(tester)).single.normalizedBounds;
    expect(after.top, greaterThan(before.top));
    expect(after.width, closeTo(before.width, 1e-6), reason: 'moving must not resize it');
  });

  documentTest('shapes are drawn with the shape tools', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);

    await selectTool(tester, 'Rectangle');
    await drag(tester, const Offset(300, 300), const Offset(600, 500));
    await selectTool(tester, 'Arrow');
    await drag(tester, const Offset(300, 700), const Offset(600, 800));

    final annotations = await storedAnnotations(tester);
    expect(annotations.map((a) => (a as ShapeAnnotation).kind), [
      ShapeKind.rectangle,
      ShapeKind.arrow,
    ]);
  });

  documentTest('a tap with a shape tool is too small to become a shape', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await selectTool(tester, 'Ellipse');

    await tester.tapAt(const Offset(400, 400));
    await tester.pumpAndSettle();

    expect(await storedAnnotations(tester), isEmpty);
  });

  documentTest('a sticky note asks for its text and shows it in the panel', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await selectTool(tester, 'Sticky note');

    await tester.tapAt(const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(find.text('Sticky note'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'check this figure');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final annotations = await storedAnnotations(tester);
    expect((annotations.single as StickyNoteAnnotation).text, 'check this figure');
  });

  documentTest('highlighting snaps to the text it was dragged across', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await selectTool(tester, 'Highlight');

    // Sweep the full width of the page across the upper text area, which on
    // the fixture's first page is the "Page 1" heading and the line under it.
    await drag(tester, const Offset(60, 200), const Offset(940, 420));

    final annotations = await storedAnnotations(tester);
    expect(annotations, hasLength(1));
    final highlight = annotations.single as HighlightAnnotation;
    expect(highlight.bands, isNotEmpty);
    expect(highlight.text, contains('Page 1'));
    // Bands hug the text rather than filling the whole swept rectangle.
    expect(highlight.normalizedBounds.width, lessThan(0.9));
  });

  documentTest('the panel lists annotations and can delete them', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 400));
    await tester.tap(find.byTooltip('Done annotating'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Outline and thumbnails'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.byType(AnnotationsPanel), findsOneWidget);
    expect(find.text('Page 1 · 1 annotation'), findsOneWidget);
    expect(find.text('Drawing'), findsWidgets);

    await tester.tap(find.byTooltip('Delete annotation'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No annotations yet'), findsOneWidget);
    expect(await storedAnnotations(tester), isEmpty);
  });

  documentTest('tapping an annotation in the panel goes back to it', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 400));
    await tester.tap(find.byTooltip('Done annotating'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Last page'));
    await pumpUntil(tester, find.text('3 / 3'));

    await tester.tap(find.byTooltip('Outline and thumbnails'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drawing').first);
    // It reopens the tools with the annotation selected, ready to edit.
    await pumpUntil(tester, find.byTooltip('Delete selected'));
    // Let the drawer finish closing before reaching for the toolbar under it.
    await tester.pumpAndSettle();
    expect(
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Delete selected'),
          matching: find.byType(IconButton),
        ),
      ).onPressed,
      isNotNull,
      reason: 'the annotation should be selected',
    );

    // And it took the reader back to the page the annotation is on.
    await tester.tap(find.byTooltip('Done annotating'));
    await pumpUntil(tester, find.text('1 / 3'));
  });

  documentTest('changing colour restyles the selected annotation', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 400));

    // Drawing leaves the new annotation selected, so the toolbar edits it.
    await tester.tap(find.byTooltip('Green'));
    await tester.pumpAndSettle();

    expect((await storedAnnotations(tester)).single.color, const Color(0xFF43A047));
  });

  documentTest('annotations come back when the document is opened again', (tester) async {
    await openDocument(tester);
    await enterAnnotationMode(tester);
    await drag(tester, const Offset(300, 400), const Offset(700, 400));
    expect(await storedAnnotations(tester), hasLength(1));

    // A fresh screen sharing the store, as if the app had been restarted.
    await openDocument(tester, key: const ValueKey('restarted'));
    await tester.tap(find.byTooltip('Outline and thumbnails'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 · 1 annotation'), findsOneWidget);
  });
}
