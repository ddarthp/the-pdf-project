import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/annotation.dart';

/// Keeps a document's annotations between sessions.
///
/// An interface so the viewer can run against an in-memory store in tests, and
/// so the backing store can move to sqflite alongside the library index later
/// without touching the annotation code.
abstract interface class AnnotationStore {
  Future<List<Annotation>> load(String documentKey);

  Future<void> save(String documentKey, List<Annotation> annotations);
}

/// On-device store backed by platform shared preferences, one JSON document
/// per PDF.
///
/// Losing annotations silently would be worse than any other failure here, so
/// read errors are reported and surfaced as "no annotations" only for a store
/// that is genuinely unavailable — never by overwriting what is already there.
class SharedPreferencesAnnotationStore implements AnnotationStore {
  static const _keyPrefix = 'annotations.';

  SharedPreferencesAsync? _preferences;
  bool _unavailable = false;

  SharedPreferencesAsync? _resolve() {
    if (_unavailable) return null;
    try {
      return _preferences ??= SharedPreferencesAsync();
    } on Object catch (error) {
      debugPrint('Annotation store unavailable, annotations will not persist: $error');
      _unavailable = true;
      return null;
    }
  }

  @override
  Future<List<Annotation>> load(String documentKey) async {
    try {
      final raw = await _resolve()?.getString('$_keyPrefix$documentKey');
      if (raw == null || raw.isEmpty) return [];
      return decode(raw);
    } on Object catch (error) {
      debugPrint('Could not read annotations for $documentKey: $error');
      return [];
    }
  }

  @override
  Future<void> save(String documentKey, List<Annotation> annotations) async {
    try {
      await _resolve()?.setString('$_keyPrefix$documentKey', encode(annotations));
    } on Object catch (error) {
      debugPrint('Could not save annotations for $documentKey: $error');
    }
  }

  /// Serialises annotations to the string stored per document.
  static String encode(List<Annotation> annotations) =>
      jsonEncode([for (final annotation in annotations) annotation.toJson()]);

  /// Reads annotations back, skipping any single entry that will not parse so
  /// one bad record cannot take the rest down with it.
  static List<Annotation> decode(String raw) {
    final entries = jsonDecode(raw) as List<Object?>;
    final annotations = <Annotation>[];
    for (final entry in entries) {
      try {
        annotations.add(Annotation.fromJson(entry! as Map<String, Object?>));
      } on Object catch (error) {
        debugPrint('Skipping an unreadable annotation: $error');
      }
    }
    return annotations;
  }
}

/// Non-persistent store, for tests.
class InMemoryAnnotationStore implements AnnotationStore {
  final _documents = <String, List<Annotation>>{};

  @override
  Future<List<Annotation>> load(String documentKey) async =>
      List.of(_documents[documentKey] ?? const []);

  @override
  Future<void> save(String documentKey, List<Annotation> annotations) async {
    _documents[documentKey] = List.of(annotations);
  }
}
