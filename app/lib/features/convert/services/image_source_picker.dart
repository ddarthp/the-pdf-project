import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../model/picked_image.dart';

/// Chooses pictures from the device and gets them ready to become pages.
///
/// A PDF can carry JPEG and PNG data as it stands, so those are passed through
/// untouched — re-encoding a photograph would make the document several times
/// larger for nothing. Anything else the device can show but a PDF cannot
/// carry, HEIC above all, is converted on the way in.
class ImageSourcePicker {
  const ImageSourcePicker();

  /// The widest an image is kept at when it has to be converted, in pixels.
  static const maxConvertedWidth = 2400;

  /// Opens the picker. Returns an empty list when the reader cancels.
  Future<List<PickedImage>> pickImages({int startingId = 0}) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose images',
      type: FileType.image,
    );

    final images = <PickedImage>[];
    for (final file in picked) {
      try {
        images.add(
          await prepare(
            bytes: await file.readAsBytes(),
            displayName: file.name,
            id: 'image-${startingId + images.length}-${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
      } on Object catch (error) {
        debugPrint('Skipping an image that could not be read: $error');
      }
    }
    return images;
  }

  /// Measures an image and, if a PDF cannot carry it as it stands, converts it.
  Future<PickedImage> prepare({
    required Uint8List bytes,
    required String displayName,
    required String id,
  }) async {
    if (isEmbeddable(bytes)) {
      final size = await _measure(bytes);
      return PickedImage(
        id: id,
        displayName: displayName,
        bytes: bytes,
        pixelWidth: size.$1,
        pixelHeight: size.$2,
      );
    }

    final converted = await _toPng(bytes);
    return PickedImage(
      id: id,
      displayName: displayName,
      bytes: converted.$1,
      pixelWidth: converted.$2,
      pixelHeight: converted.$3,
    );
  }

  /// Whether a PDF can carry these bytes without re-encoding them.
  ///
  /// Recognised by their leading bytes rather than by file extension, which a
  /// picker is under no obligation to get right.
  static bool isEmbeddable(Uint8List bytes) => isJpeg(bytes) || isPng(bytes);

  static bool isJpeg(Uint8List bytes) =>
      bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

  static bool isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;

  Future<(int, int)> _measure(Uint8List bytes) async {
    final descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(bytes),
    );
    final size = (descriptor.width, descriptor.height);
    descriptor.dispose();
    return size;
  }

  Future<(Uint8List, int, int)> _toPng(Uint8List bytes) async {
    final size = await _measure(bytes);
    final codec = await ui.instantiateImageCodec(
      bytes,
      // Only ever shrinks: a small picture is left at its own size.
      targetWidth: size.$1 > maxConvertedWidth ? maxConvertedWidth : null,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('That image could not be read.');
      return (data.buffer.asUint8List(), image.width, image.height);
    } finally {
      image.dispose();
    }
  }
}
