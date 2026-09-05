@Tags(['pdfium'])
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/annotate/model/annotation.dart';
import 'package:the_pdf_project/features/annotate/services/pdf_annotation_writer.dart';

import '../../../support/pdf_annotation_reader.dart';
import '../../../support/pdfium_test_support.dart';

final _createdAt = DateTime.utc(2026, 9, 5);
const _red = Color(0xFFE53935);

InkAnnotation ink({List<List<Offset>>? strokes, double opacity = 1}) => InkAnnotation(
  id: 'ink',
  pageNumber: 1,
  color: _red,
  opacity: opacity,
  createdAt: _createdAt,
  strokes: strokes ??
      const [
        [Offset(0.2, 0.3), Offset(0.5, 0.3), Offset(0.8, 0.5)],
      ],
  strokeWidth: 4,
);

ShapeAnnotation shape(ShapeKind kind, {Offset? start, Offset? end}) => ShapeAnnotation(
  id: 'shape-${kind.name}',
  pageNumber: 1,
  color: const Color(0xFF1E88E5),
  opacity: 1,
  createdAt: _createdAt,
  kind: kind,
  start: start ?? const Offset(0.2, 0.2),
  end: end ?? const Offset(0.7, 0.6),
  strokeWidth: 3,
);

void main() {
  const writer = PdfAnnotationWriter();

  setUpAll(initializePdfiumForTests);

  /// Opens a fresh copy of the fixture, so each test writes into its own
  /// document exactly the way the export does.
  Future<PdfDocument> openFixture() async {
    final document = await PdfDocument.openFile(sampleFixture);
    addTearDown(document.dispose);
    return document;
  }

  Future<List<WrittenAnnotation>> exportAndRead(
    List<Annotation> annotations, {
    int pageNumber = 1,
  }) async {
    final result = await writer.export(await openFixture(), annotations);
    expect(result.written, annotations.length, reason: 'every annotation should be written');
    return readAnnotations(result.bytes, pageNumber);
  }

  test('an export with no annotations still produces a readable PDF', () async {
    final result = await writer.export(await openFixture(), const []);

    expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
    final reopened = await PdfDocument.openData(result.bytes, sourceName: 'empty-export');
    addTearDown(reopened.dispose);
    expect(reopened.pages, hasLength(3));
    expect(await readAnnotations(result.bytes, 1), isEmpty);
  });

  group('subtypes PDFium draws itself', () {
    test('ink becomes an ink annotation with its colour and opacity', () async {
      final written = await exportAndRead([ink(opacity: 0.5)]);

      expect(written, hasLength(1));
      final annotation = written.single;
      expect(annotation.subtype, pdfium_bindings.FPDF_ANNOT_INK);
      expect((annotation.red, annotation.green, annotation.blue), (229, 57, 53));
      expect(annotation.alpha, closeTo(127, 2));
    });

    test('a rectangle becomes a square annotation covering the right area', () async {
      final written = await exportAndRead([shape(ShapeKind.rectangle)]);

      final annotation = written.single;
      expect(annotation.subtype, pdfium_bindings.FPDF_ANNOT_SQUARE);
      // The fixture is A4: 595 x 842 points. The shape spans 0.2-0.7 across
      // and 0.2-0.6 down, and the rectangle is grown by the stroke width.
      expect(annotation.left, closeTo(595 * 0.2 - 3, 1));
      expect(annotation.right, closeTo(595 * 0.7 + 3, 1));
      // y is measured up from the bottom, so the top of the shape is the
      // larger number.
      expect(annotation.top, closeTo(842 * 0.8 + 3, 1));
      expect(annotation.bottom, closeTo(842 * 0.4 - 3, 1));
    });

    test('an ellipse becomes a circle annotation', () async {
      final written = await exportAndRead([shape(ShapeKind.ellipse)]);

      expect(written.single.subtype, pdfium_bindings.FPDF_ANNOT_CIRCLE);
    });

    test('a highlight becomes a highlight annotation spanning its bands', () async {
      final written = await exportAndRead([
        HighlightAnnotation(
          id: 'h',
          pageNumber: 1,
          color: const Color(0xFFFDD835),
          opacity: 0.4,
          createdAt: _createdAt,
          bands: const [
            Rect.fromLTRB(0.1, 0.1, 0.9, 0.14),
            Rect.fromLTRB(0.1, 0.2, 0.5, 0.24),
          ],
          text: 'two lines',
        ),
      ]);

      final annotation = written.single;
      expect(annotation.subtype, pdfium_bindings.FPDF_ANNOT_HIGHLIGHT);
      expect((annotation.red, annotation.green, annotation.blue), (253, 216, 53));
      // The rectangle wraps both bands.
      expect(annotation.left, closeTo(595 * 0.1, 1));
      expect(annotation.right, closeTo(595 * 0.9, 1));
      expect(annotation.height, closeTo(842 * 0.14, 2));
    });

    test('a sticky note becomes a text annotation carrying its comment', () async {
      final written = await exportAndRead([
        StickyNoteAnnotation(
          id: 'n',
          pageNumber: 1,
          color: const Color(0xFFFB8C00),
          opacity: 1,
          createdAt: _createdAt,
          anchor: const Offset(0.5, 0.5),
          text: 'ask about this figure',
        ),
      ]);

      final annotation = written.single;
      expect(annotation.subtype, pdfium_bindings.FPDF_ANNOT_TEXT);
      expect(annotation.contents, 'ask about this figure');
      expect(annotation.width, closeTo(StickyNoteAnnotation.markerSize, 0.5));
    });
  });

  group('subtypes that need an appearance stream', () {
    test('a line carries a hand-written appearance that draws it', () async {
      final written = await exportAndRead([
        shape(ShapeKind.line, start: const Offset(0.2, 0.3), end: const Offset(0.8, 0.3)),
      ]);

      final annotation = written.single;
      // PDFium refuses to create the subtypes it cannot draw itself, so a line
      // rides on a stamp carrying the appearance written for it.
      expect(annotation.subtype, pdfium_bindings.FPDF_ANNOT_STAMP);
      // The endpoints are in the stream, in page coordinates.
      expect(annotation.appearance, contains((595 * 0.2).toStringAsFixed(0)));
      expect(annotation.appearance, contains(' m\n'));
      expect(annotation.appearance, contains(' l\n'));
      expect(annotation.appearance, contains('S\n'));
      // The colour is in the stream, as a stroke colour. It cannot be read
      // back with FPDFAnnot_GetColor: PDFium refuses that once an annotation
      // has an appearance stream, which is also why the colour is set before
      // the appearance when writing.
      expect(annotation.appearance, contains('0.118 0.533 0.898 RG'));
      expect(annotation.alpha, -1, reason: 'GetColor is unavailable with an appearance');
    });

    test('an arrow draws its head as well as its shaft', () async {
      final line = await exportAndRead([
        shape(ShapeKind.line, start: const Offset(0.2, 0.3), end: const Offset(0.8, 0.3)),
      ]);
      final arrow = await exportAndRead([
        shape(ShapeKind.arrow, start: const Offset(0.2, 0.3), end: const Offset(0.8, 0.3)),
      ]);

      // Three strokes rather than one: the shaft and two barbs.
      expect('S\n'.allMatches(line.single.appearance), hasLength(1));
      expect('S\n'.allMatches(arrow.single.appearance), hasLength(3));
      // And the rectangle is tall enough to hold the head.
      expect(arrow.single.height, greaterThan(line.single.height));
    });

    test('a text box becomes a stamp whose appearance holds real text', () async {
      final written = await exportAndRead([
        TextBoxAnnotation(
          id: 't',
          pageNumber: 1,
          color: const Color(0xFF000000),
          opacity: 1,
          createdAt: _createdAt,
          bounds: const Rect.fromLTRB(0.1, 0.1, 0.8, 0.2),
          text: 'remember this',
          fontSize: 14,
        ),
      ]);

      final annotation = written.single;
      expect(annotation.subtype, pdfium_bindings.FPDF_ANNOT_STAMP);
      // The text is readable in a viewer's comment list...
      expect(annotation.contents, 'remember this');
      // ...and drawn, as an image placed in the stamp's appearance.
      expect(annotation.appearance, contains('Do'));
    });

    test('an empty text box is skipped rather than written blank', () async {
      final result = await writer.export(await openFixture(), [
        TextBoxAnnotation(
          id: 't',
          pageNumber: 1,
          color: const Color(0xFF000000),
          opacity: 1,
          createdAt: _createdAt,
          bounds: const Rect.fromLTRB(0.1, 0.1, 0.8, 0.2),
          text: '',
          fontSize: 14,
        ),
      ]);

      expect(result.written, 0);
      expect(result.skipped, 1);
      expect(await readAnnotations(result.bytes, 1), isEmpty);
    });
  });

  group('across the document', () {
    test('annotations land on the pages they belong to', () async {
      final result = await writer.export(await openFixture(), [
        ink(),
        ShapeAnnotation(
          id: 'on-page-3',
          pageNumber: 3,
          color: _red,
          opacity: 1,
          createdAt: _createdAt,
          kind: ShapeKind.rectangle,
          start: const Offset(0.2, 0.2),
          end: const Offset(0.6, 0.6),
          strokeWidth: 3,
        ),
      ]);

      expect(await readAnnotations(result.bytes, 1), hasLength(1));
      expect(await readAnnotations(result.bytes, 2), isEmpty);
      expect(await readAnnotations(result.bytes, 3), hasLength(1));
    });

    test('the document keeps its pages and text', () async {
      final result = await writer.export(await openFixture(), [ink()]);

      final reopened = await PdfDocument.openData(result.bytes, sourceName: 'kept');
      addTearDown(reopened.dispose);
      expect(reopened.pages, hasLength(3));
      expect((await reopened.pages[1].loadStructuredText()).fullText, contains('haystack'));
    });

    test('one export writes every kind of annotation', () async {
      final written = await exportAndRead([
        ink(),
        shape(ShapeKind.rectangle),
        shape(ShapeKind.ellipse, start: const Offset(0.1, 0.7), end: const Offset(0.4, 0.9)),
        shape(ShapeKind.line, start: const Offset(0.1, 0.62), end: const Offset(0.9, 0.62)),
        shape(ShapeKind.arrow, start: const Offset(0.1, 0.66), end: const Offset(0.9, 0.66)),
        HighlightAnnotation(
          id: 'h',
          pageNumber: 1,
          color: const Color(0xFFFDD835),
          opacity: 0.4,
          createdAt: _createdAt,
          bands: const [Rect.fromLTRB(0.1, 0.1, 0.9, 0.14)],
          text: 'a line',
        ),
        StickyNoteAnnotation(
          id: 'n',
          pageNumber: 1,
          color: const Color(0xFFFB8C00),
          opacity: 1,
          createdAt: _createdAt,
          anchor: const Offset(0.85, 0.05),
          text: 'note',
        ),
        TextBoxAnnotation(
          id: 't',
          pageNumber: 1,
          color: const Color(0xFF8E24AA),
          opacity: 1,
          createdAt: _createdAt,
          bounds: const Rect.fromLTRB(0.1, 0.75, 0.9, 0.85),
          text: 'a text box',
          fontSize: 14,
        ),
      ]);

      expect(written, hasLength(8));
      expect(written.map((a) => a.subtype).toSet(), {
        pdfium_bindings.FPDF_ANNOT_INK,
        pdfium_bindings.FPDF_ANNOT_SQUARE,
        pdfium_bindings.FPDF_ANNOT_CIRCLE,
        pdfium_bindings.FPDF_ANNOT_HIGHLIGHT,
        pdfium_bindings.FPDF_ANNOT_TEXT,
        // Line, arrow and text box all ride on stamps.
        pdfium_bindings.FPDF_ANNOT_STAMP,
      });
      // The three that carry their own drawing have one.
      expect(
        written.where((a) => a.appearance.isNotEmpty),
        hasLength(3),
        reason: 'line, arrow and text box each carry an appearance stream',
      );
    });
  });

  group('the annotations actually paint', () {
    /// Renders a page twice — once with annotations, once without — and counts
    /// how many pixels differ. Reading the appearance stream proves it exists;
    /// this proves PDFium draws it.
    Future<int> changedPixelCount(Uint8List pdfBytes, int pageNumber) async {
      final document = await PdfDocument.openData(
        pdfBytes,
        sourceName: 'render-$pageNumber-${pdfBytes.length}-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        final page = document.pages[pageNumber - 1];
        final withAnnotations = await page.render(width: 600, height: 848);
        final without = await page.render(
          width: 600,
          height: 848,
          annotationRenderingMode: PdfAnnotationRenderingMode.none,
        );
        try {
          var changed = 0;
          for (var i = 0; i < withAnnotations!.pixels.length; i++) {
            if (withAnnotations.pixels[i] != without!.pixels[i]) changed++;
          }
          return changed;
        } finally {
          withAnnotations?.dispose();
          without?.dispose();
        }
      } finally {
        await document.dispose();
      }
    }

    test('a page with no annotations renders identically either way', () async {
      final result = await writer.export(await openFixture(), const []);

      expect(await changedPixelCount(result.bytes, 1), 0);
    });

    test('a translucent stroke changes fewer pixels than a solid one', () async {
      final solid = await writer.export(await openFixture(), [ink()]);
      final faint = await writer.export(await openFixture(), [ink(opacity: 0.2)]);

      // Opacity reaches the file through the annotation's /CA, so the same
      // stroke drawn faintly disturbs the page less.
      expect(
        await changedPixelCount(faint.bytes, 1),
        lessThan(await changedPixelCount(solid.bytes, 1)),
      );
    });

    for (final entry in <String, Annotation>{
      'ink': ink(),
      'rectangle': shape(ShapeKind.rectangle),
      'ellipse': shape(ShapeKind.ellipse),
      'line': shape(ShapeKind.line, start: const Offset(0.1, 0.5), end: const Offset(0.9, 0.5)),
      'arrow': shape(ShapeKind.arrow, start: const Offset(0.1, 0.5), end: const Offset(0.9, 0.5)),
      'highlight': HighlightAnnotation(
        id: 'h',
        pageNumber: 1,
        color: const Color(0xFFFDD835),
        opacity: 0.4,
        createdAt: _createdAt,
        bands: const [Rect.fromLTRB(0.1, 0.1, 0.9, 0.16)],
        text: 'a line',
      ),
      'sticky note': StickyNoteAnnotation(
        id: 'n',
        pageNumber: 1,
        color: const Color(0xFFFB8C00),
        opacity: 1,
        createdAt: _createdAt,
        anchor: const Offset(0.5, 0.5),
        text: 'note',
      ),
      'text box': TextBoxAnnotation(
        id: 't',
        pageNumber: 1,
        color: const Color(0xFF000000),
        opacity: 1,
        createdAt: _createdAt,
        bounds: const Rect.fromLTRB(0.1, 0.4, 0.9, 0.5),
        text: 'remember this',
        fontSize: 20,
      ),
    }.entries) {
      test('${entry.key} changes the rendered page', () async {
        final result = await writer.export(await openFixture(), [entry.value]);

        expect(
          await changedPixelCount(result.bytes, 1),
          greaterThan(200),
          reason: '${entry.key} should visibly draw something',
        );
      });
    }
  });
}
