import 'dart:typed_data';

import 'package:pdf/pdf.dart' as pw_format;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../viewer/model/pdf_source.dart';
import '../model/page_plan_entry.dart';

/// Turns a page plan into PDF bytes, using PDFium through pdfrx.
///
/// The editor opens its own copies of the source documents so nothing it does
/// can disturb a document the viewer is showing. It owns every document it
/// opens; call [dispose] when the organiser closes.
class PdfPageEditor {
  PdfPageEditor({this.passwordProvider});

  /// Asked for a password when a source document turns out to be encrypted.
  final PdfPasswordProvider? passwordProvider;

  final _sources = <String, PdfDocument>{};
  final _blanks = <String, PdfDocument>{};
  var _nextEntryId = 0;

  /// Documents opened so far, keyed by [PdfSource.key].
  PdfDocument? documentFor(String sourceId) => _sources[sourceId];

  /// Opens [source] (once) and returns a plan entry per page.
  Future<List<SourcePageEntry>> addSource(PdfSource source) async {
    final document = _sources[source.key] ??= await _open(source);
    return [
      for (final page in document.pages)
        SourcePageEntry(
          id: _newEntryId(),
          sourceId: source.key,
          pageNumber: page.pageNumber,
        ),
    ];
  }

  Future<PdfDocument> _open(PdfSource source) => switch (source) {
    PdfFileSource(:final path) => PdfDocument.openFile(path, passwordProvider: passwordProvider),
    PdfDataSource(:final bytes, :final sourceId) => PdfDocument.openData(
      bytes,
      sourceName: sourceId,
      passwordProvider: passwordProvider,
    ),
  };

  /// A blank entry the size of the page at [index], or A4 if the plan is empty.
  BlankPageEntry newBlankEntry({required List<PagePlanEntry> plan, required int index}) {
    final neighbour = plan.isEmpty
        ? null
        : plan[index.clamp(0, plan.length - 1)];
    final size = neighbour == null ? null : _sizeOf(neighbour);
    return BlankPageEntry(
      id: _newEntryId(),
      width: size?.$1 ?? pw_format.PdfPageFormat.a4.width,
      height: size?.$2 ?? pw_format.PdfPageFormat.a4.height,
    );
  }

  /// Page size in points, as laid out (so a quarter-turned page is landscape).
  (double, double)? _sizeOf(PagePlanEntry entry) {
    final (width, height) = switch (entry) {
      BlankPageEntry(:final width, :final height) => (width, height),
      SourcePageEntry(:final sourceId, :final pageNumber) => () {
        final page = _pageOf(sourceId, pageNumber);
        return page == null ? (0.0, 0.0) : (page.width, page.height);
      }(),
    };
    if (width == 0 || height == 0) return null;
    return entry.quarterTurns.isEven ? (width, height) : (height, width);
  }

  PdfPage? _pageOf(String sourceId, int pageNumber) {
    final pages = _sources[sourceId]?.pages;
    if (pages == null || pageNumber < 1 || pageNumber > pages.length) return null;
    return pages[pageNumber - 1];
  }

  /// The page a plan entry renders as, rotation included.
  ///
  /// Returns null when the entry points at a document that is no longer open,
  /// which callers render as a placeholder rather than crashing.
  Future<PdfPage?> resolvePage(PagePlanEntry entry) async {
    final page = switch (entry) {
      SourcePageEntry(:final sourceId, :final pageNumber) => _pageOf(sourceId, pageNumber),
      BlankPageEntry() => (await _blankDocument(entry)).pages.first,
    };
    if (page == null) return null;
    return entry.quarterTurns == 0
        ? page
        : page.rotatedBy(PdfPageRotation.values[entry.quarterTurns]);
  }

  /// One generated blank document per page size, reused across entries.
  Future<PdfDocument> _blankDocument(BlankPageEntry entry) async {
    final cached = _blanks[entry.sizeKey];
    if (cached != null) return cached;

    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: pw_format.PdfPageFormat(entry.width, entry.height),
        build: (context) => pw.SizedBox.expand(),
      ),
    );
    return _blanks[entry.sizeKey] = await PdfDocument.openData(
      await document.save(),
      sourceName: 'blank-${entry.sizeKey}',
    );
  }

  /// Encodes [plan] into a PDF.
  ///
  /// Entries whose source document is gone are skipped; an empty result is an
  /// error because a PDF must have at least one page.
  Future<Uint8List> encode(List<PagePlanEntry> plan) async {
    final pages = <PdfPage>[];
    for (final entry in plan) {
      final page = await resolvePage(entry);
      if (page != null) pages.add(page);
    }
    if (pages.isEmpty) {
      throw StateError('A PDF needs at least one page.');
    }

    final output = await PdfDocument.createNew(sourceName: 'organized.pdf');
    try {
      // The source documents must stay alive until encoding finishes; they do,
      // because this editor owns them until it is disposed.
      output.pages = pages;
      return await output.encodePdf();
    } finally {
      await output.dispose();
    }
  }

  String _newEntryId() => 'entry-${_nextEntryId++}';

  Future<void> dispose() async {
    for (final document in [..._sources.values, ..._blanks.values]) {
      await document.dispose();
    }
    _sources.clear();
    _blanks.clear();
  }
}
