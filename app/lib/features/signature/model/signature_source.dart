import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How a typed signature is lettered.
///
/// Built from the platform's own fonts rather than a bundled script face, so
/// the app carries no font licence and the choices work everywhere. A real
/// handwriting font is a nicety for later.
enum SignatureTypeface {
  flowing('Flowing', FontStyle.italic, FontWeight.w400, ['serif', 'Georgia', 'Times New Roman']),
  bold('Bold', FontStyle.normal, FontWeight.w700, null),
  plain('Plain', FontStyle.normal, FontWeight.w400, null);

  const SignatureTypeface(this.label, this.fontStyle, this.fontWeight, this.familyFallback);

  final String label;
  final FontStyle fontStyle;
  final FontWeight fontWeight;
  final List<String>? familyFallback;
}

/// What a signature is made of, before it is placed on a page.
///
/// The three ways of making one — drawing it, typing it, or picking a picture
/// of it — differ only in this. Placing, moving, resizing, drawing on screen
/// and exporting all work from the same [SignatureAnnotation] around it.
@immutable
sealed class SignatureSource {
  const SignatureSource();

  /// Width divided by height, used to give a signature a sensible shape when
  /// it is first placed.
  double get aspectRatio;

  Map<String, Object?> toJson();

  static Offset _offsetFrom(List<Object?> json) =>
      Offset((json[0]! as num).toDouble(), (json[1]! as num).toDouble());

  static SignatureSource fromJson(Map<String, Object?> json) => switch (json['kind']) {
    'drawn' => DrawnSignature(
      strokes: [
        for (final stroke in json['strokes'] as List<Object?>)
          [
            for (final point in stroke! as List<Object?>)
              _offsetFrom(point! as List<Object?>),
          ],
      ],
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      aspectRatio: (json['aspectRatio'] as num).toDouble(),
    ),
    'typed' => TypedSignature(
      text: json['text'] as String,
      typeface: SignatureTypeface.values.byName(json['typeface'] as String),
      aspectRatio: (json['aspectRatio'] as num).toDouble(),
    ),
    'image' => ImageSignature(
      bytes: base64Decode(json['bytes'] as String),
      aspectRatio: (json['aspectRatio'] as num).toDouble(),
    ),
    _ => throw FormatException('Unknown signature kind: ${json['kind']}'),
  };
}

/// A signature drawn by hand.
///
/// Strokes are stored as fractions of the signature's own box, so the same
/// points work at whatever size it ends up being placed.
class DrawnSignature extends SignatureSource {
  const DrawnSignature({
    required this.strokes,
    required this.strokeWidth,
    required this.aspectRatio,
  });

  final List<List<Offset>> strokes;

  /// Thickness as a fraction of the signature's width, so the stroke scales
  /// with the signature rather than staying a fixed size.
  final double strokeWidth;

  @override
  final double aspectRatio;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'drawn',
    'strokeWidth': strokeWidth,
    'aspectRatio': aspectRatio,
    'strokes': [
      for (final stroke in strokes)
        [
          for (final point in stroke) [point.dx, point.dy],
        ],
    ],
  };
}

/// A signature typed out and lettered by the app.
class TypedSignature extends SignatureSource {
  const TypedSignature({
    required this.text,
    required this.typeface,
    required this.aspectRatio,
  });

  final String text;
  final SignatureTypeface typeface;

  @override
  final double aspectRatio;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'typed',
    'text': text,
    'typeface': typeface.name,
    'aspectRatio': aspectRatio,
  };
}

/// A signature from a picture — a photo or scan of one on paper.
class ImageSignature extends SignatureSource {
  const ImageSignature({required this.bytes, required this.aspectRatio});

  /// Encoded image data, as picked or as re-encoded on the way in.
  final Uint8List bytes;

  @override
  final double aspectRatio;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'image',
    'bytes': base64Encode(bytes),
    'aspectRatio': aspectRatio,
  };
}
