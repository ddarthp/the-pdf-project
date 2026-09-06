import 'package:flutter/foundation.dart';

/// One page in a page-organising plan.
///
/// A plan is an ordered list of these: it describes the document that *would*
/// be produced, without touching any file. Nothing is written until the plan
/// is encoded and saved, so every operation is cheap and reversible.
@immutable
sealed class PagePlanEntry {
  const PagePlanEntry({required this.id, required this.quarterTurns});

  /// Stable identity for this entry, unique within a plan.
  ///
  /// The same source page can appear more than once (merging a file into
  /// itself, say), so the source and page number do not identify an entry.
  final String id;

  /// Clockwise quarter turns to apply on top of the page's own rotation.
  final int quarterTurns;

  /// Returns a copy turned [turns] quarter turns clockwise. Negative turns
  /// rotate anticlockwise.
  PagePlanEntry rotatedBy(int turns);

  static int normalizeTurns(int turns) => (turns % 4 + 4) % 4;
}

/// A page taken from one of the loaded source documents.
class SourcePageEntry extends PagePlanEntry {
  const SourcePageEntry({
    required super.id,
    required this.sourceId,
    required this.pageNumber,
    super.quarterTurns = 0,
  });

  /// Identifies the document this page comes from.
  final String sourceId;

  /// 1-based page number within that document.
  final int pageNumber;

  @override
  SourcePageEntry rotatedBy(int turns) => SourcePageEntry(
    id: id,
    sourceId: sourceId,
    pageNumber: pageNumber,
    quarterTurns: PagePlanEntry.normalizeTurns(quarterTurns + turns),
  );

  @override
  bool operator ==(Object other) =>
      other is SourcePageEntry &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.pageNumber == pageNumber &&
      other.quarterTurns == quarterTurns;

  @override
  int get hashCode => Object.hash(id, sourceId, pageNumber, quarterTurns);

  @override
  String toString() => 'SourcePageEntry($sourceId p$pageNumber, turns: $quarterTurns)';
}

/// An empty page of a given size, in points.
class BlankPageEntry extends PagePlanEntry {
  const BlankPageEntry({
    required super.id,
    required this.width,
    required this.height,
    super.quarterTurns = 0,
  });

  final double width;
  final double height;

  /// Key for reusing one generated blank document per page size.
  String get sizeKey => '${width.toStringAsFixed(2)}x${height.toStringAsFixed(2)}';

  @override
  BlankPageEntry rotatedBy(int turns) => BlankPageEntry(
    id: id,
    width: width,
    height: height,
    quarterTurns: PagePlanEntry.normalizeTurns(quarterTurns + turns),
  );

  @override
  bool operator ==(Object other) =>
      other is BlankPageEntry &&
      other.id == id &&
      other.width == width &&
      other.height == height &&
      other.quarterTurns == quarterTurns;

  @override
  int get hashCode => Object.hash(id, width, height, quarterTurns);

  @override
  String toString() => 'BlankPageEntry(${width}x$height, turns: $quarterTurns)';
}
