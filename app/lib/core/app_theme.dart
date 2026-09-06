import 'package:flutter/material.dart';

/// Visual identity for The PDF Project.
///
/// Both themes are derived from a single seed so the light and dark surfaces
/// stay in step; the viewer canvas colour is exposed separately because the
/// page backdrop should be darker than the surrounding chrome.
abstract final class AppTheme {
  static const seed = Color(0xFF2F6FEB);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      listTileTheme: const ListTileThemeData(dense: true),
    );
  }

  /// Backdrop behind the PDF pages.
  static Color viewerBackground(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : scheme.surfaceContainerHighest;
  }
}
