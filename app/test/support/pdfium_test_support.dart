import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

const sampleFixture = 'test/fixtures/sample.pdf';
const encryptedFixture = 'test/fixtures/encrypted.pdf';
const encryptedPassword = 'letmein';

/// Initialises PDFium for a widget test suite.
///
/// path_provider has no implementation under `flutter test`, so PDFium's cache
/// is pointed at a temp directory before initialisation.
Future<void> initializePdfiumForTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfrx_test_cache').path;
  await pdfrxFlutterInitialize();
}

/// Pumps until [finder] matches, letting real async work (file I/O, PDFium
/// calls, image decoding) run between frames. `pumpAndSettle` alone is not
/// enough: loading a document schedules no frames while it waits on I/O.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $finder');
}

/// The mirror of [pumpUntil]: pumps until [finder] no longer matches, for
/// waiting on something to go away (a route being popped, say).
Future<void> pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isEmpty) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $finder to disappear');
}

/// Lets pdfrx's progressive page-loading finish its trailing timers.
///
/// Without this the test framework reports "a Timer is still pending" for any
/// test whose last document load lands close to the end of the test body.
Future<void> drainBackgroundLoading(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// A widget test that opens a document: gives it a viewport big enough for the
/// toolbars and a whole page, and drains pdfrx's timers afterwards.
void documentTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await body(tester);
    await drainBackgroundLoading(tester);
  });
}
