import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/services/incoming_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late IncomingDocuments incoming;
  late List<MethodCall> calls;
  Object? initialPayload;
  Object? initialError;

  const methods = MethodChannel(IncomingDocuments.methodChannelName);
  const events = MethodChannel(IncomingDocuments.eventChannelName);
  const codec = StandardMethodCodec();

  setUp(() {
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    calls = [];
    initialPayload = null;
    initialError = null;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (initialError != null) throw initialError!;
      return initialPayload;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      calls.add(call);
      return null;
    });
    incoming = IncomingDocuments();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  /// Pushes one platform event down the event channel, the way a second
  /// "Open with" does while the app is already on screen.
  void emit(Object? payload) {
    messenger.handlePlatformMessage(
      IncomingDocuments.eventChannelName,
      codec.encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  void emitError() {
    messenger.handlePlatformMessage(
      IncomingDocuments.eventChannelName,
      codec.encodeErrorEnvelope(code: 'unreadable', message: 'could not be copied'),
      (_) {},
    );
  }

  group('takeInitialDocuments', () {
    test('hands over the document the app was launched with', () async {
      initialPayload = [
        {'path': '/cache/incoming/report.pdf', 'name': 'report.pdf'},
      ];

      final documents = await incoming.takeInitialDocuments();

      expect(documents, hasLength(1));
      expect(documents.single.path, '/cache/incoming/report.pdf');
      expect(documents.single.displayName, 'report.pdf');
      expect(calls.single.method, 'takeInitialDocuments');
    });

    test('is empty when the app was opened from its own icon', () async {
      initialPayload = const <Object?>[];

      expect(await incoming.takeInitialDocuments(), isEmpty);
    });

    test('keeps the order of several shared documents', () async {
      initialPayload = [
        {'path': '/cache/incoming/a.pdf', 'name': 'a.pdf'},
        {'path': '/cache/incoming/b.pdf', 'name': 'b.pdf'},
      ];

      final documents = await incoming.takeInitialDocuments();

      expect([for (final document in documents) document.displayName], ['a.pdf', 'b.pdf']);
    });

    test('names a document after its file when the sender gave no name', () async {
      initialPayload = [
        {'path': '/cache/incoming/unnamed-42.pdf'},
      ];

      expect((await incoming.takeInitialDocuments()).single.displayName, 'unnamed-42.pdf');
    });

    test('is empty when the platform answers with nothing at all', () async {
      initialPayload = null;

      expect(await incoming.takeInitialDocuments(), isEmpty);
    });

    test('is empty when the platform answers with something that is not a list', () async {
      initialPayload = 'report.pdf';

      expect(await incoming.takeInitialDocuments(), isEmpty);
    });

    test('skips an entry without a usable path rather than losing the batch', () async {
      initialPayload = [
        {'name': 'no-path.pdf'},
        {'path': '', 'name': 'empty-path.pdf'},
        'not a map',
        {'path': '/cache/incoming/good.pdf', 'name': 'good.pdf'},
      ];

      final documents = await incoming.takeInitialDocuments();

      expect(documents, hasLength(1));
      expect(documents.single.displayName, 'good.pdf');
    });

    test('degrades to no document when the platform fails', () async {
      initialError = PlatformException(code: 'unreadable', message: 'could not be copied');

      expect(await incoming.takeInitialDocuments(), isEmpty);
    });

    test('degrades to no document where no platform side is registered', () async {
      messenger.setMockMethodCallHandler(methods, null);

      expect(await incoming.takeInitialDocuments(), isEmpty);
    });
  });

  group('documents', () {
    test('delivers a document that arrives while the app is already running', () async {
      final delivered = incoming.documents.first;

      emit([
        {'path': '/cache/incoming/later.pdf', 'name': 'later.pdf'},
      ]);

      final documents = await delivered;
      expect(documents, hasLength(1));
      expect(documents.single, isA<PdfFileSource>());
      expect(documents.single.path, '/cache/incoming/later.pdf');
    });

    test('delivers a batch of shared documents as one arrival', () async {
      final delivered = incoming.documents.first;

      emit([
        {'path': '/cache/incoming/a.pdf', 'name': 'a.pdf'},
        {'path': '/cache/incoming/b.pdf', 'name': 'b.pdf'},
      ]);

      expect([for (final document in await delivered) document.displayName], ['a.pdf', 'b.pdf']);
    });

    test('stays open for the next document after an unreadable one', () async {
      final delivered = incoming.documents.take(1).toList();

      emit('not a list');
      emit(const <Object?>[]);
      emit([
        {'path': '/cache/incoming/good.pdf', 'name': 'good.pdf'},
      ]);

      expect((await delivered).single.single.displayName, 'good.pdf');
    });

    test('stays open for the next document after a platform failure', () async {
      final delivered = incoming.documents.take(1).toList();

      emitError();
      emit([
        {'path': '/cache/incoming/good.pdf', 'name': 'good.pdf'},
      ]);

      expect((await delivered).single.single.displayName, 'good.pdf');
    });

    test('can be listened to more than once', () async {
      final first = incoming.documents.first;
      final second = incoming.documents.first;

      emit([
        {'path': '/cache/incoming/shared.pdf', 'name': 'shared.pdf'},
      ]);

      expect((await first).single.path, '/cache/incoming/shared.pdf');
      expect((await second).single.path, '/cache/incoming/shared.pdf');
    });
  });
}
