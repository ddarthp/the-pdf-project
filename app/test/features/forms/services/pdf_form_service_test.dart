@Tags(['pdfium'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/forms/model/pdf_form_field.dart';
import 'package:the_pdf_project/features/forms/services/pdf_form_service.dart';

import '../../../support/pdfium_test_support.dart';

/// End-to-end form filling: read the fields, write values, encode, then reopen
/// the result and read them back out.
void main() {
  const service = PdfFormService();

  setUpAll(initializePdfiumForTests);

  Future<PdfDocument> openFixture() async {
    final document = await PdfDocument.openFile(formFixture);
    addTearDown(document.dispose);
    return document;
  }

  Future<List<PdfFormField>> fieldsOf(Uint8List bytes) async {
    final document = await PdfDocument.openData(
      bytes,
      sourceName: 'filled-${bytes.length}-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(document.dispose);
    return service.readFields(document);
  }

  Future<List<PdfFormField>> fillAndRead(Map<String, String> values) async {
    final document = await openFixture();
    final fields = await service.readFields(document);
    final result = await service.fill(document, fields, values);
    expect(result.filled, values.length, reason: 'every field should have been written');
    return fieldsOf(result.bytes);
  }

  PdfFormField named(List<PdfFormField> fields, String name) =>
      fields.firstWhere((field) => field.name == name);

  group('reading', () {
    test('finds every field, once each, in page order', () async {
      final fields = await service.readFields(await openFixture());

      expect(fields.map((field) => field.name), [
        'full_name',
        'subscribe',
        'plan',
        'country',
      ]);
      expect(fields.map((field) => field.pageNumber), everyElement(1));
    });

    test('tells the kinds apart', () async {
      final fields = await service.readFields(await openFixture());

      expect(named(fields, 'full_name').kind, PdfFormFieldKind.text);
      expect(named(fields, 'subscribe').kind, PdfFormFieldKind.checkbox);
      expect(named(fields, 'plan').kind, PdfFormFieldKind.radio);
      expect(named(fields, 'country').kind, PdfFormFieldKind.comboBox);
    });

    test('gathers a radio group into one field with a button each', () async {
      final plan = named(await service.readFields(await openFixture()), 'plan');

      expect(plan.controls, hasLength(2));
      expect(plan.options, ['Basic', 'Pro']);
      // Each button knows where it is, which is how it gets clicked.
      expect(plan.controls.map((control) => control.centerX), [81, 141]);
    });

    test('reads the choices a dropdown offers', () async {
      final country = named(await service.readFields(await openFixture()), 'country');

      expect(country.options, ['United Kingdom', 'Germany', 'Japan']);
    });

    test('reports an empty form as starting empty', () async {
      final fields = await service.readFields(await openFixture());

      expect(named(fields, 'full_name').value, '');
      expect(named(fields, 'subscribe').value, PdfFormField.offValue);
      expect(named(fields, 'plan').value, PdfFormField.offValue);
      expect(named(fields, 'subscribe').isChecked, isFalse);
    });

    test('finds nothing in a PDF with no form', () async {
      final document = await PdfDocument.openFile(sampleFixture);
      addTearDown(document.dispose);

      expect(await service.readFields(document), isEmpty);
    });
  });

  group('filling', () {
    test('a text field keeps what was typed into it', () async {
      final fields = await fillAndRead({'full_name': 'Ada Lovelace'});

      expect(named(fields, 'full_name').value, 'Ada Lovelace');
    });

    test('a tick box can be turned on and off again', () async {
      final ticked = await fillAndRead({'subscribe': 'Yes'});
      expect(named(ticked, 'subscribe').value, 'Yes');
      expect(named(ticked, 'subscribe').isChecked, isTrue);

      // Starting from a ticked document, asking for Off unticks it.
      final document = await PdfDocument.openData(
        (await () async {
          final source = await openFixture();
          final fields = await service.readFields(source);
          return service.fill(source, fields, {'subscribe': 'Yes'});
        }())
            .bytes,
        sourceName: 'ticked-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(document.dispose);
      final fields = await service.readFields(document);
      final result = await service.fill(document, fields, {
        'subscribe': PdfFormField.offValue,
      });

      expect(named(await fieldsOf(result.bytes), 'subscribe').value, PdfFormField.offValue);
    });

    test('a radio group takes the button that was chosen', () async {
      final fields = await fillAndRead({'plan': 'Pro'});

      expect(named(fields, 'plan').value, 'Pro');
    });

    test('choosing the other radio button replaces the first', () async {
      final basic = await fillAndRead({'plan': 'Basic'});
      expect(named(basic, 'plan').value, 'Basic');

      final pro = await fillAndRead({'plan': 'Pro'});
      expect(named(pro, 'plan').value, 'Pro');
    });

    test('a dropdown takes one of its own options', () async {
      final fields = await fillAndRead({'country': 'Japan'});

      expect(named(fields, 'country').value, 'Japan');
    });

    test('a dropdown refuses a value it does not offer', () async {
      final document = await openFixture();
      final fields = await service.readFields(document);

      final result = await service.fill(document, fields, {'country': 'Atlantis'});

      expect(result.filled, 0);
      expect(result.skipped, 1);
      expect(named(await fieldsOf(result.bytes), 'country').value, '');
    });

    test('every kind of field can be filled in one pass', () async {
      final fields = await fillAndRead({
        'full_name': 'Ada Lovelace',
        'subscribe': 'Yes',
        'plan': 'Pro',
        'country': 'Germany',
      });

      expect(named(fields, 'full_name').value, 'Ada Lovelace');
      expect(named(fields, 'subscribe').value, 'Yes');
      expect(named(fields, 'plan').value, 'Pro');
      expect(named(fields, 'country').value, 'Germany');
    });

    test('a filled form still opens as a normal PDF', () async {
      final document = await openFixture();
      final fields = await service.readFields(document);
      final result = await service.fill(document, fields, {'full_name': 'Ada'});

      expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
      final reopened = await PdfDocument.openData(result.bytes, sourceName: 'still-a-pdf');
      addTearDown(reopened.dispose);
      expect(reopened.pages, hasLength(1));
      expect((await reopened.pages.first.loadStructuredText()).fullText, contains('Membership'));
    });
  });

  group('the filled values actually show on the page', () {
    Future<int> changedPixelCount(Uint8List bytes) async {
      final filled = await PdfDocument.openData(
        bytes,
        sourceName: 'render-${bytes.length}-${DateTime.now().microsecondsSinceEpoch}',
      );
      final blank = await PdfDocument.openFile(formFixture);
      try {
        final a = await filled.pages.first.render(width: 595, height: 842);
        final b = await blank.pages.first.render(width: 595, height: 842);
        try {
          var changed = 0;
          for (var i = 0; i < a!.pixels.length; i++) {
            if (a.pixels[i] != b!.pixels[i]) changed++;
          }
          return changed;
        } finally {
          a?.dispose();
          b?.dispose();
        }
      } finally {
        await filled.dispose();
        await blank.dispose();
      }
    }

    for (final entry in <String, Map<String, String>>{
      'a typed name': {'full_name': 'Ada Lovelace'},
      'a ticked box': {'subscribe': 'Yes'},
      'a chosen radio button': {'plan': 'Pro'},
      'a chosen dropdown option': {'country': 'Japan'},
    }.entries) {
      test('${entry.key} is drawn onto the page', () async {
        final document = await openFixture();
        final fields = await service.readFields(document);
        final result = await service.fill(document, fields, entry.value);

        expect(
          await changedPixelCount(result.bytes),
          greaterThan(100),
          reason: '${entry.key} should be visible',
        );
      });
    }
  });
}
