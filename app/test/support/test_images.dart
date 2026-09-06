import 'dart:typed_data';
import 'dart:ui' as ui;

/// Makes small pictures to convert, so the tests need no image fixtures.
///
/// Drawn with Flutter and encoded as PNG, which is one of the two formats a
/// PDF can carry as it stands.
Future<Uint8List> testPng({
  required int width,
  required int height,
  ui.Color color = const ui.Color(0xFF1E88E5),
}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
