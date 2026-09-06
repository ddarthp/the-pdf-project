import 'dart:ui';

/// Turns a dragged rectangle into highlight bands that follow the text.
///
/// A highlight drawn as a plain rectangle looks wrong the moment it crosses a
/// line break. Given the character rectangles pdfrx reads off the page, the
/// characters the drag actually covers are grouped into lines and each line
/// becomes one band — so the highlight hugs the text the way it does in a
/// paper book.
///
/// Everything here is in normalised page space and free of pdfrx types.
abstract final class TextHighlight {
  /// Characters count as covered when the drag overlaps their rectangle by
  /// more than this fraction of its area.
  static const _minimumOverlap = 0.15;

  /// Two characters are on the same line when their vertical centres are
  /// within this fraction of the taller one's height.
  static const _lineTolerance = 0.6;

  /// Bands covering the characters [selection] runs across, ordered down the
  /// page. Returns an empty list when the drag caught no text — callers fall
  /// back to the raw rectangle.
  static List<Rect> bandsFor(List<Rect> charRects, Rect selection) {
    final normalizedSelection = _normalize(selection);
    final covered = [
      for (final rect in charRects)
        if (_isCovered(rect, normalizedSelection)) rect,
    ];
    if (covered.isEmpty) return const [];

    final lines = _groupIntoLines(covered);
    return [
      for (final line in lines) line.reduce((a, b) => a.expandToInclude(b)),
    ];
  }

  /// Indices into [charRects] of the characters [selection] covers, so the
  /// highlighted text can be read back out of the page's full text.
  static List<int> coveredCharIndices(List<Rect> charRects, Rect selection) {
    final normalizedSelection = _normalize(selection);
    return [
      for (var i = 0; i < charRects.length; i++)
        if (_isCovered(charRects[i], normalizedSelection)) i,
    ];
  }

  static bool _isCovered(Rect charRect, Rect selection) {
    if (charRect.isEmpty) return false;
    final overlap = charRect.intersect(selection);
    if (overlap.width <= 0 || overlap.height <= 0) return false;
    final area = charRect.width * charRect.height;
    if (area <= 0) return false;
    return (overlap.width * overlap.height) / area >= _minimumOverlap;
  }

  /// Groups characters into lines by vertical position, each line ordered
  /// left to right.
  static List<List<Rect>> _groupIntoLines(List<Rect> rects) {
    final sorted = [...rects]..sort((a, b) => a.center.dy.compareTo(b.center.dy));

    final lines = <List<Rect>>[];
    for (final rect in sorted) {
      final current = lines.isEmpty ? null : lines.last;
      if (current != null && _isSameLine(current.last, rect)) {
        current.add(rect);
      } else {
        lines.add([rect]);
      }
    }
    for (final line in lines) {
      line.sort((a, b) => a.left.compareTo(b.left));
    }
    return lines;
  }

  static bool _isSameLine(Rect a, Rect b) {
    final tallest = a.height > b.height ? a.height : b.height;
    if (tallest <= 0) return false;
    return (a.center.dy - b.center.dy).abs() <= tallest * _lineTolerance;
  }

  /// A drag can run in any direction; bands are computed from the rectangle
  /// it covers.
  static Rect _normalize(Rect rect) => Rect.fromLTRB(
    rect.left < rect.right ? rect.left : rect.right,
    rect.top < rect.bottom ? rect.top : rect.bottom,
    rect.left < rect.right ? rect.right : rect.left,
    rect.top < rect.bottom ? rect.bottom : rect.top,
  );
}
