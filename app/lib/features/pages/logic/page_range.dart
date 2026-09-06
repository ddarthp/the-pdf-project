/// Parsing and formatting of page-range text like `1-3, 5, 9-`.
///
/// Used by "select a range" in the page organiser, which is how split and
/// extract-by-range are driven.
abstract final class PageRange {
  /// Parses [text] against a document of [pageCount] pages.
  ///
  /// Accepts comma- or space-separated terms: a single page (`5`), a closed
  /// range (`2-7`), an open range to the end (`9-`) or from the start (`-4`).
  /// Ranges given backwards (`7-2`) are read as written. Returns sorted,
  /// de-duplicated 1-based page numbers, or null if the text is not a valid
  /// range for this document — callers show a validation message rather than
  /// silently correcting it.
  static List<int>? parse(String text, int pageCount) {
    if (pageCount <= 0) return null;
    final terms = text.split(RegExp(r'[,\s]+')).where((t) => t.isNotEmpty);
    if (terms.isEmpty) return null;

    final pages = <int>{};
    for (final term in terms) {
      final range = _parseTerm(term, pageCount);
      if (range == null) return null;
      pages.addAll(range);
    }
    if (pages.isEmpty) return null;
    return pages.toList()..sort();
  }

  static Iterable<int>? _parseTerm(String term, int pageCount) {
    final dash = term.indexOf('-');
    if (dash < 0) {
      final page = _parsePage(term, pageCount);
      return page == null ? null : [page];
    }

    final startText = term.substring(0, dash);
    final endText = term.substring(dash + 1);
    // A bare "-" is not a range.
    if (startText.isEmpty && endText.isEmpty) return null;

    final start = startText.isEmpty ? 1 : _parsePage(startText, pageCount);
    final end = endText.isEmpty ? pageCount : _parsePage(endText, pageCount);
    if (start == null || end == null) return null;

    final from = start <= end ? start : end;
    final to = start <= end ? end : start;
    return [for (var page = from; page <= to; page++) page];
  }

  static int? _parsePage(String text, int pageCount) {
    final page = int.tryParse(text.trim());
    if (page == null || page < 1 || page > pageCount) return null;
    return page;
  }

  /// Renders page numbers back into compact range text (`1-3, 7`).
  static String format(Iterable<int> pageNumbers) {
    final sorted = pageNumbers.toSet().toList()..sort();
    if (sorted.isEmpty) return '';

    final parts = <String>[];
    var start = sorted.first;
    var previous = start;
    for (final page in sorted.skip(1)) {
      if (page == previous + 1) {
        previous = page;
        continue;
      }
      parts.add(start == previous ? '$start' : '$start-$previous');
      start = page;
      previous = page;
    }
    parts.add(start == previous ? '$start' : '$start-$previous');
    return parts.join(', ');
  }
}
