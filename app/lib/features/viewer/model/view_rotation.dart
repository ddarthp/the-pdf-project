/// Non-destructive rotation of the whole view.
///
/// This rotates how the document is presented; it never changes the document.
/// Rotating pages in the file itself is a page operation, not a view setting.
enum ViewRotation {
  none(0, '0°'),
  clockwise90(1, '90°'),
  clockwise180(2, '180°'),
  clockwise270(3, '270°');

  const ViewRotation(this.quarterTurns, this.label);

  /// Clockwise quarter turns, matching `RotatedBox.quarterTurns`.
  final int quarterTurns;

  final String label;

  ViewRotation get next => ViewRotation.values[(index + 1) % ViewRotation.values.length];
}
