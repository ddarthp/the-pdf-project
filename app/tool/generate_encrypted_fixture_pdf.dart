import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Generates the password-protected fixture used by the viewer tests.
///
/// Run from `app/`:
///   dart run tool/generate_encrypted_fixture_pdf.dart test/fixtures/encrypted.pdf
///
/// The `pdf` package exposes only an abstract `PdfEncryption` hook and keeps
/// the dictionary primitives needed to fill in an /Encrypt dictionary behind
/// `src/`, so this writes the file directly instead of reaching into another
/// package's internals. The security handler is the PDF standard one,
/// revision 3 (128-bit RC4), per PDF 1.7 §7.6.3 algorithms 3.1–3.5.
///
/// Output is byte-for-byte reproducible: the document ID is fixed rather than
/// random, so regenerating the fixture does not churn the repository.
const userPassword = 'letmein';
const ownerPassword = 'ownersecret';

/// Permission bits: everything allowed. Bits 1–2 are reserved and must be 0,
/// which is why this is -4 rather than -1.
const permissions = -4;

const keyLength = 16; // 128-bit

/// Fixed file identifier, used both in the trailer /ID and in the key
/// derivation below.
final documentId = Uint8List.fromList(
  List<int>.generate(16, (i) => (i * 37 + 11) & 0xff),
);

/// The 32-byte padding string from the PDF specification.
const padding = <int>[
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
];

Uint8List padPassword(String password) {
  final bytes = <int>[...password.codeUnits];
  if (bytes.length > 32) return Uint8List.fromList(bytes.sublist(0, 32));
  return Uint8List.fromList([...bytes, ...padding.take(32 - bytes.length)]);
}

Uint8List rc4(List<int> key, List<int> data) {
  final s = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xff;
    final tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
  }
  final out = Uint8List(data.length);
  var i = 0;
  j = 0;
  for (var k = 0; k < data.length; k++) {
    i = (i + 1) & 0xff;
    j = (j + s[i]) & 0xff;
    final tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
    out[k] = data[k] ^ s[(s[i] + s[j]) & 0xff];
  }
  return out;
}

Uint8List md5Of(List<int> input) => Uint8List.fromList(md5.convert(input).bytes);

List<int> xorKey(List<int> key, int value) => [for (final b in key) b ^ value];

/// Algorithm 3.3: the /O entry.
Uint8List computeOwnerValue() {
  var hash = md5Of(padPassword(ownerPassword.isEmpty ? userPassword : ownerPassword));
  for (var i = 0; i < 50; i++) {
    hash = md5Of(hash);
  }
  final rc4Key = hash.sublist(0, keyLength);
  var owner = rc4(rc4Key, padPassword(userPassword));
  for (var i = 1; i <= 19; i++) {
    owner = rc4(xorKey(rc4Key, i), owner);
  }
  return owner;
}

/// Algorithm 3.2: the file encryption key.
Uint8List computeEncryptionKey(Uint8List ownerValue) {
  final p = permissions & 0xffffffff;
  var hash = md5Of([
    ...padPassword(userPassword),
    ...ownerValue,
    p & 0xff,
    (p >> 8) & 0xff,
    (p >> 16) & 0xff,
    (p >> 24) & 0xff,
    ...documentId,
  ]);
  for (var i = 0; i < 50; i++) {
    hash = md5Of(hash.sublist(0, keyLength));
  }
  return hash.sublist(0, keyLength);
}

/// Algorithm 3.5: the /U entry.
Uint8List computeUserValue(Uint8List key) {
  var user = rc4(key, md5Of([...padding, ...documentId]));
  for (var i = 1; i <= 19; i++) {
    user = rc4(xorKey(key, i), user);
  }
  // The trailing 16 bytes are arbitrary padding per the specification.
  return Uint8List.fromList([...user, ...List<int>.filled(16, 0)]);
}

/// Algorithm 3.1: the per-object key.
Uint8List objectKey(Uint8List key, int objectNumber, int generation) {
  final hash = md5Of([
    ...key,
    objectNumber & 0xff,
    (objectNumber >> 8) & 0xff,
    (objectNumber >> 16) & 0xff,
    generation & 0xff,
    (generation >> 8) & 0xff,
  ]);
  return hash.sublist(0, keyLength + 5 > 16 ? 16 : keyLength + 5);
}

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/generate_encrypted_fixture_pdf.dart <output.pdf>');
    exitCode = 64;
    return;
  }

  final ownerValue = computeOwnerValue();
  final key = computeEncryptionKey(ownerValue);
  final userValue = computeUserValue(key);

  const content =
      'BT /F1 28 Tf 72 720 Td (Locked document) Tj ET\n'
      'BT /F1 14 Tf 72 680 Td (The password for this fixture is letmein.) Tj ET\n';
  final encryptedContent = rc4(objectKey(key, 4, 0), content.codeUnits);

  // Object 0 is the free-list head; objects 1..6 follow in order.
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '', // object 4 is the content stream, written as raw bytes below
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Filter /Standard /V 2 /R 3 /Length ${keyLength * 8} '
        '/O <${hex(ownerValue)}> /U <${hex(userValue)}> /P $permissions >>',
  ];

  final out = BytesBuilder();
  final offsets = <int>[];
  out.add('%PDF-1.4\n'.codeUnits);
  // A binary comment marks the file as containing binary data.
  out.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

  for (var i = 0; i < objects.length; i++) {
    final number = i + 1;
    offsets.add(out.length);
    if (number == 4) {
      out.add('4 0 obj\n<< /Length ${encryptedContent.length} >>\nstream\n'.codeUnits);
      out.add(encryptedContent);
      out.add('\nendstream\nendobj\n'.codeUnits);
    } else {
      out.add('$number 0 obj\n${objects[i]}\nendobj\n'.codeUnits);
    }
  }

  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Encrypt 6 0 R ')
    ..write('/ID [<${hex(documentId)}> <${hex(documentId)}>] >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  out.add(buffer.toString().codeUnits);

  await File(args.first).writeAsBytes(out.takeBytes());
  stdout.writeln('wrote ${args.first} (user password: $userPassword)');
}
