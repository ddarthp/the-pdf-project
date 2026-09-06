import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart' as pdf;

import '../logic/image_page_layout.dart';
import '../model/picked_image.dart';

/// Builds a PDF from a list of images, one page each.
///
/// Every page is exactly the shape of its picture and the picture fills it,
/// which keeps the whole arrangement to a single instruction — draw this
/// image over this page — and lets the picture's own bytes go into the
/// document untouched. A JPEG photograph stays a JPEG, so an album of them
/// does not swell on the way in.
class ImagePdfBuilder {
  const ImagePdfBuilder();

  Future<Uint8List> build(List<PickedImage> images) async {
    if (images.isEmpty) {
      throw StateError('A PDF needs at least one page.');
    }

    final document = pdf.PdfDocument();
    for (final image in images) {
      final page = ImagePageLayout.pageSizeFor(
        imageWidth: image.pixelWidth.toDouble(),
        imageHeight: image.pixelHeight.toDouble(),
      );
      final pdfPage = pdf.PdfPage(
        document,
        pageFormat: pdf.PdfPageFormat(page.width, page.height),
      );
      pdfPage
          .getGraphics()
          .drawImage(
            pdf.PdfImage.file(document, bytes: image.bytes),
            0,
            0,
            page.width,
            page.height,
          );
    }

    return document.save();
  }
}
