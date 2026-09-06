import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

import '../model/pdf_form_field.dart';

/// Reads and fills AcroForm fields, through PDFium's form API.
///
/// pdfrx renders form fields but cannot fill them, so this drops to the C API
/// via `PdfDocument.useNativeDocumentHandle`. Filling goes through the same
/// calls a real form filler makes — focus a field and type into it, click a
/// tick box, choose an option — rather than writing values into the document
/// by hand, so PDFium redraws each field itself and the result looks the way
/// the document's own author meant it to.
class PdfFormService {
  const PdfFormService();

  /// Every field in the document, grouped so a radio group is one field with
  /// several buttons rather than several fields sharing a name.
  Future<List<PdfFormField>> readFields(PdfDocument document) async {
    final pageCount = document.pages.length;
    return document.useNativeDocumentHandle((handle) {
      final pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
      final nativeDocument = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);

      return _withForm(pdfium, nativeDocument, (form) {
        final fields = <PdfFormField>[];
        for (var pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
          fields.addAll(_readPage(pdfium, nativeDocument, form, pageNumber));
        }
        return fields;
      });
    });
  }

  /// Applies [values] — field name to new value — and encodes the result.
  ///
  /// [document] is changed in place, so it should be a copy opened for the
  /// filling rather than the one the viewer is showing. Returns how many
  /// fields were actually written.
  Future<PdfFormFillResult> fill(
    PdfDocument document,
    List<PdfFormField> fields,
    Map<String, String> values,
  ) async {
    final byPage = <int, List<PdfFormField>>{};
    for (final field in fields) {
      if (!values.containsKey(field.name)) continue;
      byPage.putIfAbsent(field.pageNumber, () => []).add(field);
    }

    final filled = await document.useNativeDocumentHandle((handle) {
      final pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
      final nativeDocument = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);

      return _withForm(pdfium, nativeDocument, (form) {
        var filled = 0;
        for (final entry in byPage.entries) {
          final page = pdfium.FPDF_LoadPage(nativeDocument, entry.key - 1);
          if (page == nullptr) continue;
          pdfium.FORM_OnAfterLoadPage(page, form);
          try {
            for (final field in entry.value) {
              if (_fillField(pdfium, form, page, field, values[field.name]!)) filled++;
            }
          } finally {
            pdfium.FORM_ForceToKillFocus(form);
            pdfium.FORM_OnBeforeClosePage(page, form);
            pdfium.FPDF_ClosePage(page);
          }
        }
        return filled;
      });
    });

    return PdfFormFillResult(
      bytes: await document.encodePdf(),
      filled: filled,
      requested: values.length,
    );
  }

  // --- reading -------------------------------------------------------------

  List<PdfFormField> _readPage(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_DOCUMENT document,
    pdfium_bindings.FPDF_FORMHANDLE form,
    int pageNumber,
  ) {
    final page = pdfium.FPDF_LoadPage(document, pageNumber - 1);
    if (page == nullptr) return const [];
    pdfium.FORM_OnAfterLoadPage(page, form);
    try {
      // Radio buttons arrive one widget at a time; they are gathered under the
      // field name they share.
      final byName = <String, PdfFormField>{};
      final order = <String>[];

      using((arena) {
        for (var index = 0; index < pdfium.FPDFPage_GetAnnotCount(page); index++) {
          final annot = pdfium.FPDFPage_GetAnnot(page, index);
          if (annot == nullptr) continue;
          try {
            if (pdfium.FPDFAnnot_GetSubtype(annot) != pdfium_bindings.FPDF_ANNOT_WIDGET) continue;
            final kind = _kindOf(pdfium.FPDFAnnot_GetFormFieldType(form, annot));
            final name = _readString(
              pdfium,
              arena,
              (buffer, length) =>
                  pdfium.FPDFAnnot_GetFormFieldName(form, annot, buffer, length),
            );
            if (name.isEmpty) continue;

            final control = PdfFormControl(
              annotationIndex: index,
              exportValue: _readString(
                pdfium,
                arena,
                (buffer, length) =>
                    pdfium.FPDFAnnot_GetFormFieldExportValue(form, annot, buffer, length),
              ),
              centerX: _centerOf(pdfium, arena, annot).$1,
              centerY: _centerOf(pdfium, arena, annot).$2,
            );

            final existing = byName[name];
            if (existing != null) {
              byName[name] = PdfFormField(
                name: existing.name,
                kind: existing.kind,
                pageNumber: existing.pageNumber,
                value: existing.value,
                isReadOnly: existing.isReadOnly,
                options: existing.options,
                controls: [...existing.controls, control],
              );
              continue;
            }

            order.add(name);
            byName[name] = PdfFormField(
              name: name,
              kind: kind,
              pageNumber: pageNumber,
              value: _readString(
                pdfium,
                arena,
                (buffer, length) =>
                    pdfium.FPDFAnnot_GetFormFieldValue(form, annot, buffer, length),
              ),
              // Bit 1 of the field flags is the read-only flag.
              isReadOnly: pdfium.FPDFAnnot_GetFormFieldFlags(form, annot) & 1 != 0,
              options: _readOptions(pdfium, arena, form, annot),
              controls: [control],
            );
          } finally {
            pdfium.FPDFPage_CloseAnnot(annot);
          }
        }
      });

      return [
        for (final name in order)
          if (byName[name] case final field?) _withRadioOptions(field),
      ];
    } finally {
      pdfium.FORM_OnBeforeClosePage(page, form);
      pdfium.FPDF_ClosePage(page);
    }
  }

  /// A radio group's choices are the on-state names of its buttons, which are
  /// only known once every button has been seen.
  static PdfFormField _withRadioOptions(PdfFormField field) {
    if (field.kind != PdfFormFieldKind.radio) return field;
    return PdfFormField(
      name: field.name,
      kind: field.kind,
      pageNumber: field.pageNumber,
      value: field.value,
      isReadOnly: field.isReadOnly,
      options: [
        for (final control in field.controls)
          if (control.exportValue.isNotEmpty && control.exportValue != PdfFormField.offValue)
            control.exportValue,
      ],
      controls: field.controls,
    );
  }

  List<String> _readOptions(
    pdfium_bindings.PDFium pdfium,
    Arena arena,
    pdfium_bindings.FPDF_FORMHANDLE form,
    pdfium_bindings.FPDF_ANNOTATION annot,
  ) {
    final count = pdfium.FPDFAnnot_GetOptionCount(form, annot);
    if (count <= 0) return const [];
    return [
      for (var i = 0; i < count; i++)
        _readString(
          pdfium,
          arena,
          (buffer, length) => pdfium.FPDFAnnot_GetOptionLabel(form, annot, i, buffer, length),
        ),
    ];
  }

  static (double, double) _centerOf(
    pdfium_bindings.PDFium pdfium,
    Arena arena,
    pdfium_bindings.FPDF_ANNOTATION annot,
  ) {
    final rect = arena<pdfium_bindings.FS_RECTF>();
    if (pdfium.FPDFAnnot_GetRect(annot, rect) == 0) return (0, 0);
    return ((rect.ref.left + rect.ref.right) / 2, (rect.ref.top + rect.ref.bottom) / 2);
  }

  static PdfFormFieldKind _kindOf(int formFieldType) => switch (formFieldType) {
    pdfium_bindings.FPDF_FORMFIELD_TEXTFIELD => PdfFormFieldKind.text,
    pdfium_bindings.FPDF_FORMFIELD_CHECKBOX => PdfFormFieldKind.checkbox,
    pdfium_bindings.FPDF_FORMFIELD_RADIOBUTTON => PdfFormFieldKind.radio,
    pdfium_bindings.FPDF_FORMFIELD_COMBOBOX => PdfFormFieldKind.comboBox,
    _ => PdfFormFieldKind.unsupported,
  };

  // --- filling -------------------------------------------------------------

  /// Works one field, the way a person would.
  ///
  /// Focus is dropped after every field without exception: PDFium keeps an
  /// edit in the focused widget until focus moves on, and moving it by
  /// starting on the *next* field loses the previous one.
  bool _fillField(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_FORMHANDLE form,
    pdfium_bindings.FPDF_PAGE page,
    PdfFormField field,
    String value,
  ) {
    try {
      return switch (field.kind) {
        PdfFormFieldKind.text => _typeInto(pdfium, form, page, field, value),
        PdfFormFieldKind.comboBox => _chooseOption(pdfium, form, page, field, value),
        PdfFormFieldKind.checkbox || PdfFormFieldKind.radio => _click(pdfium, form, page, field, value),
        PdfFormFieldKind.unsupported => false,
      };
    } finally {
      pdfium.FORM_ForceToKillFocus(form);
    }
  }

  bool _typeInto(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_FORMHANDLE form,
    pdfium_bindings.FPDF_PAGE page,
    PdfFormField field,
    String value,
  ) {
    final control = field.controls.firstOrNull;
    if (control == null) return false;
    final annot = pdfium.FPDFPage_GetAnnot(page, control.annotationIndex);
    if (annot == nullptr) return false;
    try {
      if (pdfium.FORM_SetFocusedAnnot(form, annot) == 0) return false;
      return using((arena) {
        // Selecting everything first means this replaces the field's contents
        // rather than appending to them.
        pdfium.FORM_SelectAllText(form, page);
        pdfium.FORM_ReplaceSelection(form, page, _toUtf16(arena, value));
        return true;
      });
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  bool _chooseOption(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_FORMHANDLE form,
    pdfium_bindings.FPDF_PAGE page,
    PdfFormField field,
    String value,
  ) {
    final index = field.options.indexOf(value);
    final control = field.controls.firstOrNull;
    if (index < 0 || control == null) return false;
    final annot = pdfium.FPDFPage_GetAnnot(page, control.annotationIndex);
    if (annot == nullptr) return false;
    try {
      if (pdfium.FORM_SetFocusedAnnot(form, annot) == 0) return false;
      return pdfium.FORM_SetIndexSelected(form, page, index, 1) != 0;
    } finally {
      pdfium.FPDFPage_CloseAnnot(annot);
    }
  }

  /// Tick boxes and radio buttons are worked by clicking them, which is the
  /// only way PDFium offers — so turning one off means clicking it only if it
  /// is currently on.
  bool _click(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_FORMHANDLE form,
    pdfium_bindings.FPDF_PAGE page,
    PdfFormField field,
    String value,
  ) {
    final control = value == PdfFormField.offValue
        ? field.controlFor(field.value)
        : field.controlFor(value);
    if (control == null) return false;

    pdfium.FORM_OnLButtonDown(form, page, 0, control.centerX, control.centerY);
    pdfium.FORM_OnLButtonUp(form, page, 0, control.centerX, control.centerY);
    return true;
  }

  // --- plumbing ------------------------------------------------------------

  /// Runs [body] with a form environment of its own.
  ///
  /// pdfrx keeps one for its own rendering but does not expose it, so this
  /// makes and disposes another. PDFium is happy with two over one document;
  /// both read and write the same field dictionaries.
  T _withForm<T>(
    pdfium_bindings.PDFium pdfium,
    pdfium_bindings.FPDF_DOCUMENT document,
    T Function(pdfium_bindings.FPDF_FORMHANDLE form) body,
  ) {
    final formInfo = calloc<pdfium_bindings.FPDF_FORMFILLINFO>();
    // Version 1 with no callbacks: PDFium checks each one before calling it,
    // and nothing here needs to be told about redraws.
    formInfo.ref.version = 1;
    final form = pdfium.FPDFDOC_InitFormFillEnvironment(document, formInfo);
    if (form == nullptr) {
      calloc.free(formInfo);
      throw StateError('This PDF has no fillable form.');
    }
    try {
      return body(form);
    } finally {
      pdfium.FPDFDOC_ExitFormFillEnvironment(form);
      calloc.free(formInfo);
    }
  }

  static String _readString(
    pdfium_bindings.PDFium pdfium,
    Arena arena,
    int Function(Pointer<UnsignedShort> buffer, int length) read,
  ) {
    final length = read(nullptr, 0);
    // Two bytes is an empty string plus its terminator.
    if (length <= 2) return '';
    final buffer = arena<UnsignedShort>(length ~/ 2);
    read(buffer, length);
    final codes = <int>[];
    for (var i = 0; i < length ~/ 2; i++) {
      if (buffer[i] == 0) break;
      codes.add(buffer[i]);
    }
    return String.fromCharCodes(codes);
  }

  static Pointer<UnsignedShort> _toUtf16(Arena arena, String value) {
    final units = value.codeUnits;
    final buffer = arena<UnsignedShort>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      buffer[i] = units[i];
    }
    buffer[units.length] = 0;
    return buffer;
  }
}

/// The outcome of filling a form.
class PdfFormFillResult {
  const PdfFormFillResult({
    required this.bytes,
    required this.filled,
    required this.requested,
  });

  /// The encoded PDF.
  final Uint8List bytes;

  /// How many fields were written.
  final int filled;

  /// How many were asked for.
  final int requested;

  int get skipped => requested - filled;
}
