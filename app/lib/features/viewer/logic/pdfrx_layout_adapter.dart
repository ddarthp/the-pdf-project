import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import '../model/reading_mode.dart';
import 'page_layout.dart';

/// Bridges the pure [PageLayouts] maths to `PdfViewerParams.layoutPages`.
abstract final class PdfrxLayoutAdapter {
  static PdfPageLayout layout(ReadingMode mode, List<PdfPage> pages, PdfViewerParams params) {
    final sizes = [for (final page in pages) Size(page.width, page.height)];
    final result = switch (mode) {
      ReadingMode.continuousScroll => PageLayouts.vertical(sizes, params.margin),
      ReadingMode.singlePage => PageLayouts.horizontalPaged(sizes, params.margin),
    };
    return PdfPageLayout(pageLayouts: result.pageRects, documentSize: result.documentSize);
  }

  /// Top-level layout functions, one per mode.
  ///
  /// Identity matters: pdfrx re-lays-out when the function it is handed
  /// changes, so each mode must map to its own stable closure rather than a
  /// freshly allocated lambda on every build.
  static PdfPageLayoutFunction functionFor(ReadingMode mode) => switch (mode) {
    ReadingMode.continuousScroll => _layoutContinuous,
    ReadingMode.singlePage => _layoutSinglePage,
  };

  static PdfPageLayout _layoutContinuous(List<PdfPage> pages, PdfViewerParams params) =>
      layout(ReadingMode.continuousScroll, pages, params);

  static PdfPageLayout _layoutSinglePage(List<PdfPage> pages, PdfViewerParams params) =>
      layout(ReadingMode.singlePage, pages, params);
}
