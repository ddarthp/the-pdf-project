import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/signature/model/signature_source.dart';

void main() {
  final samples = <String, SignatureSource>{
    'drawn': const DrawnSignature(
      strokes: [
        [Offset(0, 0), Offset(0.5, 0.4), Offset(1, 1)],
        [Offset(0.2, 0.8)],
      ],
      strokeWidth: 0.01,
      aspectRatio: 3,
    ),
    'typed': const TypedSignature(
      text: 'Ada Lovelace',
      typeface: SignatureTypeface.flowing,
      aspectRatio: 4.2,
    ),
    'image': ImageSignature(
      bytes: Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]),
      aspectRatio: 2.5,
    ),
  };

  for (final entry in samples.entries) {
    test('a ${entry.key} signature survives a JSON round trip', () {
      final restored = SignatureSource.fromJson(entry.value.toJson());

      expect(restored.runtimeType, entry.value.runtimeType);
      expect(restored.aspectRatio, entry.value.aspectRatio);
      expect(restored.toJson(), entry.value.toJson());
    });
  }

  test('image bytes come back exactly as they went in', () {
    final original = samples['image']! as ImageSignature;

    final restored = SignatureSource.fromJson(original.toJson()) as ImageSignature;

    expect(restored.bytes, original.bytes);
  });

  test('a typed signature keeps its lettering', () {
    final restored = SignatureSource.fromJson(samples['typed']!.toJson()) as TypedSignature;

    expect(restored.text, 'Ada Lovelace');
    expect(restored.typeface, SignatureTypeface.flowing);
  });

  test('an unknown kind is rejected rather than silently dropped', () {
    expect(
      () => SignatureSource.fromJson(const {'kind': 'hologram'}),
      throwsFormatException,
    );
  });

  test('every typeface has something to letter with', () {
    for (final typeface in SignatureTypeface.values) {
      expect(typeface.label, isNotEmpty);
    }
  });
}
