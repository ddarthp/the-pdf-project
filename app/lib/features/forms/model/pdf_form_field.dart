import 'package:flutter/foundation.dart';

/// The kinds of AcroForm field the app can fill.
///
/// Anything else in a document — push buttons, list boxes, signature fields —
/// is read and shown but not editable, so a form is never silently missing
/// parts of itself.
enum PdfFormFieldKind {
  text('Text'),
  checkbox('Checkbox'),
  radio('Radio buttons'),
  comboBox('Dropdown'),
  unsupported('Not editable');

  const PdfFormFieldKind(this.label);

  final String label;

  bool get isFillable => this != PdfFormFieldKind.unsupported;
}

/// One clickable control belonging to a field.
///
/// Most fields have exactly one. A radio group has several — one per button —
/// each with its own on-state name, which is what selecting it writes into the
/// field's value.
@immutable
class PdfFormControl {
  const PdfFormControl({
    required this.annotationIndex,
    required this.exportValue,
    required this.centerX,
    required this.centerY,
  });

  /// Position of the widget in its page's annotation list.
  final int annotationIndex;

  /// The value this control writes when it is turned on (`Yes`, `Pro`, …).
  final String exportValue;

  /// Middle of the widget in PDF page coordinates, which is where a click has
  /// to land to work it.
  final double centerX;
  final double centerY;

  @override
  bool operator ==(Object other) =>
      other is PdfFormControl &&
      other.annotationIndex == annotationIndex &&
      other.exportValue == exportValue &&
      other.centerX == centerX &&
      other.centerY == centerY;

  @override
  int get hashCode => Object.hash(annotationIndex, exportValue, centerX, centerY);
}

/// A field as it stands in the document.
@immutable
class PdfFormField {
  const PdfFormField({
    required this.name,
    required this.kind,
    required this.pageNumber,
    required this.value,
    required this.isReadOnly,
    required this.options,
    required this.controls,
  });

  /// The field's name in the document, which is also its identity: a radio
  /// group's buttons all share one.
  final String name;

  final PdfFormFieldKind kind;

  /// 1-based page the field's controls are on.
  final int pageNumber;

  /// What the field currently holds: the text, the chosen option, or the
  /// on-state name of whichever button is selected (`Off` when none is).
  final String value;

  final bool isReadOnly;

  /// The choices a dropdown offers, or the on-state names of a radio group.
  final List<String> options;

  final List<PdfFormControl> controls;

  /// The value that means "nothing chosen" for a tick-box or radio group.
  static const offValue = 'Off';

  bool get isChecked => value != offValue && value.isNotEmpty;

  /// Whether the reader can change this field.
  bool get isEditable => kind.isFillable && !isReadOnly;

  /// The control that writes [value] when clicked, or null if none does.
  PdfFormControl? controlFor(String value) =>
      controls.where((control) => control.exportValue == value).firstOrNull;

  PdfFormField copyWith({String? value}) => PdfFormField(
    name: name,
    kind: kind,
    pageNumber: pageNumber,
    value: value ?? this.value,
    isReadOnly: isReadOnly,
    options: options,
    controls: controls,
  );

  @override
  String toString() => 'PdfFormField($name, $kind, page $pageNumber, value: "$value")';
}
