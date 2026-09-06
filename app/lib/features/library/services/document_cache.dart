import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps a copy of documents that arrived without a file behind them.
///
/// Android's document picker often hands back a content URI and bytes rather
/// than a path, and that URI is no use once the pick is over. Writing the
/// bytes into the app's own directory is what lets such a document appear in
/// the recents list and still open a week later.
class DocumentCache {
  const DocumentCache({this.directoryProvider});

  /// Where copies are kept. Defaults to a `library` folder inside the app's
  /// documents directory; tests point it somewhere temporary.
  final Future<Directory> Function()? directoryProvider;

  Future<Directory> _directory() async {
    if (directoryProvider != null) return directoryProvider!();
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/library');
  }

  /// Writes [bytes] into the app's copy of the library and returns its path.
  ///
  /// The name is derived from [key], so opening the same document twice
  /// overwrites its copy rather than making another.
  Future<String> store({
    required String key,
    required Uint8List bytes,
    required String displayName,
  }) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final file = File('${directory.path}/${fileNameFor(key, displayName)}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Removes a copy the library no longer refers to.
  ///
  /// Only touches files inside the app's own directory: a document opened
  /// from somewhere else on the device is never deleted by dropping off the
  /// recents list.
  Future<void> discard(String path) async {
    try {
      final directory = await _directory();
      if (!path.startsWith(directory.path)) return;
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on Object catch (error) {
      debugPrint('Could not remove a cached copy: $error');
    }
  }

  /// A stable, safe file name for a document key.
  ///
  /// The key can be a whole content URI, so it is hashed rather than used as
  /// a name; the readable part is kept as a suffix so the folder can be made
  /// sense of by a person looking at it.
  static String fileNameFor(String key, String displayName) {
    final digest = md5.convert(key.codeUnits).toString().substring(0, 12);
    final readable = displayName
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final trimmed = readable.length > 40 ? readable.substring(0, 40) : readable;
    return '$digest${trimmed.isEmpty ? '' : '-$trimmed'}.pdf';
  }
}
