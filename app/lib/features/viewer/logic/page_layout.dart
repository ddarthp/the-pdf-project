import 'dart:math' as math;
import 'dart:ui';

/// Result of laying out a document's pages on the viewer canvas.
class PageLayoutResult {
  const PageLayoutResult({required this.pageRects, required this.documentSize});

  /// One rect per page, in document coordinates, in page order.
  final List<Rect> pageRects;

  /// Bounding size of the whole laid-out document.
  final Size documentSize;
}

/// Pure page-layout maths, kept free of pdfrx types so it can be unit tested
/// without a PDFium document. [buildPdfPageLayout] adapts the result for
/// `PdfViewerParams.layoutPages`.
abstract final class PageLayouts {
  /// Continuous scroll: pages stacked vertically, horizontally centred on the
  /// widest page.
  static PageLayoutResult vertical(List<Size> pageSizes, double margin) {
    if (pageSizes.isEmpty) return PageLayoutResult(pageRects: const [], documentSize: Size.zero);

    final maxWidth = pageSizes.fold(0.0, (acc, s) => math.max(acc, s.width));
    final rects = <Rect>[];
    var y = margin;
    for (final size in pageSizes) {
      rects.add(Rect.fromLTWH(margin + (maxWidth - size.width) / 2, y, size.width, size.height));
      y += size.height + margin;
    }
    return PageLayoutResult(
      pageRects: rects,
      documentSize: Size(maxWidth + margin * 2, y),
    );
  }

  /// Single page: each page centred in an identically sized slot laid out left
  /// to right. Uniform slots are what make snap-to-page a simple rounding of
  /// the horizontal offset (see [pageNumberForOffset]).
  static PageLayoutResult horizontalPaged(List<Size> pageSizes, double margin) {
    if (pageSizes.isEmpty) return PageLayoutResult(pageRects: const [], documentSize: Size.zero);

    final maxWidth = pageSizes.fold(0.0, (acc, s) => math.max(acc, s.width));
    final maxHeight = pageSizes.fold(0.0, (acc, s) => math.max(acc, s.height));
    final slotWidth = maxWidth + margin;
    final rects = <Rect>[];
    for (var i = 0; i < pageSizes.length; i++) {
      final size = pageSizes[i];
      rects.add(
        Rect.fromLTWH(
          margin + i * slotWidth + (maxWidth - size.width) / 2,
          margin + (maxHeight - size.height) / 2,
          size.width,
          size.height,
        ),
      );
    }
    return PageLayoutResult(
      pageRects: rects,
      documentSize: Size(margin + pageSizes.length * slotWidth, maxHeight + margin * 2),
    );
  }

  /// Page number (1-based) whose slot is closest to [centerX], for the
  /// horizontally paged layout produced by [horizontalPaged].
  static int pageNumberForOffset({
    required double centerX,
    required List<Rect> pageRects,
  }) {
    if (pageRects.isEmpty) return 1;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < pageRects.length; i++) {
      final distance = (pageRects[i].center.dx - centerX).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best + 1;
  }
}
