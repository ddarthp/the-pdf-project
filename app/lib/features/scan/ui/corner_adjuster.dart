import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/document_quad.dart';

/// The photograph with the page's corners drawn on it, ready to be dragged.
///
/// Automatic detection is right most of the time and wrong often enough to
/// matter, so the corners it found are shown rather than applied silently —
/// and any of them can be moved.
class CornerAdjuster extends StatefulWidget {
  const CornerAdjuster({
    required this.photograph,
    required this.quad,
    required this.onChanged,
    super.key,
  });

  final Uint8List photograph;
  final DocumentQuad quad;
  final ValueChanged<DocumentQuad> onChanged;

  /// How big the draggable handles are, in logical pixels.
  static const handleRadius = 14.0;

  @override
  State<CornerAdjuster> createState() => _CornerAdjusterState();
}

class _CornerAdjusterState extends State<CornerAdjuster> {
  int? _dragging;

  void _onPointerDown(Offset local, Size size) {
    if (size.isEmpty) return;
    final point = Offset(local.dx / size.width, local.dy / size.height);

    var nearest = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < 4; i++) {
      final corner = widget.quad[i];
      final distance =
          (Offset(corner.dx * size.width, corner.dy * size.height) - local).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = i;
      }
    }
    // Only grab a corner if the touch was actually near one; a tap in the
    // middle of the page should not fling the closest corner across it.
    if (nearestDistance > CornerAdjuster.handleRadius * 2.5) return;
    _dragging = nearest;
    _move(point);
  }

  void _move(Offset point) {
    final dragging = _dragging;
    if (dragging == null) return;
    final moved = widget.quad.withCorner(dragging, point);
    // A quad whose corners have crossed over would fold the page; the move is
    // simply refused rather than corrected behind the reader's back.
    if (!moved.isConvex) return;
    widget.onChanged(moved);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _onPointerDown(event.localPosition, size),
          onPointerMove: (event) => _move(
            Offset(
              event.localPosition.dx / size.width,
              event.localPosition.dy / size.height,
            ),
          ),
          onPointerUp: (_) => _dragging = null,
          onPointerCancel: (_) => _dragging = null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(widget.photograph, fit: BoxFit.fill),
              CustomPaint(
                painter: _QuadPainter(
                  quad: widget.quad,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuadPainter extends CustomPainter {
  const _QuadPainter({required this.quad, required this.color});

  final DocumentQuad quad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(int index) =>
        Offset(quad[index].dx * size.width, quad[index].dy * size.height);

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < 4; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    path.close();

    // Everything outside the page is dimmed, so what will be kept is obvious
    // at a glance.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        path,
      ),
      Paint()..color = const Color(0x88000000),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < 4; i++) {
      canvas
        ..drawCircle(at(i), CornerAdjuster.handleRadius, Paint()..color = color)
        ..drawCircle(
          at(i),
          CornerAdjuster.handleRadius - 4,
          Paint()..color = const Color(0xFFFFFFFF),
        );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.color != color;
}
