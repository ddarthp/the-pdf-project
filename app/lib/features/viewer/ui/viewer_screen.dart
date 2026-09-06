import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/app_theme.dart';
import '../../../core/view_preferences.dart';
import '../../annotate/annotation_controller.dart';
import '../../annotate/model/annotation.dart';
import '../../annotate/services/annotation_store.dart';
import '../../annotate/services/pdf_annotation_writer.dart';
import '../../annotate/ui/annotation_layer.dart';
import '../../annotate/ui/annotation_text_dialog.dart';
import '../../annotate/ui/annotation_toolbar.dart';
import '../../annotate/ui/annotations_panel.dart';
import '../../convert/ui/image_to_pdf_screen.dart';
import '../../scan/ui/scan_screen.dart';
import '../../forms/services/pdf_form_service.dart';
import '../../library/logic/recent_documents.dart';
import '../../library/model/recent_document.dart';
import '../../library/services/document_cache.dart';
import '../../library/services/recent_document_store.dart';
import '../../library/ui/recent_documents_view.dart';
import '../../forms/ui/form_fill_screen.dart';
import '../../share/services/pdf_export_service.dart';
import '../../share/ui/pdf_export_sheet.dart';
import '../../pages/ui/page_organizer_screen.dart';
import '../../signature/model/signature_source.dart';
import '../../signature/ui/signature_image_picker.dart';
import '../../signature/ui/signature_pad_sheet.dart';
import '../logic/page_layout.dart';
import '../logic/page_navigation.dart';
import '../logic/pdfrx_layout_adapter.dart';
import '../model/pdf_source.dart';
import '../model/reading_mode.dart';
import '../services/last_page_store.dart';
import '../services/pdf_picker.dart';
import 'jump_to_page_dialog.dart';
import 'load_error_banner.dart';
import 'outline_panel.dart';
import 'password_dialog.dart';
import 'search_bar_panel.dart';
import 'thumbnail_panel.dart';
import 'viewer_bottom_bar.dart';

/// The PDF reader: opens a document from the system picker and renders it with
/// navigation, outline, thumbnails and in-document search.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    required this.preferences,
    this.picker = const PdfPicker(),
    this.lastPageStore,
    this.annotationStore,
    this.exporter = const PdfExportService(),
    this.annotationWriter = const PdfAnnotationWriter(),
    this.signatureImagePicker = const SignatureImagePicker(),
    this.formService = const PdfFormService(),
    this.recentDocumentStore,
    this.documentCache = const DocumentCache(),
    super.key,
  });

  final ViewPreferences preferences;

  /// Injected so widget tests can drive the screen without a native picker.
  final PdfPicker picker;

  /// Defaults to the on-device shared-preferences store.
  final LastPageStore? lastPageStore;

  /// Defaults to the on-device shared-preferences store.
  final AnnotationStore? annotationStore;

  /// Sends a finished PDF to a file, the share sheet or a printer.
  final PdfExportService exporter;

  /// Turns the app's annotations into real PDF annotations.
  final PdfAnnotationWriter annotationWriter;

  /// Picks a photo or scan of a signature.
  final SignatureImagePicker signatureImagePicker;

  /// Reads and fills the document's form fields.
  final PdfFormService formService;

  /// Defaults to the on-device shared-preferences store.
  final RecentDocumentStore? recentDocumentStore;

  /// Keeps copies of documents that arrived without a file behind them.
  final DocumentCache documentCache;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  final _searchTextController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final LastPageStore _lastPageStore =
      widget.lastPageStore ?? SharedPreferencesLastPageStore();

  late final RecentDocumentStore _recentDocuments =
      widget.recentDocumentStore ?? SharedPreferencesRecentDocumentStore();

  late final AnnotationController _annotations = AnnotationController(
    store: widget.annotationStore ?? SharedPreferencesAnnotationStore(),
  )..addListener(_onAnnotationsChanged);

  /// Null until a document is loaded.
  ///
  /// [PdfTextSearcher] subscribes to the controller's document the moment it is
  /// constructed, so it cannot exist before the viewer is ready, and it has to
  /// be rebuilt for each document that gets opened.
  PdfTextSearcher? _searcher;

  PdfSource? _source;

  /// Built once per opened document so the password provider and the reload
  /// handle both survive rebuilds.
  PdfDocumentRef? _documentRef;

  PdfDocument? _document;
  int _pageNumber = 1;
  int _initialPageNumber = 1;
  int _passwordAttempts = 0;
  List<RecentDocument> _recents = const [];
  Set<String> _missingRecentPaths = const {};
  bool _isOpening = false;
  bool _isExporting = false;
  bool _isSearchVisible = false;
  late ReadingMode _readingMode = widget.preferences.readingMode;

  int get _pageCount => _document?.pages.length ?? 0;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onPreferencesChanged);
    unawaited(_loadRecents());
  }

  // --- the library ---------------------------------------------------------

  Future<void> _loadRecents() async {
    final documents = await _recentDocuments.load();
    // A document can be moved or deleted between sessions; checking once here
    // means the list can say so instead of failing when it is tapped.
    final missing = <String>{
      for (final document in documents)
        if (!File(document.path).existsSync()) document.path,
    };
    if (!mounted) return;
    setState(() {
      _recents = documents;
      _missingRecentPaths = missing;
    });
  }

  /// Records a document at the top of the recents list.
  ///
  /// Anything that falls off the end takes the app's own copy of it with it,
  /// so the list bounds the storage as well as itself.
  Future<void> _rememberOpened(PdfSource source, String path) async {
    final promoted = RecentDocuments.promote(
      _recents,
      RecentDocument(
        key: source.key,
        displayName: source.displayName,
        path: path,
        lastOpenedAt: DateTime.now(),
        pageCount: _recents
            .where((document) => document.key == source.key)
            .firstOrNull
            ?.pageCount,
      ),
    );
    for (final dropped in RecentDocuments.droppedPaths(_recents, promoted)) {
      await widget.documentCache.discard(dropped);
    }
    await _recentDocuments.save(promoted);
    if (!mounted) return;
    setState(() {
      _recents = promoted;
      _missingRecentPaths = _missingRecentPaths.difference({path});
    });
  }

  /// Fills in a document's page count once it is known.
  Future<void> _recordPageCount(String key, int pageCount) async {
    final updated = RecentDocuments.withPageCount(_recents, key, pageCount);
    if (listEquals(updated, _recents)) return;
    await _recentDocuments.save(updated);
    if (mounted) setState(() => _recents = updated);
  }

  Future<void> _forgetRecent(RecentDocument document) async {
    final remaining = RecentDocuments.remove(_recents, document.key);
    await widget.documentCache.discard(document.path);
    await _recentDocuments.save(remaining);
    if (mounted) setState(() => _recents = remaining);
  }

  /// Puts the library back on screen, leaving the document behind.
  void _closeDocument() {
    unawaited(_annotations.flush());
    _closeSearch();
    _disposeSearcher();
    _annotations.clear();
    setState(() {
      _source = null;
      _documentRef = null;
      _document = null;
    });
    unawaited(_loadRecents());
  }

  /// The toolbar and the page-navigation bar swap places when annotation mode
  /// is turned on, so the screen rebuilds with the annotation state.
  void _onAnnotationsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onPreferencesChanged);
    _annotations
      ..removeListener(_onAnnotationsChanged)
      ..dispose();
    _disposeSearcher();
    _searchTextController.dispose();
    super.dispose();
  }

  void _disposeSearcher() {
    _searcher
      ?..removeListener(_onSearcherChanged)
      ..dispose();
    _searcher = null;
  }

  void _onSearcherChanged() {
    if (mounted) setState(() {});
  }

  void _onPreferencesChanged() {
    if (!mounted) return;
    final mode = widget.preferences.readingMode;
    final modeChanged = mode != _readingMode;
    setState(() => _readingMode = mode);
    if (modeChanged) {
      // pdfrx keeps the computed page layout until something invalidates it,
      // and the scroll offset means nothing across layouts — so force a
      // re-layout and put the reader back on the page they were reading.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.isReady) return;
        _controller.invalidate();
        _controller.goToPage(pageNumber: _pageNumber);
      });
    }
  }

  // --- opening -------------------------------------------------------------

  Future<void> _openPdf() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    try {
      final source = await widget.picker.pickPdf();
      if (!mounted || source == null) return;
      await _openSource(source);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not open the PDF: $error');
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  Future<void> _openSource(PdfSource source) async {
    // A document picked as raw bytes has no file to come back to, so the app
    // keeps its own copy — that is what the recents entry points at.
    final path = switch (source) {
      PdfFileSource(:final path) => path,
      PdfDataSource(:final bytes) => await widget.documentCache.store(
        key: source.key,
        bytes: bytes,
        displayName: source.displayName,
      ),
    };
    if (!mounted) return;

    final resumePage = await _lastPageStore.lastPage(source.key);
    if (!mounted) return;
    // Writes any pending edits for the previous document before swapping.
    await _annotations.loadFor(source.key);
    if (!mounted) return;
    // Drop the previous document's searcher immediately: it is bound to a
    // document that is about to go away. onViewerReady builds a new one.
    _closeSearch();
    _disposeSearcher();
    setState(() {
      _source = source;
      _documentRef = _createDocumentRef(source);
      _document = null;
      _passwordAttempts = 0;
      _initialPageNumber = resumePage ?? 1;
      _pageNumber = _initialPageNumber;
    });
    await _rememberOpened(source, path);
  }

  PdfDocumentRef _createDocumentRef(PdfSource source) {
    Future<String?> askForPassword() => _requestPassword(source);
    return switch (source) {
      PdfFileSource(:final path) => PdfDocumentRefFile(path, passwordProvider: askForPassword),
      PdfDataSource(:final bytes, :final sourceId) => PdfDocumentRefData(
        bytes,
        sourceName: sourceId,
        passwordProvider: askForPassword,
      ),
    };
  }

  /// Called by pdfrx whenever PDFium rejects the password it was given.
  ///
  /// Returning null tells pdfrx to stop asking and report a load error, which
  /// [LoadErrorBanner] turns into a way back in.
  Future<String?> _requestPassword(PdfSource source) async {
    if (!mounted) return null;
    final isRetry = _passwordAttempts > 0;
    _passwordAttempts++;
    return showPdfPasswordDialog(
      context,
      fileName: source.displayName,
      isRetry: isRetry,
    );
  }

  /// Retries a document that failed to load — most often because its password
  /// was wrong or the prompt was dismissed.
  void _retryLoad() {
    _passwordAttempts = 0;
    _documentRef?.resolveListenable().load(forceReload: true);
  }

  void _runDocumentAction(_DocumentAction action, PdfSource source) {
    switch (action) {
      case _DocumentAction.shareOrPrint:
        unawaited(_sendCurrentDocument(source));
      case _DocumentAction.organizePages:
        unawaited(_organizePages(source));
      case _DocumentAction.fillForm:
        unawaited(_fillForm(source));
    }
  }

  /// Makes a new PDF out of pictures.
  ///
  /// Started from the library rather than from a document, because it makes
  /// one rather than changing one.
  Future<void> _makePdfFromImages() => _startNewDocument(const ImageToPdfScreen());

  /// Runs a screen that makes a document out of nothing, and reports where the
  /// result went.
  Future<void> _startNewDocument(Widget screen) async {
    final saved = await Navigator.of(context).push<Uri>(
      MaterialPageRoute(builder: (context) => screen),
    );
    if (!mounted || saved == null) return;
    _announceSavedCopy(saved);
    unawaited(_loadRecents());
  }

  /// Scans a new document with the camera.
  Future<void> _scanDocument() => _startNewDocument(const ScanScreen());

  /// Opens the form filler on a copy of the current document.
  ///
  /// Whether a PDF has fields is only known once it has been read, so the
  /// screen is always offered and says so when there is nothing to fill.
  Future<void> _fillForm(PdfSource source) async {
    final saved = await Navigator.of(context).push<Uri>(
      MaterialPageRoute(
        builder: (context) => FormFillScreen(source: source, service: widget.formService),
      ),
    );
    if (!mounted || saved == null) return;
    _announceSavedCopy(saved);
  }

  /// Opens the page organiser on a copy of the current document.
  ///
  /// The organiser never edits the document the viewer is showing; it saves a
  /// new file, which the viewer then offers to open.
  Future<void> _organizePages(PdfSource source) async {
    final saved = await Navigator.of(context).push<Uri>(
      MaterialPageRoute(
        builder: (context) => PageOrganizerScreen(source: source, picker: widget.picker),
      ),
    );
    if (!mounted || saved == null) return;
    _announceSavedCopy(saved);
  }

  /// Reports where a saved copy went, offering to open it when it landed
  /// somewhere the app can read back.
  void _announceSavedCopy(Uri saved) {
    _showMessage('Saved ${_fileNameOf(saved)}', action: _openAction(saved));
  }

  /// An "Open" button for a file the app can read back, or nothing for a
  /// destination it cannot — a share sheet never says where a document went.
  SnackBarAction? _openAction(Uri? saved) {
    if (saved == null || !saved.isScheme('file')) return null;
    final path = saved.toFilePath();
    return SnackBarAction(
      label: 'Open',
      onPressed: () =>
          _openSource(PdfFileSource(path: path, displayName: _fileNameOf(saved))),
    );
  }

  static String _fileNameOf(Uri uri) =>
      uri.pathSegments.isEmpty ? uri.toString() : uri.pathSegments.last;

  void _showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), action: action),
    );
  }

  // --- navigation ----------------------------------------------------------

  void _goToPage(int pageNumber) {
    if (!_controller.isReady) return;
    _controller.goToPage(pageNumber: PageNavigation.clamp(pageNumber, _pageCount));
  }

  Future<void> _promptJumpToPage() async {
    if (_pageCount == 0) return;
    final page = await showJumpToPageDialog(
      context,
      pageCount: _pageCount,
      currentPage: _pageNumber,
    );
    if (page != null) _goToPage(page);
  }

  void _goTo(Matrix4? matrix) {
    if (matrix != null) _controller.goTo(matrix);
  }

  void _fitWidth() {
    if (!_controller.isReady) return;
    _goTo(_controller.calcMatrixFitWidthForPage(pageNumber: _pageNumber));
  }

  void _fitHeight() {
    if (!_controller.isReady) return;
    _goTo(_controller.calcMatrixFitHeightForPage(pageNumber: _pageNumber));
  }

  void _fitPage() {
    if (!_controller.isReady) return;
    _goTo(_controller.calcMatrixForFit(pageNumber: _pageNumber));
  }

  /// In single-page mode a drag should land on a page, not between two.
  ///
  /// Only snaps while the page still fits the viewport: once the reader has
  /// zoomed in, panning within a page must not yank the view around.
  void _snapToNearestPage(ScaleEndDetails details) {
    if (_readingMode != ReadingMode.singlePage || !_controller.isReady) return;
    final rects = _controller.layout.pageLayouts;
    if (rects.isEmpty) return;
    final visible = _controller.visibleRect;
    final target = PageLayouts.pageNumberForOffset(centerX: visible.center.dx, pageRects: rects);
    if (visible.width < rects[target - 1].width * 0.9) return;
    _controller.goToPage(pageNumber: target);
  }

  // --- search --------------------------------------------------------------

  void _onSearchTextChanged(String text) {
    final searcher = _searcher;
    if (searcher == null) return;
    if (text.isEmpty) {
      searcher.resetTextSearch();
    } else {
      searcher.startTextSearch(text);
    }
    setState(() {});
  }

  void _toggleSearch() {
    if (_isSearchVisible) {
      _closeSearch();
    } else {
      setState(() => _isSearchVisible = true);
    }
  }

  void _closeSearch() {
    _searchTextController.clear();
    _searcher?.resetTextSearch();
    if (mounted) setState(() => _isSearchVisible = false);
  }

  // --- rendering -----------------------------------------------------------

  /// Inverts page content in place for night reading. Drawn before the search
  /// highlight callback so matches keep their real colour.
  void _paintNightMode(Canvas canvas, Rect pageRect, PdfPage page) {
    canvas.drawRect(
      pageRect,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..blendMode = BlendMode.difference,
    );
  }

  PdfViewerParams _buildParams(BuildContext context) {
    return PdfViewerParams(
      backgroundColor: AppTheme.viewerBackground(context),
      layoutPages: PdfrxLayoutAdapter.functionFor(_readingMode),
      pageAnchor: _readingMode == ReadingMode.singlePage
          ? PdfPageAnchor.all
          : PdfPageAnchor.top,
      onInteractionEnd: _snapToNearestPage,
      pagePaintCallbacks: [
        if (widget.preferences.invertPages) _paintNightMode,
        if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
      ],
      errorBannerBuilder: (context, error, stackTrace, documentRef) => LoadErrorBanner(
        error: error,
        onRetry: _retryLoad,
        onOpenAnother: _openPdf,
      ),
      onViewerReady: (document, controller) {
        if (!mounted) return;
        _disposeSearcher();
        setState(() {
          _document = document;
          _pageNumber = controller.pageNumber ?? 1;
          _searcher = PdfTextSearcher(controller)..addListener(_onSearcherChanged);
        });
        final source = _source;
        if (source != null) {
          unawaited(_recordPageCount(source.key, document.pages.length));
        }
      },
      onPageChanged: (pageNumber) {
        if (!mounted || pageNumber == null) return;
        setState(() => _pageNumber = pageNumber);
        _rememberCurrentPage();
      },
    );
  }

  void _rememberCurrentPage() {
    final source = _source;
    if (source == null || _document == null) return;
    _lastPageStore.saveLastPage(source.key, _pageNumber);
  }

  Widget _buildViewer(PdfDocumentRef documentRef) {
    final rotation = widget.preferences.viewRotation;
    // pdfrx has no view-rotation parameter (only per-page `rotationOverride`
    // on PdfPageView), so rotate the whole viewer instead. RotatedBox hands
    // the viewer a viewport with width and height swapped and rotates its hit
    // testing with it, which is exactly the semantics of a rotated view — and
    // it leaves the document itself untouched.
    return RotatedBox(
      quarterTurns: rotation.quarterTurns,
      child: Stack(
        children: [
          PdfViewer(
            documentRef,
            key: ValueKey(documentRef.key),
            controller: _controller,
            params: _buildParams(context),
            initialPageNumber: _initialPageNumber,
          ),
          // Inside the RotatedBox so the layer shares the viewer's coordinate
          // space; it ignores pointers unless a tool needs them.
          Positioned.fill(
            child: AnnotationLayer(
              controller: _annotations,
              viewer: _controller,
              requestText: _requestAnnotationText,
              requestSignature: _requestSignature,
            ),
          ),
        ],
      ),
    );
  }

  // --- annotations ---------------------------------------------------------

  Future<String?> _requestAnnotationText({required String title, required String? initialText}) =>
      showAnnotationTextDialog(context, title: title, initialText: initialText);

  Future<SignatureSource?> _requestSignature() => showSignaturePad(
    context,
    color: _annotations.style.color,
    picker: widget.signatureImagePicker,
  );

  /// Re-opens the text of a note or text box and writes the edit back.
  Future<void> _editAnnotationText(Annotation annotation) async {
    final existing = switch (annotation) {
      StickyNoteAnnotation(:final text) => text,
      TextBoxAnnotation(:final text) => text,
      _ => null,
    };
    if (existing == null) return;

    final text = await _requestAnnotationText(
      title: annotation is StickyNoteAnnotation ? 'Sticky note' : 'Text box',
      initialText: existing,
    );
    if (!mounted || text == null) return;
    if (text.isEmpty) {
      _annotations.remove(annotation.id);
      return;
    }
    _annotations.replace(switch (annotation) {
      StickyNoteAnnotation() => annotation.withText(text),
      TextBoxAnnotation() => annotation.withText(text),
      _ => annotation,
    });
  }

  /// Sends a copy of the document with the annotations written into it.
  ///
  /// The export opens its own copy of the PDF so the document on screen is
  /// never modified — the same rule the page organiser follows.
  Future<void> _exportAnnotations() async {
    final source = _source;
    if (source == null || _isExporting || !_annotations.hasAnnotations) return;
    setState(() => _isExporting = true);
    try {
      final document = await _openCopyOf(source);
      final PdfAnnotationExport result;
      try {
        result = await widget.annotationWriter.export(document, _annotations.annotations);
      } finally {
        await document.dispose();
      }
      if (!mounted) return;

      await _sendPdf(
        bytes: result.bytes,
        fileName: _annotatedFileName(source.displayName),
        note: result.skipped == 0
            ? '${result.written} ${result.written == 1 ? 'annotation' : 'annotations'}'
            : '${result.written} of ${result.total} annotations; '
                  '${result.skipped} could not be written',
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not export the annotations: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Shares, prints or saves the document on screen.
  ///
  /// Annotations are part of what is on screen, so a document that has any is
  /// sent with them written in — and the sheet says so rather than quietly
  /// sending something different from what the reader is looking at.
  Future<void> _sendCurrentDocument(PdfSource source) async {
    if (_isExporting) return;
    if (_annotations.hasAnnotations) {
      await _exportAnnotations();
      return;
    }

    setState(() => _isExporting = true);
    try {
      await _sendPdf(bytes: await _bytesOf(source), fileName: source.displayName);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not share this PDF: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Asks where a finished PDF should go, then sends it there.
  Future<void> _sendPdf({
    required Uint8List bytes,
    required String fileName,
    String? note,
  }) async {
    final destination = await showPdfExportSheet(context, fileName: fileName, note: note);
    if (!mounted || destination == null) return;

    final result = await widget.exporter.run(
      destination,
      bytes: bytes,
      fileName: fileName,
      // On a tablet the share sheet opens as a popover; point it at the
      // viewer rather than the corner of the screen.
      originBounds: _shareOrigin(),
    );
    if (!mounted) return;
    final message = result.message;
    if (message != null) {
      _showMessage(
        message,
        action: _openAction(result.savedTo),
      );
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The document's own bytes, for sharing it as it stands on disk.
  Future<Uint8List> _bytesOf(PdfSource source) => switch (source) {
    PdfFileSource(:final path) => File(path).readAsBytes(),
    PdfDataSource(:final bytes) => Future.value(bytes),
  };

  Future<PdfDocument> _openCopyOf(PdfSource source) => switch (source) {
    PdfFileSource(:final path) => PdfDocument.openFile(
      path,
      passwordProvider: () => _requestPassword(source),
    ),
    PdfDataSource(:final bytes, :final sourceId) => PdfDocument.openData(
      bytes,
      sourceName: 'export-$sourceId',
      passwordProvider: () => _requestPassword(source),
    ),
  };

  static String _annotatedFileName(String name) {
    final base = name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
    return '$base-annotated.pdf';
  }

  /// Takes the reader to an annotation and selects it.
  void _goToAnnotation(Annotation annotation) {
    _goToPage(annotation.pageNumber);
    _annotations
      ..isEnabled = true
      ..select(annotation.id);
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final documentRef = _documentRef;
    final document = _document;
    final preferences = widget.preferences;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          source?.displayName ?? 'The PDF Project',
          overflow: TextOverflow.ellipsis,
        ),
        leading: document == null
            ? null
            : IconButton(
                tooltip: 'Outline and thumbnails',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        actions: [
          if (source != null)
            IconButton(
              tooltip: 'Recent files',
              onPressed: _closeDocument,
              icon: const Icon(Icons.history),
            ),
          IconButton(
            tooltip: 'Find in document',
            onPressed: _searcher == null ? null : _toggleSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: _annotations.isEnabled ? 'Hide annotation tools' : 'Annotate',
            isSelected: _annotations.isEnabled,
            onPressed: document == null
                ? null
                : () => _annotations.isEnabled = !_annotations.isEnabled,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<_DocumentAction>(
            tooltip: 'Document actions',
            icon: const Icon(Icons.edit_document),
            enabled: source != null,
            onSelected: (action) => _runDocumentAction(action, source!),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _DocumentAction.shareOrPrint,
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Share or print…'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _DocumentAction.organizePages,
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_motion_outlined),
                  title: Text('Organize pages…'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _DocumentAction.fillForm,
                child: ListTile(
                  leading: Icon(Icons.checklist_outlined),
                  title: Text('Fill form…'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Open PDF',
            onPressed: _isOpening ? null : _openPdf,
            icon: const Icon(Icons.folder_open),
          ),
          _ViewMenu(preferences: preferences),
        ],
        bottom: _isSearchVisible && _searcher != null
            ? SearchBarPanel(
                textController: _searchTextController,
                searcher: _searcher!,
                onChanged: _onSearchTextChanged,
                onClose: _closeSearch,
              )
            : null,
      ),
      drawer: document == null ? null : _buildSidePanel(document),
      body: documentRef == null
          ? RecentDocumentsView(
              documents: _recents,
              missingPaths: _missingRecentPaths,
              isOpening: _isOpening,
              onOpenPressed: _openPdf,
              onImagesPressed: () => unawaited(_makePdfFromImages()),
              onScanPressed: () => unawaited(_scanDocument()),
              onDocumentSelected: (document) => unawaited(
                _openSource(
                  PdfFileSource(path: document.path, displayName: document.displayName),
                ),
              ),
              onDocumentRemoved: (document) => unawaited(_forgetRecent(document)),
            )
          : _buildViewer(documentRef),
      bottomNavigationBar: document == null
          ? null
          : _annotations.isEnabled
          ? AnnotationToolbar(
              controller: _annotations,
              onClose: () => _annotations.isEnabled = false,
              onEditSelectedText: () {
                final selected = _annotations.selected;
                if (selected != null) unawaited(_editAnnotationText(selected));
              },
              onExport: () => unawaited(_exportAnnotations()),
            )
          : ViewerBottomBar(
              pageNumber: _pageNumber,
              pageCount: _pageCount,
              onFirst: () => _goToPage(1),
              onPrevious: () => _goToPage(_pageNumber - 1),
              onNext: () => _goToPage(_pageNumber + 1),
              onLast: () => _goToPage(_pageCount),
              onJumpToPage: _promptJumpToPage,
              onZoomIn: () => _controller.zoomUp(),
              onZoomOut: () => _controller.zoomDown(),
              onFitWidth: _fitWidth,
              onFitHeight: _fitHeight,
              onFitPage: _fitPage,
            ),
    );
  }

  Widget _buildSidePanel(PdfDocument document) {
    return Drawer(
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const SafeArea(
              bottom: false,
              child: TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.grid_view), text: 'Pages'),
                  Tab(icon: Icon(Icons.list), text: 'Outline'),
                  Tab(icon: Icon(Icons.comment_outlined), text: 'Notes'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ThumbnailPanel(
                    document: document,
                    currentPage: _pageNumber,
                    onSelect: (pageNumber) {
                      Navigator.of(context).pop();
                      _goToPage(pageNumber);
                    },
                  ),
                  OutlinePanel(
                    document: document,
                    onSelect: (dest) {
                      Navigator.of(context).pop();
                      _controller.goToDest(dest);
                    },
                  ),
                  AnnotationsPanel(
                    controller: _annotations,
                    onSelect: (annotation) {
                      Navigator.of(context).pop();
                      _goToAnnotation(annotation);
                    },
                    onEditText: (annotation) {
                      Navigator.of(context).pop();
                      unawaited(_editAnnotationText(annotation));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Actions that change the document itself, rather than how it is shown.
enum _DocumentAction { shareOrPrint, organizePages, fillForm }

/// Reading mode, rotation, night mode and app theme, in one overflow menu.
class _ViewMenu extends StatelessWidget {
  const _ViewMenu({required this.preferences});

  final ViewPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'View options',
      icon: const Icon(Icons.tune),
      itemBuilder: (context) => [
        const PopupMenuItem<void>(enabled: false, child: Text('Reading mode')),
        for (final mode in ReadingMode.values)
          PopupMenuItem<void>(
            onTap: () => preferences.readingMode = mode,
            child: _MenuRow(
              icon: preferences.readingMode == mode
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              label: mode.label,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: preferences.rotateClockwise,
          child: _MenuRow(
            icon: Icons.rotate_90_degrees_cw_outlined,
            label: 'Rotate view (${preferences.viewRotation.label})',
          ),
        ),
        PopupMenuItem<void>(
          onTap: () => preferences.invertPages = !preferences.invertPages,
          child: _MenuRow(
            icon: preferences.invertPages ? Icons.check_box : Icons.check_box_outline_blank,
            label: 'Night mode (invert pages)',
          ),
        ),
        PopupMenuItem<void>(
          onTap: preferences.cycleThemeMode,
          child: _MenuRow(
            icon: Icons.brightness_6_outlined,
            label: 'Theme: ${_themeLabel(preferences.themeMode)}',
          ),
        ),
      ],
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
