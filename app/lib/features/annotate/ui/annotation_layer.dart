import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../annotation_controller.dart';
import '../logic/annotation_hit_test.dart';
import '../logic/page_coordinates.dart';
import '../logic/text_highlight.dart';
import '../model/annotation.dart';
import '../model/annotation_tool.dart';
import 'annotation_painter.dart';

/// Asks the reader for the text of a note or text box.
typedef AnnotationTextRequest =
    Future<String?> Function({required String title, required String? initialText});

/// Draws annotations over the viewer and turns touches into new ones.
///
/// The layer sits above [PdfViewer] in a stack and works entirely in the
/// viewer's own coordinate spaces: `localToDocument` turns a touch into
/// document space, `documentToLocal` puts a page rectangle back into this
/// widget's space for painting. Because both come from the viewer, scrolling,
/// zooming, the reading-mode switch and view rotation are all handled for
/// free — the page rectangle moves and the annotations move with it.
class AnnotationLayer extends StatefulWidget {
  const AnnotationLayer({
    required this.controller,
    required this.viewer,
    required this.requestText,
    super.key,
  });

  final AnnotationController controller;
  final PdfViewerController viewer;
  final AnnotationTextRequest requestText;

  /// How close a touch has to be to an annotation to count, in logical pixels.
  static const hitTolerance = 12.0;

  /// Freehand points closer together than this are dropped, so a slow stroke
  /// does not store hundreds of near-identical points.
  static const _minimumInkSpacing = 1.5;

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  /// Character rectangles per page, in normalised page space, loaded the first
  /// time a highlight needs them.
  final _charRectsByPage = <int, List<Rect>>{};
  final _pageTextByPage = <int, String>{};
  final _pageTextLoads = <int, Future<void>>{};

  int? _activePage;
  Offset? _dragStart;
  Offset? _dragOrigin;
  List<Offset> _inkPoints = const [];
  String? _movingId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Rebuilds only for changes that alter how pointers are handled; painting
  /// is driven by the painter's own repaint listenable.
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // --- coordinates ---------------------------------------------------------

  /// Everything a gesture needs about the page it landed on.
  ({int pageNumber, Rect pageRect, PdfPage page})? _pageAt(Offset localPosition) {
    final viewer = widget.viewer;
    if (!viewer.isReady) return null;
    final layout = viewer.layout.pageLayouts;
    if (layout.isEmpty) return null;

    final documentPoint = viewer.localToDocument(localPosition);
    final pageNumber =
        PageCoordinates.pageNumberAt(documentPoint, layout) ??
        PageCoordinates.nearestPageNumber(documentPoint, layout);
    if (pageNumber == null) return null;
    return (
      pageNumber: pageNumber,
      pageRect: layout[pageNumber - 1],
      page: viewer.pages[pageNumber - 1],
    );
  }

  /// Where [localPosition] falls on [pageNumber], as a fraction of that page.
  ///
  /// Always measured against the page the gesture started on, so dragging past
  /// a page boundary keeps extending the same annotation instead of jumping.
  Offset? _normalizedOn(int pageNumber, Offset localPosition, {bool clamp = true}) {
    final viewer = widget.viewer;
    if (!viewer.isReady) return null;
    final layout = viewer.layout.pageLayouts;
    if (pageNumber < 1 || pageNumber > layout.length) return null;
    final normalized = PageCoordinates.toNormalized(
      viewer.localToDocument(localPosition),
      layout[pageNumber - 1],
    );
    return clamp ? PageCoordinates.clampToPage(normalized) : normalized;
  }

  /// The hit-test tolerance in document units, so it stays a constant number
  /// of pixels on screen however far the reader has zoomed in.
  double get _documentTolerance {
    final zoom = widget.viewer.isReady ? widget.viewer.currentZoom : 1.0;
    return zoom <= 0 ? AnnotationLayer.hitTolerance : AnnotationLayer.hitTolerance / zoom;
  }

  // --- gestures ------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    final controller = widget.controller;
    final target = _pageAt(event.localPosition);
    if (target == null) return;
    final normalized = _normalizedOn(target.pageNumber, event.localPosition);
    if (normalized == null) return;

    _activePage = target.pageNumber;
    _dragStart = normalized;
    _dragOrigin = normalized;

    switch (controller.tool) {
      case AnnotationTool.pan:
        return;

      case AnnotationTool.select:
        final hit = _hitTest(target, event.localPosition);
        controller.select(hit?.id);
        _movingId = hit?.id;

      case AnnotationTool.eraser:
        final hit = _hitTest(target, event.localPosition);
        if (hit != null) controller.remove(hit.id);

      case AnnotationTool.ink:
        _inkPoints = [normalized];
        controller.setDraft(_buildInk(target.pageNumber, _inkPoints));

      case AnnotationTool.stickyNote:
        unawaited(_createStickyNote(target.pageNumber, normalized));

      case AnnotationTool.highlight:
      case AnnotationTool.rectangle:
      case AnnotationTool.ellipse:
      case AnnotationTool.line:
      case AnnotationTool.arrow:
      case AnnotationTool.textBox:
        // Start reading the page's text now, so snapping is usually ready by
        // the time the drag ends.
        unawaited(_ensurePageText(target.pageNumber, target.page));
        controller.setDraft(_buildDrag(target.pageNumber, normalized, normalized));
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final controller = widget.controller;
    final pageNumber = _activePage;
    if (pageNumber == null) return;
    final normalized = _normalizedOn(pageNumber, event.localPosition);
    if (normalized == null) return;

    switch (controller.tool) {
      case AnnotationTool.pan:
        return;

      case AnnotationTool.select:
        if (_movingId == null || _dragOrigin == null) return;
        controller.moveSelectedBy(normalized - _dragOrigin!);
        _dragOrigin = normalized;

      case AnnotationTool.eraser:
        // Erasing continues as the finger moves, like rubbing something out.
        final target = _pageAt(event.localPosition);
        if (target == null) return;
        final hit = _hitTest(target, event.localPosition);
        if (hit != null) controller.remove(hit.id);

      case AnnotationTool.ink:
        if (_inkPoints.isEmpty) return;
        if (!_isFarEnough(normalized, _inkPoints.last, pageNumber)) return;
        _inkPoints = [..._inkPoints, normalized];
        controller.setDraft(_buildInk(pageNumber, _inkPoints));

      case AnnotationTool.stickyNote:
        return;

      case AnnotationTool.highlight:
      case AnnotationTool.rectangle:
      case AnnotationTool.ellipse:
      case AnnotationTool.line:
      case AnnotationTool.arrow:
      case AnnotationTool.textBox:
        if (_dragStart == null) return;
        controller.setDraft(_buildDrag(pageNumber, _dragStart!, normalized));
    }
  }

  void _onPointerUp(PointerEvent event) {
    final controller = widget.controller;
    final pageNumber = _activePage;
    final start = _dragStart;
    _activePage = null;
    _dragStart = null;
    _dragOrigin = null;
    _movingId = null;
    if (pageNumber == null) return;

    switch (controller.tool) {
      case AnnotationTool.pan:
      case AnnotationTool.select:
      case AnnotationTool.eraser:
      case AnnotationTool.stickyNote:
        return;

      case AnnotationTool.ink:
        final points = _inkPoints;
        _inkPoints = const [];
        if (points.isEmpty) {
          controller.setDraft(null);
          return;
        }
        controller.add(_buildInk(pageNumber, points));

      case AnnotationTool.highlight:
        final end = _normalizedOn(pageNumber, event.localPosition);
        controller.setDraft(null);
        if (start == null || end == null) return;
        unawaited(_commitHighlight(pageNumber, start, end));

      case AnnotationTool.textBox:
        final end = _normalizedOn(pageNumber, event.localPosition);
        controller.setDraft(null);
        if (start == null || end == null) return;
        unawaited(_createTextBox(pageNumber, start, end));

      case AnnotationTool.rectangle:
      case AnnotationTool.ellipse:
      case AnnotationTool.line:
      case AnnotationTool.arrow:
        final end = _normalizedOn(pageNumber, event.localPosition);
        controller.setDraft(null);
        if (start == null || end == null) return;
        // A tap is not a shape; ignore anything too small to have been meant.
        if (!_isFarEnough(end, start, pageNumber)) return;
        controller.add(_buildDrag(pageNumber, start, end));
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePage = null;
    _dragStart = null;
    _dragOrigin = null;
    _movingId = null;
    _inkPoints = const [];
    widget.controller.setDraft(null);
  }

  Annotation? _hitTest(({int pageNumber, Rect pageRect, PdfPage page}) target, Offset localPosition) {
    if (!widget.viewer.isReady) return null;
    return AnnotationHitTest.topmostAt(
      widget.controller.annotations
          .where((annotation) => annotation.pageNumber == target.pageNumber)
          .toList(),
      widget.viewer.localToDocument(localPosition),
      target.pageRect,
      tolerance: _documentTolerance,
      pageWidthInPoints: target.page.width,
    );
  }

  /// Whether two normalised points are more than the ink spacing apart on
  /// screen, so the threshold means the same thing at every zoom level.
  bool _isFarEnough(Offset a, Offset b, int pageNumber) {
    final viewer = widget.viewer;
    if (!viewer.isReady) return true;
    final layout = viewer.layout.pageLayouts;
    if (pageNumber < 1 || pageNumber > layout.length) return true;
    final pageRect = layout[pageNumber - 1];
    final distance =
        (PageCoordinates.toDocument(a, pageRect) - PageCoordinates.toDocument(b, pageRect))
            .distance *
        (viewer.currentZoom <= 0 ? 1 : viewer.currentZoom);
    return distance >= AnnotationLayer._minimumInkSpacing;
  }

  // --- building annotations ------------------------------------------------

  InkAnnotation _buildInk(int pageNumber, List<Offset> points) {
    final style = widget.controller.style;
    return InkAnnotation(
      id: widget.controller.draft?.id ?? widget.controller.newId(),
      pageNumber: pageNumber,
      color: style.color,
      opacity: style.opacity,
      createdAt: DateTime.now(),
      strokes: [points],
      strokeWidth: style.strokeWidth,
    );
  }

  Annotation _buildDrag(int pageNumber, Offset start, Offset end) {
    final controller = widget.controller;
    final style = controller.style;
    final id = controller.draft?.id ?? controller.newId();
    final createdAt = DateTime.now();

    return switch (controller.tool) {
      AnnotationTool.highlight => HighlightAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: style.color,
        opacity: _highlightOpacity(style.opacity),
        createdAt: createdAt,
        bands: [Rect.fromPoints(start, end)],
      ),
      AnnotationTool.textBox => TextBoxAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: style.color,
        opacity: style.opacity,
        createdAt: createdAt,
        bounds: Rect.fromPoints(start, end),
        text: '',
        fontSize: style.strokeWidth * 4,
      ),
      _ => ShapeAnnotation(
        id: id,
        pageNumber: pageNumber,
        color: style.color,
        opacity: style.opacity,
        createdAt: createdAt,
        kind: switch (controller.tool) {
          AnnotationTool.ellipse => ShapeKind.ellipse,
          AnnotationTool.line => ShapeKind.line,
          AnnotationTool.arrow => ShapeKind.arrow,
          _ => ShapeKind.rectangle,
        },
        start: start,
        end: end,
        strokeWidth: style.strokeWidth,
      ),
    };
  }

  /// Highlights are translucent by nature; a solid one would hide the text.
  static double _highlightOpacity(double styleOpacity) => styleOpacity * 0.4;

  Future<void> _commitHighlight(int pageNumber, Offset start, Offset end) async {
    final controller = widget.controller;
    final viewer = widget.viewer;
    // Wait for the page's text if it is still being read: snapping to text is
    // the point of the tool, and a highlight that misses is worse than one
    // that takes a moment to appear.
    if (viewer.isReady && pageNumber >= 1 && pageNumber <= viewer.pages.length) {
      await _ensurePageText(pageNumber, viewer.pages[pageNumber - 1]);
    }
    if (!mounted) return;

    final style = controller.style;
    final selection = Rect.fromPoints(start, end);
    final charRects = _charRectsByPage[pageNumber];

    // Snap to the text the drag ran across; fall back to the raw rectangle
    // when the page has no text under it (a scan, or a stray drag).
    var bands = charRects == null ? const <Rect>[] : TextHighlight.bandsFor(charRects, selection);
    var text = '';
    if (bands.isEmpty) {
      if (selection.width <= 0 || selection.height <= 0) return;
      bands = [selection];
    } else {
      text = _textFor(pageNumber, charRects!, selection);
    }

    controller.add(
      HighlightAnnotation(
        id: controller.newId(),
        pageNumber: pageNumber,
        color: style.color,
        opacity: _highlightOpacity(style.opacity),
        createdAt: DateTime.now(),
        bands: bands,
        text: text,
      ),
    );
  }

  String _textFor(int pageNumber, List<Rect> charRects, Rect selection) {
    final fullText = _pageTextByPage[pageNumber];
    if (fullText == null) return '';
    final indices = TextHighlight.coveredCharIndices(charRects, selection);
    if (indices.isEmpty) return '';
    final start = indices.first.clamp(0, fullText.length);
    final end = (indices.last + 1).clamp(start, fullText.length);
    return fullText.substring(start, end).trim();
  }

  Future<void> _createStickyNote(int pageNumber, Offset anchor) async {
    final controller = widget.controller;
    final text = await widget.requestText(title: 'Sticky note', initialText: null);
    if (!mounted || text == null || text.isEmpty) return;
    controller.add(
      StickyNoteAnnotation(
        id: controller.newId(),
        pageNumber: pageNumber,
        color: controller.style.color,
        opacity: controller.style.opacity,
        createdAt: DateTime.now(),
        anchor: anchor,
        text: text,
      ),
    );
  }

  Future<void> _createTextBox(int pageNumber, Offset start, Offset end) async {
    final controller = widget.controller;
    final style = controller.style;
    final text = await widget.requestText(title: 'Text box', initialText: null);
    if (!mounted || text == null || text.isEmpty) return;

    // A tap rather than a drag still gets a usable box.
    var bounds = Rect.fromPoints(start, end);
    if (bounds.width < 0.05 || bounds.height < 0.02) {
      bounds = Rect.fromLTWH(start.dx, start.dy, 0.4, 0.08);
    }

    controller.add(
      TextBoxAnnotation(
        id: controller.newId(),
        pageNumber: pageNumber,
        color: style.color,
        opacity: style.opacity,
        createdAt: DateTime.now(),
        bounds: PageCoordinates.clampRectToPage(bounds),
        text: text,
        fontSize: style.strokeWidth * 4,
      ),
    );
  }

  /// Loads a page's character rectangles so highlights can snap to text.
  ///
  /// Concurrent callers share one load, so a drag that starts a load and a
  /// commit that waits for it do not read the page twice.
  Future<void> _ensurePageText(int pageNumber, PdfPage page) {
    if (_charRectsByPage.containsKey(pageNumber)) return Future.value();
    return _pageTextLoads[pageNumber] ??= _loadPageText(pageNumber, page);
  }

  Future<void> _loadPageText(int pageNumber, PdfPage page) async {
    try {
      final pageText = await page.loadStructuredText();
      _charRectsByPage[pageNumber] = [
        for (final rect in pageText.charRects) _toNormalized(rect, page),
      ];
      _pageTextByPage[pageNumber] = pageText.fullText;
    } on Object catch (error) {
      debugPrint('Could not read text on page $pageNumber: $error');
      _charRectsByPage[pageNumber] = const [];
    } finally {
      _pageTextLoads.remove(pageNumber);
    }
  }

  /// A PDF rectangle (points, y measured up from the bottom) as a fraction of
  /// its page, with y measured down from the top.
  static Rect _toNormalized(PdfRect rect, PdfPage page) {
    if (page.width <= 0 || page.height <= 0) return Rect.zero;
    final inPoints = rect.toRect(page: page);
    return Rect.fromLTRB(
      inPoints.left / page.width,
      inPoints.top / page.height,
      inPoints.right / page.width,
      inPoints.bottom / page.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final capturesPointers = controller.isEnabled && !controller.tool.passesPointersThrough;

    return IgnorePointer(
      ignoring: !capturesPointers,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _AnnotationLayerPainter(
            controller: controller,
            viewer: widget.viewer,
            selectionColor: Theme.of(context).colorScheme.primary,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Paints every visible page's annotations in the layer's local space.
class _AnnotationLayerPainter extends CustomPainter {
  _AnnotationLayerPainter({
    required this.controller,
    required this.viewer,
    required this.selectionColor,
  }) : super(repaint: Listenable.merge([controller, viewer]));

  final AnnotationController controller;
  final PdfViewerController viewer;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!viewer.isReady) return;
    final layout = viewer.layout.pageLayouts;
    final pages = viewer.pages;
    final visible = Rect.fromLTWH(0, 0, size.width, size.height);

    for (var i = 0; i < layout.length && i < pages.length; i++) {
      final annotations = controller.forPage(i + 1);
      if (annotations.isEmpty) continue;

      final localRect = _toLocal(layout[i]);
      if (localRect == null || !localRect.overlaps(visible)) continue;

      canvas.save();
      canvas.clipRect(localRect);
      for (final annotation in annotations) {
        AnnotationPainter.paint(
          canvas,
          annotation,
          pageRect: localRect,
          pageWidthInPoints: pages[i].width,
          isSelected: annotation.id == controller.selectedId,
          selectionColor: selectionColor,
        );
      }
      canvas.restore();
    }
  }

  /// A page rectangle in document space, moved into the layer's own space.
  Rect? _toLocal(Rect documentRect) {
    final topLeft = viewer.documentToLocal(documentRect.topLeft);
    final bottomRight = viewer.documentToLocal(documentRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  @override
  bool shouldRepaint(_AnnotationLayerPainter oldDelegate) =>
      oldDelegate.selectionColor != selectionColor;
}
