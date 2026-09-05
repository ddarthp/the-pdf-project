import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Shapes a [ShapeAnnotation] can take.
enum ShapeKind { rectangle, ellipse, line, arrow }

/// An annotation drawn on one page.
///
/// All geometry is in **normalised page space**: 0–1 across the page's width
/// and height, origin at the page's top-left. That is what makes an annotation
/// survive zooming, the reading-mode switch and view rotation — the viewer
/// hands us a page rectangle for wherever the page currently is, and the same
/// numbers map onto it. Thicknesses are in PDF points instead, so a stroke
/// keeps a real-world width rather than growing with the page.
@immutable
sealed class Annotation {
  const Annotation({
    required this.id,
    required this.pageNumber,
    required this.color,
    required this.opacity,
    required this.createdAt,
  });

  final String id;

  /// 1-based page this annotation belongs to.
  final int pageNumber;

  final Color color;

  /// 0–1, multiplied into [color] when painting.
  final double opacity;

  final DateTime createdAt;

  /// Bounding box in normalised page space, for hit testing and the panel.
  Rect get normalizedBounds;

  /// A short description of the annotation, shown in the annotations panel.
  String get summary;

  /// The same annotation shifted by [delta] in normalised page space.
  Annotation movedBy(Offset delta);

  /// The same annotation restyled, for editing an existing one.
  Annotation restyled({Color? color, double? opacity, double? strokeWidth});

  Map<String, Object?> toJson();

  Map<String, Object?> get _baseJson => {
    'id': id,
    'page': pageNumber,
    'color': color.toARGB32(),
    'opacity': opacity,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Rebuilds an annotation written by [toJson].
  ///
  /// Throws [FormatException] on anything it does not recognise, so a corrupt
  /// store surfaces as one bad annotation rather than a broken document.
  static Annotation fromJson(Map<String, Object?> json) {
    final type = json['type'];
    final id = json['id'] as String;
    final pageNumber = (json['page'] as num).toInt();
    final color = Color((json['color'] as num).toInt());
    final opacity = (json['opacity'] as num).toDouble();
    final createdAt = DateTime.parse(json['createdAt'] as String);

    return switch (type) {
      'ink' => InkAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color,
        opacity: opacity,
        createdAt: createdAt,
        strokes: [
          for (final stroke in json['strokes'] as List<Object?>)
            [
              for (final point in stroke! as List<Object?>)
                _offsetFromJson(point! as List<Object?>),
            ],
        ],
        strokeWidth: (json['strokeWidth'] as num).toDouble(),
      ),
      'shape' => ShapeAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color,
        opacity: opacity,
        createdAt: createdAt,
        kind: ShapeKind.values.byName(json['kind'] as String),
        start: _offsetFromJson(json['start']! as List<Object?>),
        end: _offsetFromJson(json['end']! as List<Object?>),
        strokeWidth: (json['strokeWidth'] as num).toDouble(),
      ),
      'highlight' => HighlightAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color,
        opacity: opacity,
        createdAt: createdAt,
        bands: [for (final band in json['bands'] as List<Object?>) _rectFromJson(band! as List<Object?>)],
        text: json['text'] as String? ?? '',
      ),
      'textBox' => TextBoxAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color,
        opacity: opacity,
        createdAt: createdAt,
        bounds: _rectFromJson(json['bounds']! as List<Object?>),
        text: json['text'] as String,
        fontSize: (json['fontSize'] as num).toDouble(),
      ),
      'stickyNote' => StickyNoteAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color,
        opacity: opacity,
        createdAt: createdAt,
        anchor: _offsetFromJson(json['anchor']! as List<Object?>),
        text: json['text'] as String,
      ),
      _ => throw FormatException('Unknown annotation type: $type'),
    };
  }

  static Offset _offsetFromJson(List<Object?> json) =>
      Offset((json[0]! as num).toDouble(), (json[1]! as num).toDouble());

  static List<double> _offsetToJson(Offset offset) => [offset.dx, offset.dy];

  static Rect _rectFromJson(List<Object?> json) => Rect.fromLTRB(
    (json[0]! as num).toDouble(),
    (json[1]! as num).toDouble(),
    (json[2]! as num).toDouble(),
    (json[3]! as num).toDouble(),
  );

  static List<double> _rectToJson(Rect rect) => [rect.left, rect.top, rect.right, rect.bottom];
}

/// Freehand drawing: one or more strokes of connected points.
class InkAnnotation extends Annotation {
  const InkAnnotation({
    required super.id,
    required super.pageNumber,
    required super.color,
    required super.opacity,
    required super.createdAt,
    required this.strokes,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;

  /// Thickness in PDF points.
  final double strokeWidth;

  @override
  Rect get normalizedBounds {
    var bounds = Rect.zero;
    var isFirst = true;
    for (final stroke in strokes) {
      for (final point in stroke) {
        final pointRect = Rect.fromLTWH(point.dx, point.dy, 0, 0);
        bounds = isFirst ? pointRect : bounds.expandToInclude(pointRect);
        isFirst = false;
      }
    }
    return bounds;
  }

  @override
  String get summary => 'Drawing';

  @override
  InkAnnotation movedBy(Offset delta) => _copyWith(
    strokes: [
      for (final stroke in strokes) [for (final point in stroke) point + delta],
    ],
  );

  @override
  InkAnnotation restyled({Color? color, double? opacity, double? strokeWidth}) =>
      _copyWith(color: color, opacity: opacity, strokeWidth: strokeWidth);

  InkAnnotation _copyWith({
    List<List<Offset>>? strokes,
    Color? color,
    double? opacity,
    double? strokeWidth,
  }) => InkAnnotation(
    id: id,
    pageNumber: pageNumber,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    createdAt: createdAt,
    strokes: strokes ?? this.strokes,
    strokeWidth: strokeWidth ?? this.strokeWidth,
  );

  @override
  Map<String, Object?> toJson() => {
    ...super._baseJson,
    'type': 'ink',
    'strokeWidth': strokeWidth,
    'strokes': [
      for (final stroke in strokes) [for (final point in stroke) Annotation._offsetToJson(point)],
    ],
  };
}

/// Rectangle, ellipse, line or arrow, defined by two corners or endpoints.
class ShapeAnnotation extends Annotation {
  const ShapeAnnotation({
    required super.id,
    required super.pageNumber,
    required super.color,
    required super.opacity,
    required super.createdAt,
    required this.kind,
    required this.start,
    required this.end,
    required this.strokeWidth,
  });

  final ShapeKind kind;
  final Offset start;
  final Offset end;

  /// Thickness in PDF points.
  final double strokeWidth;

  @override
  Rect get normalizedBounds => Rect.fromPoints(start, end);

  @override
  String get summary => switch (kind) {
    ShapeKind.rectangle => 'Rectangle',
    ShapeKind.ellipse => 'Ellipse',
    ShapeKind.line => 'Line',
    ShapeKind.arrow => 'Arrow',
  };

  @override
  ShapeAnnotation movedBy(Offset delta) => _copyWith(start: start + delta, end: end + delta);

  @override
  ShapeAnnotation restyled({Color? color, double? opacity, double? strokeWidth}) =>
      _copyWith(color: color, opacity: opacity, strokeWidth: strokeWidth);

  ShapeAnnotation _copyWith({
    Offset? start,
    Offset? end,
    Color? color,
    double? opacity,
    double? strokeWidth,
  }) => ShapeAnnotation(
    id: id,
    pageNumber: pageNumber,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    createdAt: createdAt,
    kind: kind,
    start: start ?? this.start,
    end: end ?? this.end,
    strokeWidth: strokeWidth ?? this.strokeWidth,
  );

  @override
  Map<String, Object?> toJson() => {
    ...super._baseJson,
    'type': 'shape',
    'kind': kind.name,
    'start': Annotation._offsetToJson(start),
    'end': Annotation._offsetToJson(end),
    'strokeWidth': strokeWidth,
  };
}

/// Text highlight: one band per line of text covered.
class HighlightAnnotation extends Annotation {
  const HighlightAnnotation({
    required super.id,
    required super.pageNumber,
    required super.color,
    required super.opacity,
    required super.createdAt,
    required this.bands,
    this.text = '',
  });

  final List<Rect> bands;

  /// The highlighted text, when it could be read off the page.
  final String text;

  @override
  Rect get normalizedBounds =>
      bands.isEmpty ? Rect.zero : bands.reduce((a, b) => a.expandToInclude(b));

  @override
  String get summary => text.isEmpty ? 'Highlight' : text;

  @override
  HighlightAnnotation movedBy(Offset delta) =>
      _copyWith(bands: [for (final band in bands) band.shift(delta)]);

  @override
  HighlightAnnotation restyled({Color? color, double? opacity, double? strokeWidth}) =>
      _copyWith(color: color, opacity: opacity);

  HighlightAnnotation _copyWith({List<Rect>? bands, Color? color, double? opacity}) =>
      HighlightAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color ?? this.color,
        opacity: opacity ?? this.opacity,
        createdAt: createdAt,
        bands: bands ?? this.bands,
        text: text,
      );

  @override
  Map<String, Object?> toJson() => {
    ...super._baseJson,
    'type': 'highlight',
    'bands': [for (final band in bands) Annotation._rectToJson(band)],
    'text': text,
  };
}

/// A box of text drawn onto the page.
class TextBoxAnnotation extends Annotation {
  const TextBoxAnnotation({
    required super.id,
    required super.pageNumber,
    required super.color,
    required super.opacity,
    required super.createdAt,
    required this.bounds,
    required this.text,
    required this.fontSize,
  });

  final Rect bounds;
  final String text;

  /// Font size in PDF points.
  final double fontSize;

  @override
  Rect get normalizedBounds => bounds;

  @override
  String get summary => text.isEmpty ? 'Text box' : text;

  @override
  TextBoxAnnotation movedBy(Offset delta) => _copyWith(bounds: bounds.shift(delta));

  @override
  TextBoxAnnotation restyled({Color? color, double? opacity, double? strokeWidth}) => _copyWith(
    color: color,
    opacity: opacity,
    // Thickness doubles as font size for a text box, so the same toolbar
    // control resizes the lettering.
    fontSize: strokeWidth == null ? null : strokeWidth * 4,
  );

  TextBoxAnnotation withText(String text) => TextBoxAnnotation(
    id: id,
    pageNumber: pageNumber,
    color: color,
    opacity: opacity,
    createdAt: createdAt,
    bounds: bounds,
    text: text,
    fontSize: fontSize,
  );

  TextBoxAnnotation _copyWith({Rect? bounds, Color? color, double? opacity, double? fontSize}) =>
      TextBoxAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color ?? this.color,
        opacity: opacity ?? this.opacity,
        createdAt: createdAt,
        bounds: bounds ?? this.bounds,
        text: text,
        fontSize: fontSize ?? this.fontSize,
      );

  @override
  Map<String, Object?> toJson() => {
    ...super._baseJson,
    'type': 'textBox',
    'bounds': Annotation._rectToJson(bounds),
    'text': text,
    'fontSize': fontSize,
  };
}

/// A pinned comment: a small marker on the page with text behind it.
class StickyNoteAnnotation extends Annotation {
  const StickyNoteAnnotation({
    required super.id,
    required super.pageNumber,
    required super.color,
    required super.opacity,
    required super.createdAt,
    required this.anchor,
    required this.text,
  });

  /// Where the marker sits, in normalised page space.
  final Offset anchor;

  final String text;

  /// Marker size in PDF points; fixed so notes stay tappable at any zoom.
  static const markerSize = 22.0;

  @override
  Rect get normalizedBounds => Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0);

  @override
  String get summary => text.isEmpty ? 'Note' : text;

  @override
  StickyNoteAnnotation movedBy(Offset delta) => _copyWith(anchor: anchor + delta);

  @override
  StickyNoteAnnotation restyled({Color? color, double? opacity, double? strokeWidth}) =>
      _copyWith(color: color, opacity: opacity);

  StickyNoteAnnotation withText(String text) => StickyNoteAnnotation(
    id: id,
    pageNumber: pageNumber,
    color: color,
    opacity: opacity,
    createdAt: createdAt,
    anchor: anchor,
    text: text,
  );

  StickyNoteAnnotation _copyWith({Offset? anchor, Color? color, double? opacity}) =>
      StickyNoteAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: color ?? this.color,
        opacity: opacity ?? this.opacity,
        createdAt: createdAt,
        anchor: anchor ?? this.anchor,
        text: text,
      );

  @override
  Map<String, Object?> toJson() => {
    ...super._baseJson,
    'type': 'stickyNote',
    'anchor': Annotation._offsetToJson(anchor),
    'text': text,
  };
}
