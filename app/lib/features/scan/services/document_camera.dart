import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Takes a photograph of a page.
///
/// Goes through the system camera rather than driving one in-app: the phone's
/// own camera already handles focus, exposure and the permission prompt, and
/// what the scanner needs from it is one sharp photograph. Straightening,
/// cropping and cleaning up happen afterwards, on code that can be tested
/// without a camera at all.
///
/// A seam, so the rest of the scanner can be exercised without hardware.
class DocumentCamera {
  const DocumentCamera({this.picker});

  /// Injected by tests; the real one is made on demand.
  @protected
  final ImagePicker? picker;

  ImagePicker get _images => picker ?? ImagePicker();

  /// Photographs a page. Returns null if the camera was closed without one.
  Future<Uint8List?> capture() => _read(ImageSource.camera);

  /// Takes a page from a picture already on the device — a photograph taken
  /// earlier, or one sent by someone else.
  Future<Uint8List?> chooseExisting() => _read(ImageSource.gallery);

  Future<Uint8List?> _read(ImageSource source) async {
    final file = await _images.pickImage(
      source: source,
      // Full resolution: small print is the whole point, and the processor
      // does its own sizing afterwards.
      imageQuality: 100,
    );
    return file?.readAsBytes();
  }
}
