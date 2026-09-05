import 'package:flutter/material.dart';

/// A pad to sign on with a finger or stylus.
///
/// Strokes are reported in the canvas's own pixels; [SignatureGeometry.tighten]
/// crops them to what was drawn on the way out.
class SignatureCanvas extends StatefulWidget {
  const SignatureCanvas({
    required this.strokes,
    required this.color,
    required this.onChanged,
    super.key,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final ValueChanged<List<List<Offset>>> onChanged;

  /// Stroke thickness on the pad, in logical pixels.
  static const strokeWidth = 3.0;

  @override
  State<SignatureCanvas> createState() => _SignatureCanvasState();
}

class _SignatureCanvasState extends State<SignatureCanvas> {
  List<Offset>? _current;

  void _start(Offset position) {
    _current = [position];
    widget.onChanged([...widget.strokes, _current!]);
  }

  void _extend(Offset position) {
    final current = _current;
    if (current == null) return;
    // The last stroke in the list is the one being drawn.
    final strokes = [...widget.strokes];
    if (strokes.isEmpty) return;
    strokes[strokes.length - 1] = [...current..add(position)];
    widget.onChanged(strokes);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _start(event.localPosition),
          onPointerMove: (event) => _extend(event.localPosition),
          onPointerUp: (_) => _current = null,
          onPointerCancel: (_) => _current = null,
          child: CustomPaint(
            painter: _SignaturePainter(strokes: widget.strokes, color: widget.color),
            size: Size.infinite,
            child: widget.strokes.isEmpty
                ? Center(
                    child: Text(
                      'Sign here',
                      style: TextStyle(color: scheme.outline),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes, required this.color});

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = SignatureCanvas.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, SignatureCanvas.strokeWidth / 2, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.color != color;
}
