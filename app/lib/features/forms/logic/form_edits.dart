import '../model/pdf_form_field.dart';

/// Works out what actually has to change in a document.
///
/// Kept pure so the rules — what counts as a change, what a tick means for a
/// given field, which values a field will accept — can be tested without a
/// PDF anywhere near them.
abstract final class FormEdits {
  /// The fields whose value differs from what the reader has typed or chosen.
  ///
  /// Only these get touched, which matters: filling a field means clicking or
  /// typing into it, and doing that to a field nobody edited would rewrite its
  /// appearance for no reason.
  static Map<String, String> changes(
    List<PdfFormField> fields,
    Map<String, String> edited,
  ) => {
    for (final field in fields)
      if (field.isEditable &&
          edited.containsKey(field.name) &&
          edited[field.name] != field.value)
        field.name: edited[field.name]!,
  };

  /// The value a field takes when a tick box is turned on or off.
  ///
  /// A tick box's "on" is whatever its own control calls it — usually `Yes`,
  /// but a document is free to name it anything.
  static String checkboxValue(PdfFormField field, {required bool isChecked}) {
    if (!isChecked) return PdfFormField.offValue;
    final on = field.controls
        .where((control) => control.exportValue != PdfFormField.offValue)
        .firstOrNull;
    return on?.exportValue ?? 'Yes';
  }

  /// Whether a field will accept [value].
  ///
  /// Text takes anything; the others only take something they can actually be
  /// set to, so a stale choice cannot be written into a document.
  static bool accepts(PdfFormField field, String value) => switch (field.kind) {
    PdfFormFieldKind.text => true,
    PdfFormFieldKind.comboBox => field.options.contains(value),
    PdfFormFieldKind.checkbox ||
    PdfFormFieldKind.radio => value == PdfFormField.offValue || field.controlFor(value) != null,
    PdfFormFieldKind.unsupported => false,
  };

  /// The starting point for the form editor: every fillable field mapped to
  /// what it already holds.
  static Map<String, String> initialValues(List<PdfFormField> fields) => {
    for (final field in fields)
      if (field.isEditable) field.name: field.value,
  };

  /// A short description of how much of the form has been filled in, for the
  /// editor's summary line.
  static ({int filled, int total}) progress(
    List<PdfFormField> fields,
    Map<String, String> values,
  ) {
    var filled = 0;
    var total = 0;
    for (final field in fields) {
      if (!field.isEditable) continue;
      total++;
      final value = values[field.name] ?? field.value;
      if (value.isNotEmpty && value != PdfFormField.offValue) filled++;
    }
    return (filled: filled, total: total);
  }
}
