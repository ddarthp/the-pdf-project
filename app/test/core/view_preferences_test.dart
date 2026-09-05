import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/viewer/model/reading_mode.dart';
import 'package:the_pdf_project/features/viewer/model/view_rotation.dart';

void main() {
  test('defaults to system theme and continuous scrolling', () {
    final preferences = ViewPreferences();

    expect(preferences.themeMode, ThemeMode.system);
    expect(preferences.readingMode, ReadingMode.continuousScroll);
    expect(preferences.viewRotation, ViewRotation.none);
    expect(preferences.invertPages, isFalse);
  });

  test('rotateClockwise steps a quarter turn at a time and wraps', () {
    final preferences = ViewPreferences();

    preferences.rotateClockwise();
    expect(preferences.viewRotation, ViewRotation.clockwise90);
    preferences.rotateClockwise();
    preferences.rotateClockwise();
    expect(preferences.viewRotation, ViewRotation.clockwise270);
    preferences.rotateClockwise();
    expect(preferences.viewRotation, ViewRotation.none);
  });

  test('cycles system -> light -> dark -> system', () {
    final preferences = ViewPreferences();

    preferences.cycleThemeMode();
    expect(preferences.themeMode, ThemeMode.light);
    preferences.cycleThemeMode();
    expect(preferences.themeMode, ThemeMode.dark);
    preferences.cycleThemeMode();
    expect(preferences.themeMode, ThemeMode.system);
  });

  test('notifies only on a real change', () {
    final preferences = ViewPreferences();
    var notifications = 0;
    preferences.addListener(() => notifications++);

    preferences.readingMode = ReadingMode.singlePage;
    preferences.readingMode = ReadingMode.singlePage;

    expect(notifications, 1);
  });
}
