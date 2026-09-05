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

  /// Two-page spread: facing pages side by side, spreads stacked downwards.
  ///
  /// Columns are the width of the widest page in the document so spreads line
  /// up with each other; an odd final page sits alone in the left column.
  static PageLayoutResult verticalSpreads(List<Size> pageSizes, double margin) {
    if (pageSizes.isEmpty) return PageLayoutResult(pageRects: const [], documentSize: Size.zero);

    final columnWidth = pageSizes.fold(0.0, (acc, s) => math.max(acc, s.width));
    final spreadWidth = columnWidth * 2 + margin;
    final rects = List<Rect>.filled(pageSizes.length, Rect.zero);
    var y = margin;
    for (var i = 0; i < pageSizes.length; i += 2) {
      final left = pageSizes[i];
      final right = i + 1 < pageSizes.length ? pageSizes[i + 1] : null;
      final rowHeight = right == null ? left.height : math.max(left.height, right.height);

      rects[i] = Rect.fromLTWH(
        margin + (columnWidth - left.width) / 2,
        y + (rowHeight - left.height) / 2,
        left.width,
        left.height,
      );
      if (right != null) {
        rects[i + 1] = Rect.fromLTWH(
          margin + columnWidth + margin + (columnWidth - right.width) / 2,
          y + (rowHeight - right.height) / 2,
          right.width,
          right.height,
        );
      }
      y += rowHeight + margin;
    }
    return PageLayoutResult(
      pageRects: rects,
      documentSize: Size(spreadWidth + margin * 2, y),
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
