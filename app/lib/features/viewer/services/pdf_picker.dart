import 'package:file_picker/file_picker.dart';

import '../model/pdf_source.dart';

/// Thrown when a picked document cannot be turned into a [PdfSource].
class PdfPickException implements Exception {
  const PdfPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opens the system document picker and returns the chosen PDF.
///
/// Everything stays on-device: the picker hands back either a local path or
/// bytes, and neither leaves the process.
class PdfPicker {
  const PdfPicker();

  /// Returns null when the user cancels the picker.
  Future<PdfSource?> pickPdf() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Open PDF',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked == null) return null;
    return toSource(picked);
  }

  /// Converts a picked file into a [PdfSource].
  ///
  /// On Android the picker usually returns a content URI with no filesystem
  /// path, so the document is read into memory instead.
  Future<PdfSource> toSource(PlatformFile picked) async {
    final path = picked.path;
    if (path != null) {
      return PdfFileSource(path: path, displayName: picked.name);
    }
    final bytes = await picked.readAsBytes();
    return PdfDataSource(
      bytes: bytes,
      displayName: picked.name,
      sourceId: picked.uri.toString(),
    );
  }
}
