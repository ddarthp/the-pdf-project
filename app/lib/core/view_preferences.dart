import 'package:flutter/material.dart';

import '../features/viewer/model/reading_mode.dart';

/// App-wide, in-memory view preferences.
///
/// Deliberately not persisted yet: persistence lands together with the
/// "remember last opened page per document" feature so both use one store.
class ViewPreferences extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  ReadingMode _readingMode = ReadingMode.continuousScroll;
  bool _invertPages = false;

  ThemeMode get themeMode => _themeMode;

  ReadingMode get readingMode => _readingMode;

  /// Renders page content inverted (white-on-black) without touching the
  /// app chrome — a true "night mode" for the document itself.
  bool get invertPages => _invertPages;

  set themeMode(ThemeMode value) {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
  }

  set readingMode(ReadingMode value) {
    if (_readingMode == value) return;
    _readingMode = value;
    notifyListeners();
  }

  set invertPages(bool value) {
    if (_invertPages == value) return;
    _invertPages = value;
    notifyListeners();
  }

  /// Cycles system → light → dark → system.
  void cycleThemeMode() {
    themeMode = switch (_themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }
}
