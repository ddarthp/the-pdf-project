import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/app_theme.dart';
import '../../../core/view_preferences.dart';
import '../logic/page_layout.dart';
import '../logic/page_navigation.dart';
import '../logic/pdfrx_layout_adapter.dart';
import '../model/pdf_source.dart';
import '../model/reading_mode.dart';
import '../services/pdf_picker.dart';
import 'empty_state.dart';
import 'jump_to_page_dialog.dart';
import 'outline_panel.dart';
import 'search_bar_panel.dart';
import 'thumbnail_panel.dart';
import 'viewer_bottom_bar.dart';

/// The PDF reader: opens a document from the system picker and renders it with
/// navigation, outline, thumbnails and in-document search.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({required this.preferences, this.picker = const PdfPicker(), super.key});

  final ViewPreferences preferences;

  /// Injected so widget tests can drive the screen without a native picker.
  final PdfPicker picker;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  final _searchTextController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Null until a document is loaded.
  ///
  /// [PdfTextSearcher] subscribes to the controller's document the moment it is
  /// constructed, so it cannot exist before the viewer is ready, and it has to
  /// be rebuilt for each document that gets opened.
  PdfTextSearcher? _searcher;

  PdfSource? _source;
  PdfDocument? _document;
  int _pageNumber = 1;
  bool _isOpening = false;
  bool _isSearchVisible = false;
  late ReadingMode _readingMode = widget.preferences.readingMode;

  int get _pageCount => _document?.pages.length ?? 0;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onPreferencesChanged);
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onPreferencesChanged);
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
      // Drop the previous document's searcher immediately: it is bound to a
      // document that is about to go away. onViewerReady builds a new one.
      _closeSearch();
      _disposeSearcher();
      setState(() {
        _source = source;
        _document = null;
        _pageNumber = 1;
      });
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Could not open the PDF: $error');
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  void _fitWidth() {
    if (!_controller.isReady) return;
    final matrix = _controller.calcMatrixFitWidthForPage(pageNumber: _pageNumber);
    if (matrix != null) _controller.goTo(matrix);
  }

  void _fitPage() {
    if (!_controller.isReady) return;
    final matrix = _controller.calcMatrixForFit(pageNumber: _pageNumber);
    if (matrix != null) _controller.goTo(matrix);
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
      },
    );
  }

  Widget _buildViewer(PdfSource source) {
    final params = _buildParams(context);
    final key = ValueKey(source.key);
    return switch (source) {
      PdfFileSource(:final path) => PdfViewer.file(
        path,
        key: key,
        controller: _controller,
        params: params,
      ),
      PdfDataSource(:final bytes, :final sourceId) => PdfViewer.data(
        bytes,
        key: key,
        sourceName: sourceId,
        controller: _controller,
        params: params,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
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
      body: source == null
          ? ViewerEmptyState(onOpenPressed: _openPdf, isOpening: _isOpening)
          : _buildViewer(source),
      bottomNavigationBar: document == null
          ? null
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
              onFitPage: _fitPage,
            ),
    );
  }

  Widget _buildSidePanel(PdfDocument document) {
    return Drawer(
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const SizedBox(height: 8),
            SafeArea(
              bottom: false,
              child: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.grid_view), text: 'Pages'),
                  Tab(icon: Icon(Icons.list), text: 'Outline'),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reading mode, night mode and app theme, grouped in one overflow menu.
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
            child: Row(
              children: [
                Icon(
                  preferences.readingMode == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(mode.label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: () => preferences.invertPages = !preferences.invertPages,
          child: Row(
            children: [
              Icon(
                preferences.invertPages ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
              ),
              const SizedBox(width: 12),
              const Flexible(
                child: Text('Night mode (invert pages)', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        PopupMenuItem<void>(
          onTap: preferences.cycleThemeMode,
          child: Row(
            children: [
              const Icon(Icons.brightness_6_outlined, size: 18),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Theme: ${_themeLabel(preferences.themeMode)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
