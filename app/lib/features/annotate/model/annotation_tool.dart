/// What a pointer does while annotation mode is on.
enum AnnotationTool {
  /// Pointers pass through to the viewer, so the reader can scroll and zoom
  /// without leaving annotation mode.
  pan('Pan'),

  /// Tap to select an annotation, drag to move it.
  select('Select'),

  ink('Draw'),
  highlight('Highlight'),
  rectangle('Rectangle'),
  ellipse('Ellipse'),
  line('Line'),
  arrow('Arrow'),
  textBox('Text box'),
  stickyNote('Sticky note'),
  signature('Signature'),

  /// Tap an annotation to remove it.
  eraser('Eraser');

  const AnnotationTool(this.label);

  final String label;

  /// Tools that let the viewer handle the pointer itself.
  bool get passesPointersThrough => this == AnnotationTool.pan;

  /// Tools that create something by dragging from one point to another.
  bool get isDragToDraw => const {
    AnnotationTool.highlight,
    AnnotationTool.rectangle,
    AnnotationTool.ellipse,
    AnnotationTool.line,
    AnnotationTool.arrow,
    AnnotationTool.textBox,
  }.contains(this);
}
