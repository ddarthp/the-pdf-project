import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which page a reader was on, per document.
///
/// Stays an interface so the viewer can be driven by an in-memory store in
/// tests, and so the backing store can later grow into the library index
/// without touching the viewer.
abstract interface class LastPageStore {
  /// Last page read for [documentKey], or null if the document is new.
  Future<int?> lastPage(String documentKey);

  Future<void> saveLastPage(String documentKey, int pageNumber);
}

/// On-device store backed by platform shared preferences.
///
/// Resuming where you left off is a convenience, so a store that is missing or
/// misbehaving degrades to "no bookmark" rather than failing the open. The
/// platform object is created on first use because constructing it throws
/// where no platform implementation is registered (a plain `flutter test`,
/// for one).
class SharedPreferencesLastPageStore implements LastPageStore {
  static const _keyPrefix = 'viewer.lastPage.';

  SharedPreferencesAsync? _preferences;
  bool _unavailable = false;

  SharedPreferencesAsync? _resolve() {
    if (_unavailable) return null;
    try {
      return _preferences ??= SharedPreferencesAsync();
    } on Object catch (error) {
      debugPrint('Last-page store unavailable, not remembering pages: $error');
      _unavailable = true;
      return null;
    }
  }

  @override
  Future<int?> lastPage(String documentKey) async {
    try {
      return await _resolve()?.getInt('$_keyPrefix$documentKey');
    } on Object catch (error) {
      debugPrint('Could not read the last page for $documentKey: $error');
      return null;
    }
  }

  @override
  Future<void> saveLastPage(String documentKey, int pageNumber) async {
    try {
      await _resolve()?.setInt('$_keyPrefix$documentKey', pageNumber);
    } on Object catch (error) {
      debugPrint('Could not save the last page for $documentKey: $error');
    }
  }
}

/// Non-persistent store, for tests and for the case where no store is wanted.
class InMemoryLastPageStore implements LastPageStore {
  final _pages = <String, int>{};

  @override
  Future<int?> lastPage(String documentKey) async => _pages[documentKey];

  @override
  Future<void> saveLastPage(String documentKey, int pageNumber) async {
    _pages[documentKey] = pageNumber;
  }
}
