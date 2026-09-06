import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

/// One annotation as it exists in a saved PDF.
class WrittenAnnotation {
  const WrittenAnnotation({
    required this.subtype,
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
    required this.contents,
    required this.appearance,
  });

  final int subtype;
  final double left;
  final double bottom;
  final double right;
  final double top;
  final int red;
  final int green;
  final int blue;

  /// 0–255, written by PDFium into `/CA` from the colour's alpha.
  final int alpha;

  final String contents;

  /// The normal appearance stream, empty when the annotation has none.
  final String appearance;

  double get width => right - left;

  double get height => top - bottom;

  @override
  String toString() =>
      'WrittenAnnotation(subtype: $subtype, rect: ($left, $bottom, $right, $top), '
      'rgba: ($red, $green, $blue, $alpha), contents: "$contents")';
}

/// Reads the annotations back out of a saved PDF, through the same PDFium API
/// that wrote them.
///
/// pdfrx surfaces annotation metadata only for links, so verifying an export
/// means going to the C API directly.
Future<List<WrittenAnnotation>> readAnnotations(Uint8List pdfBytes, int pageNumber) async {
  final document = await PdfDocument.openData(
    pdfBytes,
    sourceName: 'verify-${pdfBytes.length}-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    return await document.useNativeDocumentHandle((handle) {
      final pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
      final nativeDocument = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);
      final page = pdfium.FPDF_LoadPage(nativeDocument, pageNumber - 1);
      if (page == nullptr) return const <WrittenAnnotation>[];
      try {
        return [
          for (var i = 0; i < pdfium.FPDFPage_GetAnnotCount(page); i++)
            _readAnnotation(pdfium, page, i),
        ].nonNulls.toList();
      } finally {
        pdfium.FPDF_ClosePage(page);
      }
    });
  } finally {
    await document.dispose();
  }
}

WrittenAnnotation? _readAnnotation(
  pdfium_bindings.PDFium pdfium,
  pdfium_bindings.FPDF_PAGE page,
  int index,
) {
  final annot = pdfium.FPDFPage_GetAnnot(page, index);
  if (annot == nullptr) return null;
  try {
    return using((arena) {
      final rect = arena<pdfium_bindings.FS_RECTF>();
      pdfium.FPDFAnnot_GetRect(annot, rect);

      final r = arena<UnsignedInt>();
      final g = arena<UnsignedInt>();
      final b = arena<UnsignedInt>();
      final a = arena<UnsignedInt>();
      final hasColor =
          pdfium.FPDFAnnot_GetColor(
            annot,
            pdfium_bindings.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            r,
            g,
            b,
            a,
          ) !=
          0;

      return WrittenAnnotation(
        subtype: pdfium.FPDFAnnot_GetSubtype(annot),
        left: rect.ref.left,
        bottom: rect.ref.bottom,
        right: rect.ref.right,
        top: rect.ref.top,
        red: hasColor ? r.value : -1,
        green: hasColor ? g.value : -1,
        blue: hasColor ? b.value : -1,
        alpha: hasColor ? a.value : -1,
        contents: _readString(pdfium, arena, annot, 'Contents'),
        appearance: _readAppearance(pdfium, arena, annot),
      );
    });
  } finally {
    pdfium.FPDFPage_CloseAnnot(annot);
  }
}

String _readString(
  pdfium_bindings.PDFium pdfium,
  Arena arena,
  pdfium_bindings.FPDF_ANNOTATION annot,
  String key,
) {
  final nativeKey = key.toNativeUtf8(allocator: arena).cast<Char>();
  final length = pdfium.FPDFAnnot_GetStringValue(annot, nativeKey, nullptr, 0);
  if (length <= 2) return '';
  final buffer = arena<UnsignedShort>(length ~/ 2);
  pdfium.FPDFAnnot_GetStringValue(annot, nativeKey, buffer, length);
  return _fromUtf16(buffer, length ~/ 2);
}

String _readAppearance(
  pdfium_bindings.PDFium pdfium,
  Arena arena,
  pdfium_bindings.FPDF_ANNOTATION annot,
) {
  const normal = pdfium_bindings.FPDF_ANNOT_APPEARANCEMODE_NORMAL;
  final length = pdfium.FPDFAnnot_GetAP(annot, normal, nullptr, 0);
  if (length <= 2) return '';
  final buffer = arena<UnsignedShort>(length ~/ 2);
  pdfium.FPDFAnnot_GetAP(annot, normal, buffer, length);
  return _fromUtf16(buffer, length ~/ 2);
}

/// PDFium hands strings back as null-terminated UTF-16LE.
String _fromUtf16(Pointer<UnsignedShort> buffer, int units) {
  final codes = <int>[];
  for (var i = 0; i < units; i++) {
    final code = buffer[i];
    if (code == 0) break;
    codes.add(code);
  }
  return String.fromCharCodes(codes);
}
