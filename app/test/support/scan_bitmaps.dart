import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Makes synthetic photographs to detect pages in, so the scanner's maths can
/// be tested without a camera.
///
/// Raw RGBA, the same form the real pipeline works in.
class TestBitmap {
  TestBitmap(this.width, this.height, {int background = 40})
    : pixels = Uint8List(width * height * 4) {
    for (var i = 0; i < width * height; i++) {
      pixels[i * 4] = background;
      pixels[i * 4 + 1] = background;
      pixels[i * 4 + 2] = background;
      pixels[i * 4 + 3] = 255;
    }
  }

  final int width;
  final int height;
  final Uint8List pixels;

  void set(int x, int y, int value) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final i = (y * width + x) * 4;
    pixels[i] = value;
    pixels[i + 1] = value;
    pixels[i + 2] = value;
    pixels[i + 3] = 255;
  }

  int luminanceAt(int x, int y) => pixels[(y * width + x) * 4];

  /// Fills an upright rectangle, in pixels.
  void fillRect(int left, int top, int right, int bottom, {int value = 235}) {
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        set(x, y, value);
      }
    }
  }

  /// Fills the quadrilateral through four corners, given in pixels.
  ///
  /// Scan-line filled by testing each pixel against the shape, which is slow
  /// and obviously correct — the right trade for a test helper.
  void fillQuad(List<Offset> corners, {int value = 235}) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (_contains(corners, Offset(x + 0.5, y + 0.5))) set(x, y, value);
      }
    }
  }

  static bool _contains(List<Offset> corners, Offset point) {
    var sign = 0;
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % corners.length];
      final cross = (b.dx - a.dx) * (point.dy - a.dy) - (b.dy - a.dy) * (point.dx - a.dx);
      if (cross == 0) continue;
      final current = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = current;
      } else if (sign != current) {
        return false;
      }
    }
    return true;
  }

  /// Corners of a rectangle turned [degrees] about the picture's centre.
  static List<Offset> rotatedRect({
    required Size picture,
    required Size rect,
    required double degrees,
  }) {
    final radians = degrees * math.pi / 180;
    final centre = Offset(picture.width / 2, picture.height / 2);
    return [
      for (final corner in [
        Offset(-rect.width / 2, -rect.height / 2),
        Offset(rect.width / 2, -rect.height / 2),
        Offset(rect.width / 2, rect.height / 2),
        Offset(-rect.width / 2, rect.height / 2),
      ])
        centre +
            Offset(
              corner.dx * math.cos(radians) - corner.dy * math.sin(radians),
              corner.dx * math.sin(radians) + corner.dy * math.cos(radians),
            ),
    ];
  }
}
