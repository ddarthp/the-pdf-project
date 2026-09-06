import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import 'pdf_saver.dart';

/// Where a PDF can be sent once the app has produced it.
enum PdfExportDestination {
  /// The system save dialog — Files on iOS, the storage provider on Android.
  saveToFiles('Save to Files…', 'Choose where to keep it'),

  /// The system share sheet: mail, messaging, AirDrop, another app.
  share('Share…', 'Send it somewhere else'),

  /// The system print dialog.
  print('Print…', 'Send it to a printer');

  const PdfExportDestination(this.label, this.description);

  final String label;
  final String description;
}

/// What became of an export.
class PdfExportResult {
  const PdfExportResult({required this.destination, required this.completed, this.savedTo});

  final PdfExportDestination destination;

  /// False when the reader backed out of the system dialog.
  final bool completed;

  /// Where the file was written, for [PdfExportDestination.saveToFiles].
  final Uri? savedTo;

  /// What to tell the reader afterwards, or null when nothing needs saying —
  /// backing out of a share sheet is not news.
  String? get message {
    if (!completed) return null;
    return switch (destination) {
      PdfExportDestination.saveToFiles => 'Saved ${_fileName ?? 'the PDF'}',
      PdfExportDestination.share => 'Shared',
      PdfExportDestination.print => 'Sent to the printer',
    };
  }

  String? get _fileName {
    final segments = savedTo?.pathSegments;
    return segments == null || segments.isEmpty ? null : segments.last;
  }
}

/// Sends a finished PDF to the system: to a file, to the share sheet, or to a
/// printer.
///
/// All three hand the bytes straight to the platform. Nothing goes over a
/// network, and nothing is kept: the share sheet and the print dialog decide
/// where it ends up, and the app never sees the choice.
class PdfExportService {
  const PdfExportService({this.saver = const PdfSaver()});

  final PdfSaver saver;

  /// Carries out [destination].
  ///
  /// [originBounds] is where the share sheet should point from — on a tablet
  /// it opens as a popover anchored to whatever was tapped.
  Future<PdfExportResult> run(
    PdfExportDestination destination, {
    required Uint8List bytes,
    required String fileName,
    Rect? originBounds,
  }) => switch (destination) {
    PdfExportDestination.saveToFiles => saveToFiles(bytes: bytes, fileName: fileName),
    PdfExportDestination.share => share(
      bytes: bytes,
      fileName: fileName,
      originBounds: originBounds,
    ),
    PdfExportDestination.print => printPdf(bytes: bytes, fileName: fileName),
  };

  Future<PdfExportResult> saveToFiles({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final destination = await saver.savePdf(bytes: bytes, suggestedName: fileName);
    return PdfExportResult(
      destination: PdfExportDestination.saveToFiles,
      completed: destination != null,
      savedTo: destination,
    );
  }

  Future<PdfExportResult> share({
    required Uint8List bytes,
    required String fileName,
    Rect? originBounds,
  }) async {
    final shared = await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
      bounds: originBounds,
    );
    return PdfExportResult(destination: PdfExportDestination.share, completed: shared);
  }

  Future<PdfExportResult> printPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final printed = await Printing.layoutPdf(
      // The document is already laid out; the printer takes it as it is.
      onLayout: (format) => bytes,
      name: fileName,
    );
    return PdfExportResult(destination: PdfExportDestination.print, completed: printed);
  }
}
