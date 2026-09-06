import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'model/annotation.dart';
import 'model/annotation_style.dart';
import 'model/annotation_tool.dart';
import 'services/annotation_store.dart';

/// Owns the annotations for the document on screen, plus which tool and style
/// the reader has chosen.
///
/// The viewer, the toolbar, the drawing layer and the panel all listen to
/// this, so there is one copy of the truth and any of them can change it.
/// Every change is written back to the store, debounced so a freehand stroke
/// does not cause a write per point.
class AnnotationController extends ChangeNotifier {
  AnnotationController({required this.store, this.saveDebounce = const Duration(milliseconds: 400)});

  final AnnotationStore store;

  /// How long to wait for edits to settle before writing to the store.
  final Duration saveDebounce;

  String? _documentKey;
  List<Annotation> _annotations = const [];
  Annotation? _draft;
  String? _selectedId;
  bool _isEnabled = false;
  AnnotationTool _tool = AnnotationTool.ink;
  AnnotationStyle _style = const AnnotationStyle();
  Timer? _saveTimer;
  var _nextId = 0;

  /// All annotations on the open document, oldest first.
  List<Annotation> get annotations => List.unmodifiable(_annotations);

  /// The annotation currently being drawn, painted but not yet committed.
  Annotation? get draft => _draft;

  String? get selectedId => _selectedId;

  Annotation? get selected =>
      _annotations.where((annotation) => annotation.id == _selectedId).firstOrNull;

  /// Whether annotation mode is on. With it off, existing annotations are
  /// still drawn but pointers go to the viewer.
  bool get isEnabled => _isEnabled;

  AnnotationTool get tool => _tool;

  AnnotationStyle get style => _style;

  bool get hasAnnotations => _annotations.isNotEmpty;

  /// Annotations on one page, oldest first, with the draft included so it is
  /// painted while it is being drawn.
  List<Annotation> forPage(int pageNumber) => [
    for (final annotation in _annotations)
      if (annotation.pageNumber == pageNumber) annotation,
    if (_draft?.pageNumber == pageNumber) _draft!,
  ];

  /// Loads the annotations belonging to [documentKey], replacing whatever was
  /// on screen. Pending writes for the previous document are flushed first.
  Future<void> loadFor(String documentKey) async {
    await flush();
    _documentKey = documentKey;
    _annotations = const [];
    _draft = null;
    _selectedId = null;
    notifyListeners();

    final loaded = await store.load(documentKey);
    // Another document may have been opened while this load was in flight.
    if (_documentKey != documentKey) return;
    _annotations = loaded;
    _nextId = loaded.length;
    notifyListeners();
  }

  /// Clears the screen when the viewer has no document.
  void clear() {
    _documentKey = null;
    _annotations = const [];
    _draft = null;
    _selectedId = null;
    notifyListeners();
  }

  set isEnabled(bool value) {
    if (_isEnabled == value) return;
    _isEnabled = value;
    if (!value) _selectedId = null;
    notifyListeners();
  }

  set tool(AnnotationTool value) {
    if (_tool == value) return;
    _tool = value;
    // A tool change means the reader has moved on from whatever was selected.
    if (value != AnnotationTool.select) _selectedId = null;
    notifyListeners();
  }

  set style(AnnotationStyle value) {
    if (_style == value) return;
    _style = value;
    notifyListeners();
    // Restyling applies to the selection too, so the toolbar edits what is
    // already on the page rather than only what comes next.
    final selected = this.selected;
    if (selected != null) {
      replace(
        selected.restyled(
          color: value.color,
          opacity: value.opacity,
          strokeWidth: value.strokeWidth,
        ),
      );
    }
  }

  /// A fresh id for a new annotation, unique within this document.
  String newId() => 'ann-${_nextId++}-${DateTime.now().microsecondsSinceEpoch}';

  /// Shows [annotation] as being drawn without committing it.
  void setDraft(Annotation? annotation) {
    _draft = annotation;
    notifyListeners();
  }

  void add(Annotation annotation) {
    _draft = null;
    _annotations = [..._annotations, annotation];
    _selectedId = annotation.id;
    _scheduleSave();
    notifyListeners();
  }

  /// Replaces an annotation with an edited version of itself.
  void replace(Annotation annotation) {
    final index = _annotations.indexWhere((existing) => existing.id == annotation.id);
    if (index < 0) return;
    _annotations = [..._annotations]..[index] = annotation;
    _scheduleSave();
    notifyListeners();
  }

  void remove(String id) {
    if (!_annotations.any((annotation) => annotation.id == id)) return;
    _annotations = [
      for (final annotation in _annotations)
        if (annotation.id != id) annotation,
    ];
    if (_selectedId == id) _selectedId = null;
    _scheduleSave();
    notifyListeners();
  }

  void removeAll() {
    if (_annotations.isEmpty) return;
    _annotations = const [];
    _selectedId = null;
    _scheduleSave();
    notifyListeners();
  }

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Moves the selected annotation by [delta] in normalised page space.
  void moveSelectedBy(Offset delta) {
    final selected = this.selected;
    if (selected == null) return;
    replace(selected.movedBy(delta));
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, () => unawaited(flush()));
  }

  /// Writes pending changes now. Called when the document changes and on
  /// dispose, so nothing is lost to a debounce that never fired.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final documentKey = _documentKey;
    if (documentKey == null) return;
    await store.save(documentKey, _annotations);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final documentKey = _documentKey;
    if (documentKey != null) {
      unawaited(store.save(documentKey, _annotations));
    }
    super.dispose();
  }
}
