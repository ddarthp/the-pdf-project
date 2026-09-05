import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../signature/model/signature_source.dart';
import '../logic/page_coordinates.dart';
import '../model/annotation.dart';

/// Draws annotations onto a canvas.
///
/// The painter knows nothing about where the page is: it is handed the page's
/// rectangle in whatever space the canvas uses, and every normalised
/// coordinate is mapped through that. So the same code paints into the
/// viewer's document space and into a widget's local space.
abstract final class AnnotationPainter {
  /// Size of a selection handle, in logical pixels of the target canvas.
  static const handleRadius = 5.0;

  /// Looks up the decoded picture for an image signature.
  static ui.Image? _noImages(String annotationId) => null;

  static void paint(
    Canvas canvas,
    Annotation annotation, {
    required Rect pageRect,
    required double pageWidthInPoints,
    required bool isSelected,
    required Color selectionColor,
    ui.Image? Function(String annotationId) signatureImage = _noImages,
  }) {
    Offset toDoc(Offset normalized) => PageCoordinates.toDocument(normalized, pageRect);
    Rect toDocRect(Rect normalized) => PageCoordinates.rectToDocument(normalized, pageRect);
    double width(double points) =>
        PageCoordinates.lengthToDocument(points, pageRect, pageWidthInPoints);

    final color = annotation.color.withValues(alpha: annotation.opacity);

    switch (annotation) {
      case InkAnnotation(:final strokes, :final strokeWidth):
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width(strokeWidth)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (final stroke in strokes) {
          if (stroke.isEmpty) continue;
          if (stroke.length == 1) {
            // A tap with the pen down is a dot, not nothing.
            canvas.drawCircle(toDoc(stroke.first), width(strokeWidth) / 2, Paint()..color = color);
            continue;
          }
          final path = Path()..moveTo(toDoc(stroke.first).dx, toDoc(stroke.first).dy);
          for (final point in stroke.skip(1)) {
            final mapped = toDoc(point);
            path.lineTo(mapped.dx, mapped.dy);
          }
          canvas.drawPath(path, paint);
        }

      case ShapeAnnotation(:final kind, :final start, :final end, :final strokeWidth):
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width(strokeWidth)
          ..strokeCap = StrokeCap.round;
        final a = toDoc(start);
        final b = toDoc(end);
        switch (kind) {
          case ShapeKind.rectangle:
            canvas.drawRect(Rect.fromPoints(a, b), paint);
          case ShapeKind.ellipse:
            canvas.drawOval(Rect.fromPoints(a, b), paint);
          case ShapeKind.line:
            canvas.drawLine(a, b, paint);
          case ShapeKind.arrow:
            canvas.drawLine(a, b, paint);
            _paintArrowHead(canvas, a, b, paint, width(strokeWidth));
        }

      case HighlightAnnotation(:final bands):
        // Multiply keeps the text readable through the colour, the way a
        // marker pen works on paper.
        final paint = Paint()
          ..color = color
          ..blendMode = BlendMode.multiply;
        for (final band in bands) {
          canvas.drawRect(toDocRect(band), paint);
        }

      case TextBoxAnnotation(:final bounds, :final text, :final fontSize):
        final rect = toDocRect(bounds);
        canvas.drawRect(
          rect,
          Paint()
            ..color = color.withValues(alpha: annotation.opacity * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = width(1),
        );
        if (text.isNotEmpty) {
          _paintText(
            canvas,
            text,
            rect.deflate(width(3)),
            color: annotation.color.withValues(alpha: annotation.opacity),
            fontSize: width(fontSize),
          );
        }

      case StickyNoteAnnotation(:final anchor, :final text):
        final size = width(StickyNoteAnnotation.markerSize);
        final rect = Rect.fromLTWH(toDoc(anchor).dx, toDoc(anchor).dy, size, size);
        final radius = Radius.circular(size * 0.2);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius, bottomRight: radius),
          Paint()..color = color,
        );
        // Two rules stand in for the note's text at any size.
        final rulePaint = Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85)
          ..strokeWidth = math.max(1, size * 0.08)
          ..strokeCap = StrokeCap.round;
        for (final fraction in const [0.38, 0.6]) {
          canvas.drawLine(
            Offset(rect.left + size * 0.22, rect.top + size * fraction),
            Offset(rect.right - size * (text.isEmpty ? 0.45 : 0.22), rect.top + size * fraction),
            rulePaint,
          );
        }

      case SignatureAnnotation(:final source, :final bounds):
        _paintSignature(
          canvas,
          source,
          toDocRect(bounds),
          color: annotation.color,
          opacity: annotation.opacity,
          image: signatureImage(annotation.id),
        );
    }

    if (isSelected) {
      _paintSelection(canvas, toDocRect(annotation.normalizedBounds), selectionColor);
    }
  }

  /// Draws a signature stretched to fill [rect], whichever way it was made.
  static void _paintSignature(
    Canvas canvas,
    SignatureSource source,
    Rect rect, {
    required Color color,
    required double opacity,
    required ui.Image? image,
  }) {
    if (rect.width <= 0 || rect.height <= 0) return;

    switch (source) {
      case DrawnSignature(:final strokes, :final strokeWidth):
        final paint = Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          // The width is a fraction of the signature, so it grows and shrinks
          // with it rather than staying a fixed size on the page.
          ..strokeWidth = math.max(strokeWidth * rect.width, 0.2)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (final stroke in strokes) {
          if (stroke.isEmpty) continue;
          Offset at(Offset point) =>
              Offset(rect.left + point.dx * rect.width, rect.top + point.dy * rect.height);
          if (stroke.length == 1) {
            canvas.drawCircle(at(stroke.first), paint.strokeWidth / 2, Paint()..color = paint.color);
            continue;
          }
          final path = Path()..moveTo(at(stroke.first).dx, at(stroke.first).dy);
          for (final point in stroke.skip(1)) {
            path.lineTo(at(point).dx, at(point).dy);
          }
          canvas.drawPath(path, paint);
        }

      case TypedSignature(:final text, :final typeface):
        final painter = TextPainter(
          text: TextSpan(text: text, style: typedSignatureStyle(typeface, color, opacity)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        if (painter.width <= 0 || painter.height <= 0) return;
        // Laid out once at a nominal size, then stretched onto the rectangle,
        // so the lettering fills the signature exactly however it is resized.
        canvas.save();
        canvas.translate(rect.left, rect.top);
        canvas.scale(rect.width / painter.width, rect.height / painter.height);
        painter.paint(canvas, Offset.zero);
        canvas.restore();
        painter.dispose();

      case ImageSignature():
        if (image == null) {
          // Still decoding: show where it will land rather than a blank gap.
          canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(0x33000000)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
          return;
        }
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity),
        );
    }
  }

  /// The lettering of a typed signature, at the nominal size it is laid out
  /// before being stretched onto the page.
  static TextStyle typedSignatureStyle(
    SignatureTypeface typeface,
    Color color,
    double opacity,
  ) => TextStyle(
    color: color.withValues(alpha: opacity),
    fontSize: 96,
    fontStyle: typeface.fontStyle,
    fontWeight: typeface.fontWeight,
    fontFamilyFallback: typeface.familyFallback,
  );

  static void _paintArrowHead(Canvas canvas, Offset from, Offset to, Paint paint, double width) {
    final direction = to - from;
    if (direction.distance == 0) return;
    final angle = math.atan2(direction.dy, direction.dx);
    final headLength = math.max(width * 3, 8.0);
    const spread = math.pi / 7;
    for (final side in const [1, -1]) {
      canvas.drawLine(
        to,
        to - Offset(math.cos(angle + spread * side), math.sin(angle + spread * side)) * headLength,
        paint,
      );
    }
  }

  static void _paintText(
    Canvas canvas,
    String text,
    Rect rect, {
    required Color color,
    required double fontSize,
  }) {
    if (rect.width <= 0 || rect.height <= 0) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: math.max(fontSize, 1)),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    canvas.save();
    canvas.clipRect(rect);
    painter.paint(canvas, rect.topLeft);
    canvas.restore();
  }

  static void _paintSelection(Canvas canvas, Rect bounds, Color color) {
    final rect = bounds.inflate(handleRadius * 1.5);
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final handlePaint = Paint()..color = color;
    for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawCircle(corner, handleRadius, handlePaint);
    }
  }
}
