import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../signature/model/signature_source.dart';
import '../model/annotation.dart';

/// Holds decoded pictures for image signatures.
///
/// Painting is synchronous but decoding is not, so the pictures are decoded
/// once, ahead of being drawn, and the cache tells its listeners when one
/// arrives. Until then the painter draws a placeholder rather than nothing.
class SignatureImageCache extends ChangeNotifier {
  final _images = <String, ui.Image>{};
  final _pending = <String>{};
  var _isDisposed = false;

  /// The picture for an annotation, or null while it is still being decoded.
  ui.Image? imageFor(String annotationId) => _images[annotationId];

  /// Starts decoding anything in [annotations] that is not cached yet, and
  /// drops pictures for annotations that have gone.
  void sync(Iterable<Annotation> annotations) {
    final wanted = <String, ImageSignature>{};
    for (final annotation in annotations) {
      if (annotation case SignatureAnnotation(:final source, :final id)
          when source is ImageSignature) {
        wanted[id] = source;
      }
    }

    for (final id in _images.keys.toList()) {
      if (wanted.containsKey(id)) continue;
      _images.remove(id)?.dispose();
    }

    for (final entry in wanted.entries) {
      if (_images.containsKey(entry.key) || !_pending.add(entry.key)) continue;
      unawaited(_decode(entry.key, entry.value));
    }
  }

  Future<void> _decode(String annotationId, ImageSignature signature) async {
    try {
      final codec = await ui.instantiateImageCodec(signature.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_isDisposed) {
        frame.image.dispose();
        return;
      }
      _images[annotationId] = frame.image;
      notifyListeners();
    } on Object catch (error) {
      debugPrint('Could not decode a signature image: $error');
    } finally {
      _pending.remove(annotationId);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
