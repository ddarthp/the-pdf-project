import 'package:flutter/material.dart';

import '../features/viewer/model/reading_mode.dart';
import '../features/viewer/model/view_rotation.dart';

/// App-wide, in-memory view preferences.
///
/// Deliberately not persisted yet: persistence lands together with the
/// "remember last opened page per document" feature so both use one store.
class ViewPreferences extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  ReadingMode _readingMode = ReadingMode.continuousScroll;
  ViewRotation _viewRotation = ViewRotation.none;
  bool _invertPages = false;

  ThemeMode get themeMode => _themeMode;

  ReadingMode get readingMode => _readingMode;

  /// Rotation applied to the presentation only; the document is untouched.
  ViewRotation get viewRotation => _viewRotation;

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

  set viewRotation(ViewRotation value) {
    if (_viewRotation == value) return;
    _viewRotation = value;
    notifyListeners();
  }

  set invertPages(bool value) {
    if (_invertPages == value) return;
    _invertPages = value;
    notifyListeners();
  }

  /// Steps the view 90° clockwise, wrapping back to upright.
  void rotateClockwise() => viewRotation = _viewRotation.next;

  /// Cycles system → light → dark → system.
  void cycleThemeMode() {
    themeMode = switch (_themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }
}
