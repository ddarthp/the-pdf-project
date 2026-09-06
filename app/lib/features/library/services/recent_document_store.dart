import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/recent_document.dart';

/// Keeps the list of recently opened documents between sessions.
///
/// An interface so the home screen can run against an in-memory list in tests.
abstract interface class RecentDocumentStore {
  Future<List<RecentDocument>> load();

  Future<void> save(List<RecentDocument> documents);
}

/// On-device store backed by platform shared preferences.
///
/// Shared preferences rather than a database: the list is capped at
/// [RecentDocuments.maxEntries] small records, so there is nothing here a
/// query would help with. A database earns its place when the library grows
/// into something searchable — folders, tags, finding a document by name —
/// which is a later step.
class SharedPreferencesRecentDocumentStore implements RecentDocumentStore {
  static const _key = 'library.recentDocuments';

  SharedPreferencesAsync? _preferences;
  bool _unavailable = false;

  SharedPreferencesAsync? _resolve() {
    if (_unavailable) return null;
    try {
      return _preferences ??= SharedPreferencesAsync();
    } on Object catch (error) {
      debugPrint('Recent documents unavailable, the list will not persist: $error');
      _unavailable = true;
      return null;
    }
  }

  @override
  Future<List<RecentDocument>> load() async {
    try {
      final raw = await _resolve()?.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      return decode(raw);
    } on Object catch (error) {
      debugPrint('Could not read the recent documents: $error');
      return [];
    }
  }

  @override
  Future<void> save(List<RecentDocument> documents) async {
    try {
      await _resolve()?.setString(_key, encode(documents));
    } on Object catch (error) {
      debugPrint('Could not save the recent documents: $error');
    }
  }

  static String encode(List<RecentDocument> documents) =>
      jsonEncode([for (final document in documents) document.toJson()]);

  /// Reads the list back, skipping any entry that will not parse so one bad
  /// record cannot lose the whole list.
  static List<RecentDocument> decode(String raw) {
    final entries = jsonDecode(raw) as List<Object?>;
    final documents = <RecentDocument>[];
    for (final entry in entries) {
      try {
        documents.add(RecentDocument.fromJson(entry! as Map<String, Object?>));
      } on Object catch (error) {
        debugPrint('Skipping an unreadable recent document: $error');
      }
    }
    return documents;
  }
}

/// Non-persistent store, for tests.
class InMemoryRecentDocumentStore implements RecentDocumentStore {
  InMemoryRecentDocumentStore([List<RecentDocument>? documents])
    : _documents = List.of(documents ?? const []);

  List<RecentDocument> _documents;

  @override
  Future<List<RecentDocument>> load() async => List.of(_documents);

  @override
  Future<void> save(List<RecentDocument> documents) async {
    _documents = List.of(documents);
  }
}
