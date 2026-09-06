import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/forms/logic/form_edits.dart';
import 'package:the_pdf_project/features/forms/model/pdf_form_field.dart';

PdfFormControl control(String exportValue, {int index = 0}) => PdfFormControl(
  annotationIndex: index,
  exportValue: exportValue,
  centerX: 0,
  centerY: 0,
);

PdfFormField field(
  String name,
  PdfFormFieldKind kind, {
  String value = '',
  bool isReadOnly = false,
  List<String> options = const [],
  List<PdfFormControl> controls = const [],
}) => PdfFormField(
  name: name,
  kind: kind,
  pageNumber: 1,
  value: value,
  isReadOnly: isReadOnly,
  options: options,
  controls: controls.isEmpty ? [control('')] : controls,
);

final text = field('name', PdfFormFieldKind.text, value: 'Ada');
final checkbox = field(
  'subscribe',
  PdfFormFieldKind.checkbox,
  value: PdfFormField.offValue,
  controls: [control('Off'), control('Yes', index: 1)],
);
final radio = field(
  'plan',
  PdfFormFieldKind.radio,
  value: PdfFormField.offValue,
  options: const ['Basic', 'Pro'],
  controls: [control('Basic'), control('Pro', index: 1)],
);
final combo = field(
  'country',
  PdfFormFieldKind.comboBox,
  options: const ['Germany', 'Japan'],
);
final readOnly = field('reference', PdfFormFieldKind.text, value: 'AB-12', isReadOnly: true);
final unsupported = field('signed_by', PdfFormFieldKind.unsupported);

void main() {
  final fields = [text, checkbox, radio, combo, readOnly, unsupported];

  group('changes', () {
    test('reports only the fields whose value actually differs', () {
      final changes = FormEdits.changes(fields, {
        'name': 'Ada',
        'plan': 'Pro',
        'country': 'Japan',
      });

      expect(changes, {'plan': 'Pro', 'country': 'Japan'});
    });

    test('ignores fields the reader never touched', () {
      expect(FormEdits.changes(fields, const {}), isEmpty);
    });

    test('never touches a read-only or unfillable field', () {
      final changes = FormEdits.changes(fields, {
        'reference': 'CD-34',
        'signed_by': 'someone',
      });

      expect(changes, isEmpty);
    });

    test('ignores a name that is not in the document', () {
      expect(FormEdits.changes(fields, {'ghost': 'value'}), isEmpty);
    });

    test('counts clearing a field as a change', () {
      expect(FormEdits.changes(fields, {'name': ''}), {'name': ''});
    });
  });

  group('checkboxValue', () {
    test('uses whatever the document calls the box being on', () {
      expect(FormEdits.checkboxValue(checkbox, isChecked: true), 'Yes');
    });

    test('falls back to Yes when the document does not say', () {
      final bare = field('bare', PdfFormFieldKind.checkbox, controls: [control('Off')]);

      expect(FormEdits.checkboxValue(bare, isChecked: true), 'Yes');
    });

    test('turning it off is always Off', () {
      expect(FormEdits.checkboxValue(checkbox, isChecked: false), PdfFormField.offValue);
    });
  });

  group('accepts', () {
    test('a text field takes anything', () {
      expect(FormEdits.accepts(text, 'anything at all'), isTrue);
      expect(FormEdits.accepts(text, ''), isTrue);
    });

    test('a dropdown only takes one of its own options', () {
      expect(FormEdits.accepts(combo, 'Japan'), isTrue);
      expect(FormEdits.accepts(combo, 'Atlantis'), isFalse);
    });

    test('a radio group only takes one of its buttons, or none', () {
      expect(FormEdits.accepts(radio, 'Pro'), isTrue);
      expect(FormEdits.accepts(radio, PdfFormField.offValue), isTrue);
      expect(FormEdits.accepts(radio, 'Enterprise'), isFalse);
    });

    test('nothing can be written to a field the app cannot fill', () {
      expect(FormEdits.accepts(unsupported, 'anything'), isFalse);
    });
  });

  group('initialValues', () {
    test('starts every fillable field from what it already holds', () {
      expect(FormEdits.initialValues(fields), {
        'name': 'Ada',
        'subscribe': PdfFormField.offValue,
        'plan': PdfFormField.offValue,
        'country': '',
      });
    });
  });

  group('progress', () {
    test('counts a field as filled once it holds something', () {
      final progress = FormEdits.progress(fields, {
        'name': 'Ada',
        'plan': 'Pro',
        'country': '',
        'subscribe': PdfFormField.offValue,
      });

      expect(progress.filled, 2);
      expect(progress.total, 4, reason: 'read-only and unfillable fields do not count');
    });

    test('starts at nothing filled for an empty form', () {
      final empty = [field('a', PdfFormFieldKind.text), field('b', PdfFormFieldKind.text)];

      expect(FormEdits.progress(empty, const {}).filled, 0);
      expect(FormEdits.progress(empty, const {}).total, 2);
    });
  });

  group('the field itself', () {
    test('knows whether it is ticked', () {
      expect(checkbox.isChecked, isFalse);
      expect(checkbox.copyWith(value: 'Yes').isChecked, isTrue);
    });

    test('finds the control that writes a value', () {
      expect(radio.controlFor('Pro')?.annotationIndex, 1);
      expect(radio.controlFor('Enterprise'), isNull);
    });

    test('is not editable when the document says read-only', () {
      expect(readOnly.isEditable, isFalse);
      expect(unsupported.isEditable, isFalse);
      expect(text.isEditable, isTrue);
    });
  });
}
