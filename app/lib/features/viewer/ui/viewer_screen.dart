import 'dart:async';

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
import '../../pages/services/pdf_saver.dart';
import '../../pages/ui/page_organizer_screen.dart';
import '../logic/page_layout.dart';
import '../logic/page_navigation.dart';
import '../logic/pdfrx_layout_adapter.dart';
import '../model/pdf_source.dart';
import '../model/reading_mode.dart';
import '../services/last_page_store.dart';
import '../services/pdf_picker.dart';
import 'empty_state.dart';
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
    this.saver = const PdfSaver(),
    this.annotationWriter = const PdfAnnotationWriter(),
    super.key,
  });

  final ViewPreferences preferences;

  /// Injected so widget tests can drive the screen without a native picker.
  final PdfPicker picker;

  /// Defaults to the on-device shared-preferences store.
  final LastPageStore? lastPageStore;

  /// Defaults to the on-device shared-preferences store.
  final AnnotationStore? annotationStore;

  /// Writes an exported PDF wherever the reader chooses.
  final PdfSaver saver;

  /// Turns the app's annotations into real PDF annotations.
  final PdfAnnotationWriter annotationWriter;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  final _searchTextController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final LastPageStore _lastPageStore =
      widget.lastPageStore ?? SharedPreferencesLastPageStore();

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
  bool _isOpening = false;
  bool _isExporting = false;
  bool _isSearchVisible = false;
  late ReadingMode _readingMode = widget.preferences.readingMode;

  int get _pageCount => _document?.pages.length ?? 0;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onPreferencesChanged);
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

    final path = saved.isScheme('file') ? saved.toFilePath() : null;
    _showMessage(
      'Saved ${_fileNameOf(saved)}',
      action: path == null
          ? null
          : SnackBarAction(
              label: 'Open',
              onPressed: () => _openSource(
                PdfFileSource(path: path, displayName: _fileNameOf(saved)),
              ),
            ),
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
            ),
          ),
        ],
      ),
    );
  }

  // --- annotations ---------------------------------------------------------

  Future<String?> _requestAnnotationText({required String title, required String? initialText}) =>
      showAnnotationTextDialog(context, title: title, initialText: initialText);

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

  /// Saves a copy of the document with the annotations written into it.
  ///
  /// The export opens its own copy of the PDF so the document on screen is
  /// never modified — the same rule the page organiser follows.
  Future<void> _exportAnnotations() async {
    final source = _source;
    if (source == null || _isExporting || !_annotations.hasAnnotations) return;
    setState(() => _isExporting = true);
    try {
      final document = await _openCopyOf(source);
      try {
        final result = await widget.annotationWriter.export(
          document,
          _annotations.annotations,
        );
        if (!mounted) return;
        final destination = await widget.saver.savePdf(
          bytes: result.bytes,
          suggestedName: _annotatedFileName(source.displayName),
        );
        if (!mounted || destination == null) return;
        _showMessage(
          result.skipped == 0
              ? 'Saved with ${result.written} '
                    '${result.written == 1 ? 'annotation' : 'annotations'}.'
              : 'Saved ${result.written} of ${result.total} annotations; '
                    '${result.skipped} could not be written.',
        );
      } finally {
        await document.dispose();
      }
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not export the annotations: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

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
          IconButton(
            tooltip: 'Organize pages',
            onPressed: source == null ? null : () => _organizePages(source),
            icon: const Icon(Icons.auto_awesome_motion_outlined),
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
          ? ViewerEmptyState(onOpenPressed: _openPdf, isOpening: _isOpening)
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
