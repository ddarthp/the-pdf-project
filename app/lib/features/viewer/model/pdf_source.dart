import 'dart:typed_data';

/// Where an opened PDF came from.
///
/// Android's storage-access framework hands back a content URI rather than a
/// filesystem path, so a picked document is either a real file or an in-memory
/// copy. Everything downstream works off this type instead of a raw path.
sealed class PdfSource {
  const PdfSource(this.displayName);

  /// File name shown in the app bar.
  final String displayName;

  /// Stable identity for the document, used to detect "a different PDF".
  String get key;
}

/// A PDF backed by a readable file on disk.
class PdfFileSource extends PdfSource {
  const PdfFileSource({required this.path, required String displayName}) : super(displayName);

  final String path;

  @override
  String get key => 'file:$path';
}

/// A PDF that had to be read into memory (e.g. an Android content URI).
class PdfDataSource extends PdfSource {
  const PdfDataSource({required this.bytes, required String displayName, required this.sourceId})
    : super(displayName);

  final Uint8List bytes;

  /// Unique id for the byte source; pdfrx uses it to key its document cache.
  final String sourceId;

  @override
  String get key => 'data:$sourceId';
}
