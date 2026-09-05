@Tags(['pdfium'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/forms/model/pdf_form_field.dart';
import 'package:the_pdf_project/features/forms/services/pdf_form_service.dart';
import 'package:the_pdf_project/features/forms/ui/form_fill_screen.dart';
import 'package:the_pdf_project/features/pages/services/pdf_saver.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';

import '../../../support/pdfium_test_support.dart';

const _form = PdfFileSource(path: formFixture, displayName: 'form.pdf');
const _noForm = PdfFileSource(path: sampleFixture, displayName: 'sample.pdf');

/// Captures what would have been written instead of opening a save dialog.
class _RecordingSaver extends PdfSaver {
  _RecordingSaver();

  Uint8List? savedBytes;
  String? savedName;

  @override
  Future<Uri?> savePdf({required Uint8List bytes, required String suggestedName}) async {
    savedBytes = bytes;
    savedName = suggestedName;
    return Uri.file('/tmp/$suggestedName');
  }
}

void main() {
  setUpAll(initializePdfiumForTests);

  late _RecordingSaver saver;

  setUp(() => saver = _RecordingSaver());

  Future<Future<Uri?>> pushScreen(WidgetTester tester, {PdfSource source = _form}) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())),
    );
    final result = navigatorKey.currentState!.push<Uri>(
      MaterialPageRoute(builder: (context) => FormFillScreen(source: source, saver: saver)),
    );
    await pumpUntil(tester, find.byType(FormFillScreen));
    return result;
  }

  /// Reads the fields back out of whatever was saved.
  Future<List<PdfFormField>> savedFields(WidgetTester tester) async {
    final fields = await tester.runAsync(() async {
      final document = await PdfDocument.openData(
        saver.savedBytes!,
        sourceName: 'saved-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        return await const PdfFormService().readFields(document);
      } finally {
        await document.dispose();
      }
    });
    return fields!;
  }

  String valueOf(List<PdfFormField> fields, String name) =>
      fields.firstWhere((field) => field.name == name).value;

  documentTest('lists every field with the right control', (tester) async {
    await pushScreen(tester);
    await pumpUntil(tester, find.text('full_name'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 · 4 fields'), findsOneWidget);
    // A line to type on, a switch, a set of buttons, and a list to pick from.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNWidgets(2));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('0 of 4 filled in'), findsOneWidget);
  });

  documentTest('says so when a PDF has nothing to fill in', (tester) async {
    await pushScreen(tester, source: _noForm);
    await pumpUntil(tester, find.text('No form fields'));

    expect(find.byType(TextField), findsNothing);
  });

  documentTest('typing into a field counts towards the total', (tester) async {
    await pushScreen(tester);
    await pumpUntil(tester, find.text('full_name'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ada Lovelace');
    await tester.pumpAndSettle();

    expect(find.text('1 of 4 filled in'), findsOneWidget);
  });

  documentTest('saving writes every kind of answer into the PDF', (tester) async {
    final result = await pushScreen(tester);
    await pumpUntil(tester, find.text('full_name'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ada Lovelace');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pro'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japan').last);
    await tester.pumpAndSettle();

    expect(find.text('4 of 4 filled in'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save filled PDF'));
    await pumpUntilAbsent(tester, find.byType(FormFillScreen));
    await tester.pumpAndSettle();

    expect(saver.savedName, 'form-filled.pdf');
    final fields = await savedFields(tester);
    expect(valueOf(fields, 'full_name'), 'Ada Lovelace');
    expect(valueOf(fields, 'subscribe'), 'Yes');
    expect(valueOf(fields, 'plan'), 'Pro');
    expect(valueOf(fields, 'country'), 'Japan');
    expect(await result, Uri.file('/tmp/form-filled.pdf'));
  });

  documentTest('saving an untouched form is refused rather than written', (tester) async {
    await pushScreen(tester);
    await pumpUntil(tester, find.text('full_name'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save filled PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing has been filled in yet.'), findsOneWidget);
    expect(saver.savedBytes, isNull);
    expect(find.byType(FormFillScreen), findsOneWidget);
  });

  documentTest('a tick can be taken back before saving', (tester) async {
    await pushScreen(tester);
    await pumpUntil(tester, find.text('full_name'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 filled in'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('0 of 4 filled in'), findsOneWidget);
  });
}
