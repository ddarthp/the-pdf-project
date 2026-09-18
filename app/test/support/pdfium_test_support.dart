import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:the_pdf_project/features/viewer/services/incoming_documents.dart';

const sampleFixture = 'test/fixtures/sample.pdf';
const encryptedFixture = 'test/fixtures/encrypted.pdf';
const encryptedPassword = 'letmein';
const formFixture = 'test/fixtures/form.pdf';

/// Initialises PDFium for a widget test suite.
///
/// path_provider has no implementation under `flutter test`, so PDFium's cache
/// is pointed at a temp directory before initialisation.
///
/// The test host also has to be told where PDFium itself is. On a device the
/// library comes from the app bundle, but under `flutter test` the host is
/// macOS, and `pdfium_dart`'s loader has no macOS branch: it asks the OS for
/// the library, gets `Unsupported platform`, then falls back to reading
/// `.dart_tool/native_assets.yaml`, which the current Flutter no longer
/// writes — it emits `.dart_tool/flutter_build/<hash>/native_assets.json`
/// instead. Both paths fail, so the load throws before any test body runs.
/// [Pdfrx.pdfiumModulePath] is the loader's documented way out, and
/// `pdfrx_engine`'s worker forwards it to the background isolate that does the
/// actual loading.
Future<void> initializePdfiumForTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfrx_test_cache').path;
  Pdfrx.pdfiumModulePath ??= _hostPdfiumModulePath();
  await pdfrxFlutterInitialize();
}

/// Locates a PDFium build the test host can `dlopen`, or null to let the
/// loader try its own strategies (Linux and Windows hosts resolve it unaided).
///
/// `PDFIUM_PATH` wins, matching the variable `pdfrx_engine` reads when it
/// initialises for plain Dart, so CI can point at its own copy. Otherwise this
/// takes the library the `pdfium_dart` build hook downloads for the host,
/// which lands under `build/` once native assets are enabled:
///
/// ```sh
/// flutter config --enable-native-assets
/// ```
///
/// Returning null when it is missing keeps the failure legible: the tests
/// still fail to load PDFium, but with the loader's own message rather than a
/// path error from here.
String? _hostPdfiumModulePath() {
  final configured = Platform.environment['PDFIUM_PATH'];
  if (configured != null && File(configured).existsSync()) return configured;

  if (!Platform.isMacOS) return null;

  final downloaded = File('build/native_assets/macos/libpdfium.dylib');
  return downloaded.existsSync() ? downloaded.absolute.path : null;
}

/// Gives [IncomingDocuments] an empty platform side, for a test about
/// something else.
///
/// The viewer asks for the document it was launched with and subscribes to the
/// ones that arrive later as soon as it is built. A test host has no plugins
/// registered, so without this Flutter reports a `MissingPluginException`
/// while activating that stream — loudly enough to fail the test around it.
/// An empty handler simply states what is true here: nothing was shared.
void silenceIncomingDocuments() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel(IncomingDocuments.methodChannelName),
    (call) async => const <Object?>[],
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel(IncomingDocuments.eventChannelName),
    (call) async => null,
  );
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
