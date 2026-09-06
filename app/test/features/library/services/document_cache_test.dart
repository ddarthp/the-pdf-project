import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/library/services/document_cache.dart';

void main() {
  late Directory directory;
  late DocumentCache cache;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('library_cache');
    cache = DocumentCache(directoryProvider: () async => directory);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  final bytes = Uint8List.fromList('%PDF-1.7 hello'.codeUnits);

  test('keeps a copy that can be read back', () async {
    final path = await cache.store(key: 'content://doc/1', bytes: bytes, displayName: 'report.pdf');

    expect(File(path).readAsBytesSync(), bytes);
    expect(path, startsWith(directory.path));
  });

  test('reopening the same document overwrites its copy rather than adding one', () async {
    final first = await cache.store(
      key: 'content://doc/1',
      bytes: bytes,
      displayName: 'report.pdf',
    );
    final second = await cache.store(
      key: 'content://doc/1',
      bytes: Uint8List.fromList('%PDF-1.7 newer'.codeUnits),
      displayName: 'report.pdf',
    );

    expect(second, first);
    expect(directory.listSync(), hasLength(1));
    expect(File(second).readAsStringSync(), endsWith('newer'));
  });

  test('different documents get different copies', () async {
    final a = await cache.store(key: 'content://doc/1', bytes: bytes, displayName: 'a.pdf');
    final b = await cache.store(key: 'content://doc/2', bytes: bytes, displayName: 'a.pdf');

    expect(a, isNot(b));
    expect(directory.listSync(), hasLength(2));
  });

  test('creates its folder if it is not there yet', () async {
    directory.deleteSync(recursive: true);

    final path = await cache.store(key: 'k', bytes: bytes, displayName: 'a.pdf');

    expect(File(path).existsSync(), isTrue);
  });

  group('discard', () {
    test('removes a copy the library kept', () async {
      final path = await cache.store(key: 'k', bytes: bytes, displayName: 'a.pdf');

      await cache.discard(path);

      expect(File(path).existsSync(), isFalse);
    });

    test('never touches a file outside the app\'s own folder', () async {
      final elsewhere = File('${Directory.systemTemp.path}/someones-own-document.pdf')
        ..writeAsBytesSync(bytes);
      addTearDown(() => elsewhere.existsSync() ? elsewhere.deleteSync() : null);

      await cache.discard(elsewhere.path);

      expect(
        elsewhere.existsSync(),
        isTrue,
        reason: 'dropping off the recents list must not delete the reader\'s own file',
      );
    });

    test('shrugs off a copy that is already gone', () async {
      await cache.discard('${directory.path}/never-existed.pdf');
    });
  });

  group('fileNameFor', () {
    test('is stable for the same document', () {
      expect(
        DocumentCache.fileNameFor('content://doc/1', 'report.pdf'),
        DocumentCache.fileNameFor('content://doc/1', 'report.pdf'),
      );
    });

    test('keeps a readable part so the folder makes sense to a person', () {
      expect(DocumentCache.fileNameFor('k', 'Annual report.pdf'), endsWith('-Annual_report.pdf'));
    });

    test('strips characters a file name cannot hold', () {
      final name = DocumentCache.fileNameFor('k', 'a/b:c*d.pdf');

      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, endsWith('.pdf'));
    });

    test('does not run away with a very long name', () {
      final name = DocumentCache.fileNameFor('k', '${'x' * 300}.pdf');

      expect(name.length, lessThan(80));
    });
  });
}
