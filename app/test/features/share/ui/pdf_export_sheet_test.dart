import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/share/services/pdf_export_service.dart';
import 'package:the_pdf_project/features/share/ui/pdf_export_sheet.dart';

void main() {
  /// Opens the sheet and hands back what it returns.
  Future<Future<PdfExportDestination?>> showSheet(
    WidgetTester tester, {
    String fileName = 'report.pdf',
    String? note,
  }) async {
    late Future<PdfExportDestination?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showPdfExportSheet(context, fileName: fileName, note: note),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('offers all three destinations', (tester) async {
    await showSheet(tester);

    expect(find.text('Save to Files…'), findsOneWidget);
    expect(find.text('Share…'), findsOneWidget);
    expect(find.text('Print…'), findsOneWidget);
  });

  testWidgets('names the file it is about', (tester) async {
    await showSheet(tester, fileName: 'form-filled.pdf');

    expect(find.text('form-filled.pdf'), findsOneWidget);
  });

  testWidgets('shows a note about what is being sent', (tester) async {
    await showSheet(tester, note: '3 annotations');

    expect(find.text('3 annotations'), findsOneWidget);
  });

  for (final destination in PdfExportDestination.values) {
    testWidgets('choosing ${destination.label} returns it', (tester) async {
      final result = await showSheet(tester);

      await tester.tap(find.text(destination.label));
      await tester.pumpAndSettle();

      expect(await result, destination);
    });
  }

  testWidgets('dismissing it chooses nothing', (tester) async {
    final result = await showSheet(tester);

    Navigator.of(tester.element(find.text('Share…'))).pop();
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}
