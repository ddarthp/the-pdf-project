/// How pages are laid out in the viewer.
enum ReadingMode {
  /// Pages stacked vertically; the whole document scrolls as one strip.
  continuousScroll('Continuous scroll'),

  /// One page per screen, swiped horizontally, snapping to page boundaries.
  singlePage('Single page');

  const ReadingMode(this.label);

  final String label;
}
