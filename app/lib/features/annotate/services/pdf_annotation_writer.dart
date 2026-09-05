import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

import '../../signature/model/signature_source.dart';
import '../logic/annotation_appearance.dart';
import '../logic/pdf_page_geometry.dart';
import '../model/annotation.dart';
import '../ui/annotation_painter.dart';

/// Writes the app's annotations into a PDF as real PDF annotations.
///
/// pdfrx renders annotations but cannot author them, so this drops to PDFium's
/// C API through `PdfDocument.useNativeDocumentHandle`, which hands over the
/// native document handle with pdfrx's worker suspended.
///
/// PDFium builds appearance streams itself for ink, square, circle, highlight
/// and text notes, so those five map straight onto native subtypes. Lines,
/// arrows, text boxes and signatures have no such subtype available and carry
/// an explicit appearance instead — see [_writeLine], [_writeRasterStamp] and
/// [_writeDrawnSignature].
class PdfAnnotationWriter {
  const PdfAnnotationWriter();

  /// How many of each annotation was written, for reporting back.
  static const _unsupported = -1;

  /// Pictures are drawn this many times larger than the page, then scaled
  /// down, so they stay sharp under zoom.
  static const _rasterScale = 4.0;

  /// A ceiling on the drawn size, so a full-page annotation cannot allocate an
  /// unreasonable bitmap.
  static const _maxRasterSide = 4000;

  /// Writes [annotations] into [document] and encodes the result.
  ///
  /// [document] is modified in place, so it should be a copy opened for the
  /// export rather than the one the viewer is showing.
  Future<PdfAnnotationExport> export(
    PdfDocument document,
    List<Annotation> annotations,
  ) async {
    final byPage = <int, List<Annotation>>{};
    for (final annotation in annotations) {
      byPage.putIfAbsent(annotation.pageNumber, () => []).add(annotation);
    }

    // Page geometry comes from pdfrx rather than from FFI: annotations were
    // authored against the page size pdfrx reported, so the export has to use
    // the same numbers.
    final geometryByPage = <int, PdfPageGeometry>{};
    for (final pageNumber in byPage.keys) {
      if (pageNumber < 1 || pageNumber > document.pages.length) continue;
      final page = document.pages[pageNumber - 1];
      geometryByPage[pageNumber] = PdfPageGeometry(
        displayWidth: page.width,
        displayHeight: page.height,
        quarterTurns: page.rotation.index,
      );
    }

    // Anything drawn with Flutter has to become pixels before crossing into
    // FFI; see [_writeRasterStamp].
    final images = await _decodeSignatureImages(annotations);
    final rasters = <String, _AnnotationRaster>{};
    try {
      for (final annotation in annotations) {
        if (!_needsRaster(annotation)) continue;
        final geometry = geometryByPage[annotation.pageNumber];
        if (geometry == null) continue;
        final raster = await _rasterize(annotation, geometry, images);
        if (raster != null) rasters[annotation.id] = raster;
      }
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
    }

    final written = await document.useNativeDocumentHandle(
      (handle) => _writeAll(handle, byPage, geometryByPage, rasters),
    );
    final bytes = await document.encodePdf();
    return PdfAnnotationExport(bytes: bytes, written: written, total: annotations.length);
  }

  int _writeAll(
    int handle,
    Map<int, List<Annotation>> byPage,
    Map<int, PdfPageGeometry> geometryByPage,
    Map<String, _AnnotationRaster> rasters,
  ) {
    final pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
    final nativeDocument = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);
    var written = 0;

    for (final entry in byPage.entries) {
      final geometry = geometryByPage[entry.key];
      if (geometry == null) continue;

      final page = pdfium.FPDF_LoadPage(nativeDocument, entry.key - 1);
      if (page == nullptr) continue;
      try {
        for (final annotation in entry.value) {
          if (_write(pdfium, nativeDocument, page, geometry, annotation, rasters) !=
              _unsupported) {
            written++;
          }
        }
        // Annotations live outside the page's content stream, but appending a
        // page object to a stamp's appearance does touch it.
        pdfium.FPDFPage_GenerateContent(page);
      } finally {
        pdfium.FPDF_ClosePage(page);
      }
    }
    return written;
  }

  int _write(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_DOCUMENT document,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    Annotation annotation,
    Map<String, _AnnotationRaster> rasters,
  ) {
    return switch (annotation) {
      InkAnnotation() => _writeInk(pdfium, page, geometry, annotation),
      HighlightAnnotation() => _writeHighlight(pdfium, page, geometry, annotation),
      StickyNoteAnnotation() => _writeStickyNote(pdfium, page, geometry, annotation),
      TextBoxAnnotation() => annotation.text.isEmpty
          ? _unsupported
          : _writeRasterStamp(
              pdfium,
              document,
              page,
              geometry,
              annotation,
              rasters[annotation.id],
              contents: annotation.text,
            ),
      SignatureAnnotation(:final source) => switch (source) {
        DrawnSignature() => _writeDrawnSignature(pdfium, page, geometry, annotation, source),
        _ => _writeRasterStamp(
          pdfium,
          document,
          page,
          geometry,
          annotation,
          rasters[annotation.id],
          contents: source is TypedSignature ? source.text : null,
        ),
      },
      ShapeAnnotation(:final kind) => switch (kind) {
        ShapeKind.rectangle => _writeBoxed(
          pdfium,
          page,
          geometry,
          annotation,
          pdfium_bindings.FPDF_ANNOT_SQUARE,
        ),
        ShapeKind.ellipse => _writeBoxed(
          pdfium,
          page,
          geometry,
          annotation,
          pdfium_bindings.FPDF_ANNOT_CIRCLE,
        ),
        ShapeKind.line || ShapeKind.arrow => _writeLine(pdfium, page, geometry, annotation),
      },
    };
  }

  // --- the five PDFium draws itself ----------------------------------------

  /// Freehand ink: PDFium keeps the stroke points and generates the drawing
  /// from `/InkList` plus the border width.
  int _writeInk(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    InkAnnotation annotation,
  ) {
    final annot = pdfium.FPDFPage_CreateAnnot(page, pdfium_bindings.FPDF_ANNOT_INK);
    if (annot == nullptr) return _unsupported;
    try {
      _setColor(pdfium, annot, annotation.color, annotation.opacity);
      pdfium.FPDFAnnot_SetBorder(annot, 0, 0, annotation.strokeWidth);

      final touched = <Offset>[];
      using((arena) {
        for (final stroke in annotation.strokes) {
          if (stroke.isEmpty) continue;
          final points = arena<pdfium_bindings.FS_POINTF>(stroke.length);
          for (var i = 0; i < stroke.length; i++) {
            final point = geometry.toPdfPoint(stroke[i]);
            points[i].x = point.dx;
            points[i].y = point.dy;
            touched.add(point);
          }
          pdfium.FPDFAnnot_AddInkStroke(annot, points, stroke.length);
        }
      });
      if (touched.isEmpty) return _unsupported;

      _setRect(
        pdfium,
        annot,
        geometry,
        PdfPointRect.containing(touched).inflate(annotation.strokeWidth),
      );
      return 1;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  /// Rectangle and ellipse share everything but their subtype.
  int _writeBoxed(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    ShapeAnnotation annotation,
    int subtype,
  ) {
    final annot = pdfium.FPDFPage_CreateAnnot(page, subtype);
    if (annot == nullptr) return _unsupported;
    try {
      _setColor(pdfium, annot, annotation.color, annotation.opacity);
      pdfium.FPDFAnnot_SetBorder(annot, 0, 0, annotation.strokeWidth);
      _setRect(
        pdfium,
        annot,
        geometry,
        geometry.toPdfRect(annotation.normalizedBounds).inflate(annotation.strokeWidth),
      );
      return 1;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  /// Highlight: one quadpoint set per band, which is what makes a highlight
  /// that spans several lines follow the text rather than covering the gaps.
  int _writeHighlight(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    HighlightAnnotation annotation,
  ) {
    if (annotation.bands.isEmpty) return _unsupported;
    final annot = pdfium.FPDFPage_CreateAnnot(page, pdfium_bindings.FPDF_ANNOT_HIGHLIGHT);
    if (annot == nullptr) return _unsupported;
    try {
      _setColor(pdfium, annot, annotation.color, annotation.opacity);
      using((arena) {
        for (final band in annotation.bands) {
          final rect = geometry.toPdfRect(band);
          final quad = arena<pdfium_bindings.FS_QUADPOINTSF>();
          // Quadpoints run top-left, top-right, bottom-left, bottom-right.
          quad.ref
            ..x1 = rect.left
            ..y1 = rect.top
            ..x2 = rect.right
            ..y2 = rect.top
            ..x3 = rect.left
            ..y3 = rect.bottom
            ..x4 = rect.right
            ..y4 = rect.bottom;
          pdfium.FPDFAnnot_AppendAttachmentPoints(annot, quad);
        }
      });
      _setRect(pdfium, annot, geometry, geometry.toPdfRect(annotation.normalizedBounds));
      return 1;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  /// Sticky note: a text annotation, which every reader shows as a note icon
  /// with the comment behind it.
  int _writeStickyNote(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    StickyNoteAnnotation annotation,
  ) {
    final annot = pdfium.FPDFPage_CreateAnnot(page, pdfium_bindings.FPDF_ANNOT_TEXT);
    if (annot == nullptr) return _unsupported;
    try {
      _setColor(pdfium, annot, annotation.color, annotation.opacity);
      _setString(pdfium, annot, 'Contents', annotation.text);

      final anchor = geometry.toPdfPoint(annotation.anchor);
      const size = StickyNoteAnnotation.markerSize;
      _setRect(
        pdfium,
        annot,
        geometry,
        PdfPointRect(
          left: anchor.dx,
          top: anchor.dy,
          right: anchor.dx + size,
          bottom: anchor.dy - size,
        ),
      );
      return 1;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  // --- the three that need an appearance stream ----------------------------

  /// Line and arrow.
  ///
  /// PDFium only lets you create the subtypes it can draw by itself, and a
  /// line annotation is not one of them — nor is there a setter for its `/L`
  /// endpoints. So the drawing is written out as an appearance stream on a
  /// stamp, whose whole job is to carry an appearance. That stream is only
  /// path operators, which need nothing in the appearance's resources, and
  /// the colour is set first so the annotation's `/CA` still carries the
  /// opacity.
  int _writeLine(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    ShapeAnnotation annotation,
  ) {
    final annot = pdfium.FPDFPage_CreateAnnot(page, pdfium_bindings.FPDF_ANNOT_STAMP);
    if (annot == nullptr) return _unsupported;
    try {
      _setColor(pdfium, annot, annotation.color, annotation.opacity);

      final from = geometry.toPdfPoint(annotation.start);
      final to = geometry.toPdfPoint(annotation.end);
      final appearance = annotation.kind == ShapeKind.arrow
          ? AnnotationAppearance.arrow(
              from: from,
              to: to,
              color: annotation.color,
              strokeWidth: annotation.strokeWidth,
            )
          : AnnotationAppearance.line(
              from: from,
              to: to,
              color: annotation.color,
              strokeWidth: annotation.strokeWidth,
            );

      // The rectangle has to be set before the appearance: PDFium uses it as
      // the appearance's bounding box, and anything outside is clipped away.
      _setRect(
        pdfium,
        annot,
        geometry,
        PdfPointRect.containing(appearance.extent).inflate(annotation.strokeWidth * 2),
      );
      _setAppearance(pdfium, annot, appearance.content);
      return 1;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  /// Text boxes, typed signatures and image signatures.
  ///
  /// All three end up as a picture in a stamp's appearance, because neither
  /// route to real PDF text is open: an appearance made by `FPDFAnnot_SetAP`
  /// gets an empty `/Resources`, leaving no font for `Tf` to name, and
  /// `FPDFPageObj_NewTextObj` reaches for PDFium's system font callback —
  /// which pdfrx binds to its worker isolate, so calling it from here aborts
  /// the process. Flutter draws them instead. Where there is text behind the
  /// picture it also goes into `/Contents`, so it stays readable in a
  /// viewer's comment list.
  int _writeRasterStamp(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_DOCUMENT document,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    Annotation annotation,
    _AnnotationRaster? raster, {
    String? contents,
  }) {
    if (raster == null) return _unsupported;
    final annot = pdfium.FPDFPage_CreateAnnot(page, pdfium_bindings.FPDF_ANNOT_STAMP);
    if (annot == nullptr) return _unsupported;
    try {
      if (contents != null && contents.isNotEmpty) {
        _setString(pdfium, annot, 'Contents', contents);
      }
      final rect = geometry.toPdfRect(annotation.normalizedBounds);
      _setRect(pdfium, annot, geometry, rect);

      final placed = using((arena) {
        final object = pdfium.FPDFPageObj_NewImageObj(document);
        if (object == nullptr) return false;

        final pixels = arena<Uint8>(raster.bgra.length);
        pixels.asTypedList(raster.bgra.length).setAll(0, raster.bgra);
        final bitmap = pdfium.FPDFBitmap_CreateEx(
          raster.width,
          raster.height,
          pdfium_bindings.FPDFBitmap_BGRA,
          pixels.cast<Void>(),
          raster.width * 4,
        );
        if (bitmap == nullptr) {
          pdfium.FPDFPageObj_Destroy(object);
          return false;
        }
        // SetBitmap copies the samples into the document, so the buffer and
        // the bitmap handle are both finished with once it returns.
        final copied = pdfium.FPDFImageObj_SetBitmap(nullptr, 0, object, bitmap) != 0;
        pdfium.FPDFBitmap_Destroy(bitmap);
        if (!copied) {
          pdfium.FPDFPageObj_Destroy(object);
          return false;
        }

        // An image object covers the unit square; this matrix stretches it
        // over the annotation rectangle.
        final matrix = arena<pdfium_bindings.FS_MATRIX>();
        matrix.ref
          ..a = rect.width
          ..b = 0
          ..c = 0
          ..d = rect.height
          ..e = rect.left
          ..f = rect.bottom;
        pdfium.FPDFPageObj_SetMatrix(object, matrix);

        if (pdfium.FPDFAnnot_AppendObject(annot, object) == 0) {
          pdfium.FPDFPageObj_Destroy(object);
          return false;
        }
        return true;
      });
      return placed ? 1 : _unsupported;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  /// A signature drawn by hand, kept as vector strokes.
  ///
  /// Unlike the other two kinds this one need not become pixels: strokes are
  /// path operators, which an appearance stream can carry without resources.
  /// A signature is the thing most likely to end up printed, so it is worth
  /// staying sharp at any size.
  int _writeDrawnSignature(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_PAGE page,
    PdfPageGeometry geometry,
    SignatureAnnotation annotation,
    DrawnSignature source,
  ) {
    if (source.strokes.every((stroke) => stroke.isEmpty)) return _unsupported;
    final annot = pdfium.FPDFPage_CreateAnnot(page, pdfium_bindings.FPDF_ANNOT_STAMP);
    if (annot == nullptr) return _unsupported;
    try {
      _setColor(pdfium, annot, annotation.color, annotation.opacity);

      final bounds = annotation.bounds;
      // Signature points are fractions of the signature's own box; put them
      // on the page first, then into PDF coordinates.
      Offset onPage(Offset point) => geometry.toPdfPoint(
        Offset(
          bounds.left + point.dx * bounds.width,
          bounds.top + point.dy * bounds.height,
        ),
      );
      final strokeWidth = source.strokeWidth * bounds.width * geometry.pageWidth;
      final appearance = AnnotationAppearance.strokes(
        strokes: [
          for (final stroke in source.strokes) [for (final point in stroke) onPage(point)],
        ],
        color: annotation.color,
        strokeWidth: strokeWidth,
      );
      if (appearance.extent.isEmpty) return _unsupported;

      // The rectangle has to be set before the appearance: PDFium uses it as
      // the appearance's bounding box, and anything outside is clipped away.
      _setRect(
        pdfium,
        annot,
        geometry,
        PdfPointRect.containing(appearance.extent).inflate(strokeWidth),
      );
      _setAppearance(pdfium, annot, appearance.content);
      return 1;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  /// Whether an annotation has to be drawn to pixels before it can be written.
  static bool _needsRaster(Annotation annotation) => switch (annotation) {
    TextBoxAnnotation() => true,
    SignatureAnnotation(:final source) => source is! DrawnSignature,
    _ => false,
  };

  /// Decodes the pictures behind any image signatures, so they can be drawn.
  Future<Map<String, ui.Image>> _decodeSignatureImages(List<Annotation> annotations) async {
    final images = <String, ui.Image>{};
    for (final annotation in annotations) {
      if (annotation case SignatureAnnotation(:final source, :final id)
          when source is ImageSignature) {
        try {
          final codec = await ui.instantiateImageCodec(source.bytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          images[id] = frame.image;
        } on Object catch (error) {
          debugPrint('Could not decode a signature image for export: $error');
        }
      }
    }
    return images;
  }

  /// Draws one annotation with Flutter and hands back its pixels in the byte
  /// order PDFium wants.
  ///
  /// The same painter that draws on screen is reused, handed a page rectangle
  /// sized so the annotation's own bounds fill the picture. Rendered at
  /// [_rasterScale] so it still looks sharp when the page is zoomed.
  Future<_AnnotationRaster?> _rasterize(
    Annotation annotation,
    PdfPageGeometry geometry,
    Map<String, ui.Image> images,
  ) async {
    final rect = geometry.toPdfRect(annotation.normalizedBounds);
    final width = (rect.width * _rasterScale).round().clamp(1, _maxRasterSide);
    final height = (rect.height * _rasterScale).round().clamp(1, _maxRasterSide);

    final bounds = annotation.normalizedBounds;
    final pageWidth = bounds.width == 0 ? width.toDouble() : width / bounds.width;
    final pageHeight = bounds.height == 0 ? height.toDouble() : height / bounds.height;
    final pageRect = Rect.fromLTWH(
      -bounds.left * pageWidth,
      -bounds.top * pageHeight,
      pageWidth,
      pageHeight,
    );

    final recorder = ui.PictureRecorder();
    AnnotationPainter.paint(
      Canvas(recorder),
      annotation,
      pageRect: pageRect,
      pageWidthInPoints: geometry.pageWidth,
      isSelected: false,
      selectionColor: const Color(0x00000000),
      signatureImage: (id) => images[id],
    );

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        return _AnnotationRaster(
          bgra: _toBgra(data.buffer.asUint8List()),
          width: width,
          height: height,
        );
      } finally {
        image.dispose();
      }
    } on Object catch (error) {
      debugPrint('Could not draw an annotation for export: $error');
      return null;
    } finally {
      picture.dispose();
    }
  }

  /// Flutter hands back RGBA; PDFium bitmaps are BGRA.
  static Uint8List _toBgra(Uint8List rgba) {
    final bgra = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      bgra[i] = rgba[i + 2];
      bgra[i + 1] = rgba[i + 1];
      bgra[i + 2] = rgba[i];
      bgra[i + 3] = rgba[i + 3];
    }
    return bgra;
  }

  // --- shared plumbing -----------------------------------------------------

  /// Sets `/C` and, from the alpha, `/CA` — which is where opacity comes from
  /// for every annotation, including the ones drawn by hand.
  ///
  /// Must run before any appearance stream exists; PDFium refuses otherwise.
  void _setColor(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_ANNOTATION annot,
    Color color,
    double opacity,
  ) {
    pdfium.FPDFAnnot_SetColor(
      annot,
      pdfium_bindings.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
      (opacity.clamp(0.0, 1.0) * 255).round(),
    );
  }

  void _setRect(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_ANNOTATION annot,
    PdfPageGeometry geometry,
    PdfPointRect rect,
  ) {
    final clamped = rect.clampToPage(geometry.pageWidth, geometry.pageHeight);
    using((arena) {
      final native = arena<pdfium_bindings.FS_RECTF>();
      native.ref
        ..left = clamped.left
        ..top = clamped.top
        ..right = clamped.right
        ..bottom = clamped.bottom;
      pdfium.FPDFAnnot_SetRect(annot, native);
    });
  }

  void _setString(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_ANNOTATION annot,
    String key,
    String value,
  ) {
    using((arena) {
      pdfium.FPDFAnnot_SetStringValue(
        annot,
        key.toNativeUtf8(allocator: arena).cast<Char>(),
        _toUtf16(arena, value),
      );
    });
  }

  void _setAppearance(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_ANNOTATION annot,
    String content,
  ) {
    using((arena) {
      pdfium.FPDFAnnot_SetAP(
        annot,
        pdfium_bindings.FPDF_ANNOT_APPEARANCEMODE_NORMAL,
        _toUtf16(arena, content),
      );
    });
  }

  /// PDFium takes strings as null-terminated UTF-16LE.
  Pointer<UnsignedShort> _toUtf16(Arena arena, String value) {
    final units = value.codeUnits;
    final buffer = arena<UnsignedShort>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      buffer[i] = units[i];
    }
    buffer[units.length] = 0;
    return buffer;
  }
}

/// The outcome of writing annotations into a document.
class PdfAnnotationExport {
  const PdfAnnotationExport({
    required this.bytes,
    required this.written,
    required this.total,
  });

  /// The encoded PDF.
  final Uint8List bytes;

  /// How many annotations made it into the file.
  final int written;

  /// How many were offered.
  final int total;

  /// Annotations that could not be written — an empty text box, say.
  int get skipped => total - written;
}

/// An annotation drawn to pixels, ready to be handed to PDFium.
class _AnnotationRaster {
  const _AnnotationRaster({required this.bgra, required this.width, required this.height});

  final Uint8List bgra;
  final int width;
  final int height;
}
