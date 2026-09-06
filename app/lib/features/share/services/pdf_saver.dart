import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Writes a generated PDF wherever the reader chooses, through the system
/// save dialog. Stays on-device: the bytes go straight to the file system (or
/// the Android storage provider), never over a network.
class PdfSaver {
  const PdfSaver();

  /// Returns where the file was written, or null if the reader cancelled.
  Future<Uri?> savePdf({required Uint8List bytes, required String suggestedName}) {
    return FilePicker.saveFile(
      dialogTitle: 'Save PDF',
      fileName: suggestedName,
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
  }
}
