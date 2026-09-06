import 'package:flutter/foundation.dart';

/// An image chosen to become a page.
@immutable
class PickedImage {
  const PickedImage({
    required this.id,
    required this.displayName,
    required this.bytes,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  /// Unique within one conversion, so the list can be reordered by key.
  final String id;

  final String displayName;

  /// Encoded image data, in a format a PDF can carry directly.
  final Uint8List bytes;

  final int pixelWidth;
  final int pixelHeight;

  double get aspectRatio => pixelHeight <= 0 ? 1 : pixelWidth / pixelHeight;

  @override
  String toString() => 'PickedImage($displayName, ${pixelWidth}x$pixelHeight)';
}
