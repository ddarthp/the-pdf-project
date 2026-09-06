/// Pure page-navigation helpers, shared by the toolbar and the jump-to-page
/// dialog so both agree on what a valid page number is.
abstract final class PageNavigation {
  /// Clamps [pageNumber] into `1..pageCount`. Returns 1 for an empty document
  /// so callers never have to special-case it.
  static int clamp(int pageNumber, int pageCount) {
    if (pageCount <= 0) return 1;
    if (pageNumber < 1) return 1;
    if (pageNumber > pageCount) return pageCount;
    return pageNumber;
  }

  /// Parses user input from the jump-to-page field.
  ///
  /// Returns null when the text is not a page number within the document, so
  /// the dialog can show a validation message instead of silently clamping.
  static int? parsePageInput(String text, int pageCount) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) return null;
    if (pageCount <= 0) return null;
    if (parsed < 1 || parsed > pageCount) return null;
    return parsed;
  }

  static bool canGoBack(int pageNumber) => pageNumber > 1;

  static bool canGoForward(int pageNumber, int pageCount) => pageNumber < pageCount;
}
