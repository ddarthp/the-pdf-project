/// How pages are laid out in the viewer.
enum ReadingMode {
  /// Pages stacked vertically; the whole document scrolls as one strip.
  continuousScroll('Continuous scroll'),

  /// One page per screen, swiped horizontally, snapping to page boundaries.
  singlePage('Single page'),

  /// Facing pages side by side, spreads stacked vertically like the
  /// continuous mode. Pages pair up as (1,2), (3,4), … and an odd final page
  /// sits alone in the left column.
  twoPageSpread('Two-page spread');

  const ReadingMode(this.label);

  final String label;
}
