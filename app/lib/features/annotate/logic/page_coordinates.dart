import 'dart:math' as math;
import 'dart:ui';

/// Mapping between the viewer's document-layout space and normalised page
/// space, which is where annotations live.
///
/// This is the piece everything else leans on. pdfrx lays every page out as a
/// rectangle in one big document coordinate space — `PdfViewerController.layout`
/// for the rectangles, `localToDocument` for turning a touch into that space,
/// and the same rectangle again when painting. Storing annotation geometry as
/// a fraction of its page means zooming, switching reading mode and rotating
/// the view all change the page rectangle and nothing else: the same numbers
/// map onto whatever rectangle the page currently occupies.
///
/// Deliberately free of pdfrx types so the maths can be tested without a
/// PDFium document.
abstract final class PageCoordinates {
  /// Document point → fraction of [pageRect], origin at its top-left.
  ///
  /// Points outside the page produce values outside 0–1; use [clampToPage]
  /// when that must not happen.
  static Offset toNormalized(Offset documentPoint, Rect pageRect) {
    if (pageRect.width <= 0 || pageRect.height <= 0) return Offset.zero;
    return Offset(
      (documentPoint.dx - pageRect.left) / pageRect.width,
      (documentPoint.dy - pageRect.top) / pageRect.height,
    );
  }

  /// Fraction of [pageRect] → document point.
  static Offset toDocument(Offset normalized, Rect pageRect) => Offset(
    pageRect.left + normalized.dx * pageRect.width,
    pageRect.top + normalized.dy * pageRect.height,
  );

  static Rect rectToDocument(Rect normalized, Rect pageRect) => Rect.fromPoints(
    toDocument(normalized.topLeft, pageRect),
    toDocument(normalized.bottomRight, pageRect),
  );

  static Rect rectToNormalized(Rect documentRect, Rect pageRect) => Rect.fromPoints(
    toNormalized(documentRect.topLeft, pageRect),
    toNormalized(documentRect.bottomRight, pageRect),
  );

  /// Keeps a normalised point on its page.
  static Offset clampToPage(Offset normalized) =>
      Offset(normalized.dx.clamp(0.0, 1.0), normalized.dy.clamp(0.0, 1.0));

  /// Keeps a normalised rectangle on its page, preserving its size where it
  /// fits and trimming it where it does not.
  static Rect clampRectToPage(Rect normalized) => Rect.fromLTRB(
    normalized.left.clamp(0.0, 1.0),
    normalized.top.clamp(0.0, 1.0),
    normalized.right.clamp(0.0, 1.0),
    normalized.bottom.clamp(0.0, 1.0),
  );

  /// Which page a document point lands on, 1-based, or null if it fell in the
  /// gap between pages.
  static int? pageNumberAt(Offset documentPoint, List<Rect> pageLayouts) {
    for (var i = 0; i < pageLayouts.length; i++) {
      if (pageLayouts[i].contains(documentPoint)) return i + 1;
    }
    return null;
  }

  /// The page whose rectangle is nearest [documentPoint], for drags that stray
  /// into the margin. Returns null only for an empty layout.
  static int? nearestPageNumber(Offset documentPoint, List<Rect> pageLayouts) {
    if (pageLayouts.isEmpty) return null;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < pageLayouts.length; i++) {
      final rect = pageLayouts[i];
      final dx = math.max(0.0, math.max(rect.left - documentPoint.dx, documentPoint.dx - rect.right));
      final dy = math.max(0.0, math.max(rect.top - documentPoint.dy, documentPoint.dy - rect.bottom));
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best + 1;
  }

  /// A thickness in PDF points, in document-space units.
  ///
  /// [pageWidthInPoints] is the page's own width, so the ratio against the
  /// laid-out rectangle is exactly the current scale of the page.
  static double lengthToDocument(
    double points,
    Rect pageRect,
    double pageWidthInPoints,
  ) {
    if (pageWidthInPoints <= 0) return points;
    return points * pageRect.width / pageWidthInPoints;
  }
}
