import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/pdf_source.dart';

/// PDFs handed to the app by another app — "Open with The PDF Project" from a
/// file manager or a mail attachment, and documents shared into it.
///
/// Both platforms copy the document into the app's own cache before telling
/// Dart about it, so what arrives here is always a path that can simply be
/// opened. That copy is not a convenience: an Android `content://` URI has no
/// file behind it, and an iOS security-scoped URL stops being readable the
/// moment the platform stops granting access — neither survives the trip into
/// the viewer, so neither is allowed to make it that far.
///
/// The channels are injectable, which is what lets the whole service be
/// driven from a unit test with no device attached.
class IncomingDocuments {
  IncomingDocuments({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel(methodChannelName),
      _events = events ?? const EventChannel(eventChannelName);

  /// Where the launch document is asked for, once.
  static const methodChannelName = 'com.softmindai.the_pdf_project/incoming_documents';

  /// Where documents that arrive later are announced.
  static const eventChannelName = 'com.softmindai.the_pdf_project/incoming_documents/events';

  final MethodChannel _channel;
  final EventChannel _events;

  Stream<List<PdfFileSource>>? _documents;

  /// The documents the app was launched with, in the order they were shared.
  ///
  /// Empty when the app was opened from its own icon. Taking them clears the
  /// platform's copy, so the launch document opens once and a later rebuild
  /// does not reopen it over whatever the reader has moved on to.
  ///
  /// Receiving a document is a favour the OS is doing the reader, never the
  /// only way in, so a platform that cannot answer degrades to "nothing
  /// arrived" rather than failing the launch.
  Future<List<PdfFileSource>> takeInitialDocuments() async {
    try {
      return parse(await _channel.invokeMethod<Object?>('takeInitialDocuments'));
    } on Object catch (error) {
      debugPrint('Could not read the document the app was opened with: $error');
      return const [];
    }
  }

  /// Documents that arrive while the app is already running.
  ///
  /// The Android activity is `singleTop`, so a second "Open with" reuses the
  /// running instance instead of launching a new one, and iOS hands a second
  /// document to the live scene. Either way there is no new launch to read,
  /// and this is the only place such a document shows up.
  ///
  /// A batch shared in one go arrives as one event. Events that carry nothing
  /// readable are dropped, and a failure on the platform side is reported and
  /// swallowed so the next document still gets through.
  Stream<List<PdfFileSource>> get documents {
    return _documents ??= _events
        .receiveBroadcastStream()
        .map(parse)
        .handleError((Object error) {
          debugPrint('Could not read an incoming document: $error');
        })
        .where((documents) => documents.isNotEmpty)
        .asBroadcastStream();
  }

  /// Reads a platform payload into sources the viewer already understands.
  ///
  /// Anything unreadable is skipped rather than thrown, so one malformed
  /// entry cannot lose the documents shared alongside it.
  @visibleForTesting
  static List<PdfFileSource> parse(Object? payload) {
    if (payload is! List) return const [];
    final documents = <PdfFileSource>[];
    for (final entry in payload) {
      if (entry is! Map) continue;
      final path = entry['path'];
      if (path is! String || path.isEmpty) continue;
      final name = entry['name'];
      documents.add(
        PdfFileSource(
          path: path,
          displayName: name is String && name.isNotEmpty ? name : _fileNameOf(path),
        ),
      );
    }
    return documents;
  }

  static String _fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;
}
