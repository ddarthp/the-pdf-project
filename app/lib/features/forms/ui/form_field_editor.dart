import 'package:flutter/material.dart';

import '../model/pdf_form_field.dart';

/// The right control for one form field.
///
/// A form is only as good as its editors, and each kind wants a different one:
/// a line to type on, a switch, a set of buttons where exactly one wins, a
/// list to pick from. Fields the document marks read-only, and kinds the app
/// cannot fill, are still shown — with their value — so nothing about the form
/// is silently hidden.
class FormFieldEditor extends StatelessWidget {
  const FormFieldEditor({
    required this.field,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final PdfFormField field;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!field.isEditable) return _ReadOnlyField(field: field, value: value);

    return switch (field.kind) {
      PdfFormFieldKind.text => _TextField(field: field, value: value, onChanged: onChanged),
      PdfFormFieldKind.checkbox => _Checkbox(field: field, value: value, onChanged: onChanged),
      PdfFormFieldKind.radio => _RadioGroup(field: field, value: value, onChanged: onChanged),
      PdfFormFieldKind.comboBox => _Dropdown(field: field, value: value, onChanged: onChanged),
      PdfFormFieldKind.unsupported => _ReadOnlyField(field: field, value: value),
    };
  }
}

class _TextField extends StatefulWidget {
  const _TextField({required this.field, required this.value, required this.onChanged});

  final PdfFormField field;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.field.name,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.field, required this.value, required this.onChanged});

  final PdfFormField field;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // A tick box's "on" is whatever the document calls it, usually `Yes`.
    final onValue = field.controls
        .map((control) => control.exportValue)
        .firstWhere((export) => export != PdfFormField.offValue, orElse: () => 'Yes');

    return SwitchListTile(
      title: Text(field.name),
      value: value != PdfFormField.offValue && value.isNotEmpty,
      onChanged: (isOn) => onChanged(isOn ? onValue : PdfFormField.offValue),
    );
  }
}

class _RadioGroup extends StatelessWidget {
  const _RadioGroup({required this.field, required this.value, required this.onChanged});

  final PdfFormField field;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(field.name, style: theme.textTheme.labelLarge),
          ),
          RadioGroup<String>(
            groupValue: value,
            onChanged: (chosen) => onChanged(chosen ?? PdfFormField.offValue),
            child: Column(
              children: [
                for (final option in field.options)
                  RadioListTile<String>(value: option, title: Text(option)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.field, required this.value, required this.onChanged});

  final PdfFormField field;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DropdownButtonFormField<String>(
        // A form can arrive holding something that is not on its own list; show
        // nothing chosen rather than crashing on it.
        initialValue: field.options.contains(value) ? value : null,
        decoration: InputDecoration(
          labelText: field.name,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in field.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (chosen) => onChanged(chosen ?? ''),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.field, required this.value});

  final PdfFormField field;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
      title: Text(field.name),
      subtitle: Text(
        value.isEmpty || value == PdfFormField.offValue
            ? '${field.kind.label} · empty'
            : value,
      ),
      enabled: false,
    );
  }
}
