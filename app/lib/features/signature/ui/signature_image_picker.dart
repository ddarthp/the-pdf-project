import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

import '../logic/signature_geometry.dart';

/// A picture of a signature, ready to be placed.
class PickedSignatureImage {
  const PickedSignatureImage({required this.bytes, required this.aspectRatio});

  /// PNG data, re-encoded on the way in.
  final Uint8List bytes;

  final double aspectRatio;
}

/// Picks a photo or scan of a signature off the device.
///
/// The picture is re-encoded down to [maxWidth] before it is kept, because a
/// signature is stored alongside the annotations and a full camera photo would
/// dwarf everything else in there. Re-encoding to PNG also means one format to
/// decode later, whatever was picked.
class SignatureImagePicker {
  const SignatureImagePicker();

  /// The widest a stored signature picture gets, in pixels.
  static const maxWidth = 1200;

  /// Returns null when the reader cancels.
  Future<PickedSignatureImage?> pick() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choose a signature image',
      type: FileType.image,
    );
    if (picked == null) return null;
    return prepare(await picked.readAsBytes());
  }

  /// Decodes, shrinks and re-encodes picked bytes.
  Future<PickedSignatureImage> prepare(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: await _targetWidth(bytes),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('That image could not be read.');
      }
      return PickedSignatureImage(
        bytes: data.buffer.asUint8List(),
        aspectRatio: SignatureGeometry.clampAspectRatio(image.width / image.height),
      );
    } finally {
      image.dispose();
    }
  }

  /// Only shrinks: a small signature is left at its own size rather than
  /// being blown up.
  Future<int?> _targetWidth(Uint8List bytes) async {
    final descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(bytes),
    );
    final width = descriptor.width;
    descriptor.dispose();
    return width > maxWidth ? maxWidth : null;
  }
}
