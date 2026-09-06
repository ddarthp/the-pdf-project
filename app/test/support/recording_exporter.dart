import 'dart:typed_data';
import 'dart:ui';

import 'package:the_pdf_project/features/share/services/pdf_export_service.dart';

/// Records where a PDF was sent instead of opening a system dialog.
///
/// Every screen that produces a PDF hands it to [PdfExportService.run], so
/// overriding that one method covers saving, sharing and printing alike.
class RecordingExporter extends PdfExportService {
  RecordingExporter({this.completes = true});

  /// Whether the imagined system dialog is seen through rather than dismissed.
  final bool completes;

  PdfExportDestination? destination;
  Uint8List? bytes;
  String? fileName;
  Rect? originBounds;

  @override
  Future<PdfExportResult> run(
    PdfExportDestination destination, {
    required Uint8List bytes,
    required String fileName,
    Rect? originBounds,
  }) async {
    this.destination = destination;
    this.bytes = bytes;
    this.fileName = fileName;
    this.originBounds = originBounds;
    return PdfExportResult(
      destination: destination,
      completed: completes,
      savedTo: completes && destination == PdfExportDestination.saveToFiles
          ? Uri.file('/tmp/$fileName')
          : null,
    );
  }
}
