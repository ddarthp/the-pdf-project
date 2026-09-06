import 'dart:io';

/// Generates the AcroForm fixture used by the forms tests.
///
/// Run from `app/`:
///   dart run tool/generate_form_fixture_pdf.dart test/fixtures/form.pdf
///
/// Written by hand rather than with the `pdf` package, which has no radio
/// groups: a radio group is one parent field with several widget kids, each
/// with its own on-state name, and that shape is exactly what the fixture
/// needs to exercise. `/NeedAppearances` is deliberately left out, so the
/// tests measure what the app's own filling produces rather than what a
/// reader would regenerate anyway.
///
/// Output is byte-for-byte reproducible.
const textFieldName = 'full_name';
const checkboxName = 'subscribe';
const radioGroupName = 'plan';
const radioOnStates = ['Basic', 'Pro'];
const comboName = 'country';
const comboOptions = ['United Kingdom', 'Germany', 'Japan'];

/// A widget's appearance for its off and on states. Shared by the checkbox and
/// both radio buttons, which is legal and keeps the file small.
const offAppearance = '0.5 w 0 0 0 RG 1 1 16 16 re S\n';
const onAppearance = '0.5 w 0 0 0 RG 1 1 16 16 re S 0 0 0 rg 5 5 8 8 re f\n';

const pageLabels = '''
BT /F1 18 Tf 72 780 Td (Membership form) Tj ET
BT /F1 11 Tf 72 730 Td (Full name) Tj ET
BT /F1 11 Tf 96 664 Td (Subscribe to updates) Tj ET
BT /F1 11 Tf 96 624 Td (Basic) Tj ET
BT /F1 11 Tf 156 624 Td (Pro) Tj ET
BT /F1 11 Tf 72 610 Td (Country) Tj ET
''';

String dict(String body) => '<< $body >>';

String formXObject(String content) =>
    '<< /Type /XObject /Subtype /Form /BBox [0 0 18 18] /Resources << >> '
    '/Length ${content.length} >>\nstream\n$content\nendstream';

String stream(String content) => '<< /Length ${content.length} >>\nstream\n$content\nendstream';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/generate_form_fixture_pdf.dart <output.pdf>');
    exitCode = 64;
    return;
  }

  // Object numbers, in the order they are written below.
  const catalog = 1;
  const pages = 2;
  const page = 3;
  const helvetica = 4;
  const textField = 5;
  const checkbox = 6;
  const radioGroup = 7;
  const radioBasic = 8;
  const radioPro = 9;
  const combo = 10;
  const zapfDingbats = 11;
  const contents = 12;
  const offState = 13;
  const onState = 14;

  /// Radio flag is bit 16, combo flag is bit 18 of the field flags.
  const radioFlags = 1 << 15;
  const comboFlags = 1 << 17;

  final objects = <String>[
    // 1: catalog, carrying the form definition
    dict(
      '/Type /Catalog /Pages $pages 0 R '
      '/AcroForm << /Fields [$textField 0 R $checkbox 0 R $radioGroup 0 R $combo 0 R] '
      '/DA (/Helv 0 Tf 0 g) '
      '/DR << /Font << /Helv $helvetica 0 R /ZaDb $zapfDingbats 0 R >> >> >>',
    ),
    // 2: page tree
    dict('/Type /Pages /Kids [$page 0 R] /Count 1'),
    // 3: the page, listing every widget that appears on it
    dict(
      '/Type /Page /Parent $pages 0 R /MediaBox [0 0 595 842] '
      '/Resources << /Font << /F1 $helvetica 0 R >> >> /Contents $contents 0 R '
      '/Annots [$textField 0 R $checkbox 0 R $radioBasic 0 R $radioPro 0 R $combo 0 R]',
    ),
    // 4: the form's text font
    dict('/Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding'),
    // 5: text field
    dict(
      '/Type /Annot /Subtype /Widget /FT /Tx /T ($textFieldName) /V () '
      '/DA (/Helv 12 Tf 0 g) /Rect [72 700 372 724] /F 4 /P $page 0 R',
    ),
    // 6: checkbox
    dict(
      '/Type /Annot /Subtype /Widget /FT /Btn /T ($checkboxName) /V /Off /AS /Off '
      '/AP << /N << /Off $offState 0 R /Yes $onState 0 R >> >> '
      '/DA (/ZaDb 0 Tf 0 g) /Rect [72 660 90 678] /F 4 /P $page 0 R',
    ),
    // 7: radio group — a field with no widget of its own, only kids
    dict(
      '/FT /Btn /Ff $radioFlags /T ($radioGroupName) /V /Off '
      '/Kids [$radioBasic 0 R $radioPro 0 R]',
    ),
    // 8, 9: the radio buttons, each with its own on-state name
    dict(
      '/Type /Annot /Subtype /Widget /Parent $radioGroup 0 R /AS /Off '
      '/AP << /N << /Off $offState 0 R /${radioOnStates[0]} $onState 0 R >> >> '
      '/Rect [72 620 90 638] /F 4 /P $page 0 R',
    ),
    dict(
      '/Type /Annot /Subtype /Widget /Parent $radioGroup 0 R /AS /Off '
      '/AP << /N << /Off $offState 0 R /${radioOnStates[1]} $onState 0 R >> >> '
      '/Rect [132 620 150 638] /F 4 /P $page 0 R',
    ),
    // 10: combo box
    dict(
      '/Type /Annot /Subtype /Widget /FT /Ch /Ff $comboFlags /T ($comboName) /V () '
      '/Opt [${comboOptions.map((option) => '($option)').join(' ')}] '
      '/DA (/Helv 12 Tf 0 g) /Rect [72 570 272 594] /F 4 /P $page 0 R',
    ),
    // 11: the font checkbox glyphs are drawn from
    dict('/Type /Font /Subtype /Type1 /BaseFont /ZapfDingbats'),
    // 12: page content — the labels beside each field
    stream(pageLabels),
    // 13, 14: shared off and on appearances for the checkbox and radios
    formXObject(offAppearance),
    formXObject(onAppearance),
  ];

  final out = StringBuffer();
  final offsets = <int>[];
  out.write('%PDF-1.7\n%âãÏÓ\n');
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }

  final xrefOffset = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out
    ..write('trailer\n<< /Size ${objects.length + 1} /Root $catalog 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');

  await File(args.first).writeAsString(out.toString(), flush: true);
  stdout.writeln('wrote ${args.first}');
}
