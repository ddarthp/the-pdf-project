import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates the fixture PDF used by the viewer tests.
/// Run from `app/`:
///   dart run tool/generate_fixture_pdf.dart test/fixtures/sample.pdf
Future<void> main(List<String> args) async {
  final doc = pw.Document(title: 'The PDF Project sample');
  const bodies = [
    'Chapter one. The quick brown fox jumps over the lazy dog.',
    'Chapter two. Searching for haystack should match here.',
    'Chapter three. The end of the sample document.',
  ];
  for (var i = 0; i < bodies.length; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Page ${i + 1}', style: const pw.TextStyle(fontSize: 28)),
            pw.SizedBox(height: 16),
            pw.Text(bodies[i], style: const pw.TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
  await File(args.first).writeAsBytes(await doc.save());
  stdout.writeln('wrote ${args.first}');
}
