import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/share/services/pdf_export_service.dart';
import 'package:the_pdf_project/features/share/services/pdf_saver.dart';

/// Stands in for the system save dialog.
class _FakeSaver extends PdfSaver {
  const _FakeSaver({this.destination, this.calls});

  final Uri? destination;
  final List<String>? calls;

  @override
  Future<Uri?> savePdf({required Uint8List bytes, required String suggestedName}) async {
    calls?.add(suggestedName);
    return destination;
  }
}

final _bytes = Uint8List.fromList('%PDF-1.7'.codeUnits);

void main() {
  group('saving to files', () {
    test('reports where the file went', () async {
      const service = PdfExportService(saver: _FakeSaver(destination: null));
      final saved = Uri.file('/tmp/report.pdf');

      final result = await const PdfExportService(saver: _FakeSaver())
          .saveToFiles(bytes: _bytes, fileName: 'report.pdf');
      final completed = await PdfExportService(saver: _FakeSaver(destination: saved))
          .saveToFiles(bytes: _bytes, fileName: 'report.pdf');

      expect(service.saver, isA<PdfSaver>());
      expect(result.completed, isFalse, reason: 'no destination means it was cancelled');
      expect(completed.completed, isTrue);
      expect(completed.savedTo, saved);
      expect(completed.destination, PdfExportDestination.saveToFiles);
    });

    test('passes the suggested name through', () async {
      final calls = <String>[];

      await PdfExportService(saver: _FakeSaver(calls: calls))
          .saveToFiles(bytes: _bytes, fileName: 'form-filled.pdf');

      expect(calls, ['form-filled.pdf']);
    });

    test('run dispatches to the same place', () async {
      final calls = <String>[];

      await PdfExportService(saver: _FakeSaver(calls: calls)).run(
        PdfExportDestination.saveToFiles,
        bytes: _bytes,
        fileName: 'report.pdf',
      );

      expect(calls, ['report.pdf']);
    });
  });

  group('what the reader is told afterwards', () {
    test('a saved file is named', () {
      const result = PdfExportResult(
        destination: PdfExportDestination.saveToFiles,
        completed: true,
        savedTo: null,
      );

      expect(
        PdfExportResult(
          destination: PdfExportDestination.saveToFiles,
          completed: true,
          savedTo: Uri.file('/tmp/report.pdf'),
        ).message,
        'Saved report.pdf',
      );
      // The system dialog does not always say where it put things.
      expect(result.message, 'Saved the PDF');
    });

    test('sharing and printing are acknowledged without a location', () {
      expect(
        const PdfExportResult(
          destination: PdfExportDestination.share,
          completed: true,
        ).message,
        'Shared',
      );
      expect(
        const PdfExportResult(
          destination: PdfExportDestination.print,
          completed: true,
        ).message,
        'Sent to the printer',
      );
    });

    test('backing out says nothing at all', () {
      for (final destination in PdfExportDestination.values) {
        expect(
          PdfExportResult(destination: destination, completed: false).message,
          isNull,
          reason: '$destination',
        );
      }
    });
  });

  test('every destination has something to show in the sheet', () {
    for (final destination in PdfExportDestination.values) {
      expect(destination.label, isNotEmpty);
      expect(destination.description, isNotEmpty);
    }
  });
}
