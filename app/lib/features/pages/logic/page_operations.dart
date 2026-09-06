import '../model/page_plan_entry.dart';

/// The page operations, as pure transforms of a plan.
///
/// Every operation returns a new list and leaves its input untouched, which is
/// what makes the organiser's undo stack a plain list of previous plans. No
/// pdfrx types here: `PdfPageEditor` turns a plan into real pages.
abstract final class PageOperations {
  /// Removes the entries at [indices]. Out-of-range indices are ignored.
  static List<PagePlanEntry> delete(List<PagePlanEntry> plan, Set<int> indices) => [
    for (var i = 0; i < plan.length; i++)
      if (!indices.contains(i)) plan[i],
  ];

  /// Keeps only the entries at [indices], in their existing order.
  ///
  /// This is both "extract pages" and one half of a split.
  static List<PagePlanEntry> extract(List<PagePlanEntry> plan, Set<int> indices) => [
    for (var i = 0; i < plan.length; i++)
      if (indices.contains(i)) plan[i],
  ];

  /// Moves the page at [oldIndex] so it ends up at [newIndex].
  ///
  /// Both are positions in the final list, which is what
  /// `ReorderableListView.onReorderItem` reports.
  static List<PagePlanEntry> reorder(List<PagePlanEntry> plan, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= plan.length) return List.of(plan);
    final target = newIndex.clamp(0, plan.length - 1);
    if (target == oldIndex) return List.of(plan);
    final result = List.of(plan);
    result.insert(target, result.removeAt(oldIndex));
    return result;
  }

  /// Turns the entries at [indices] by [quarterTurns] clockwise. Negative
  /// values turn anticlockwise.
  static List<PagePlanEntry> rotate(
    List<PagePlanEntry> plan,
    Set<int> indices,
    int quarterTurns,
  ) => [
    for (var i = 0; i < plan.length; i++)
      if (indices.contains(i)) plan[i].rotatedBy(quarterTurns) else plan[i],
  ];

  /// Inserts [entries] at [index], clamped to the ends of the plan.
  static List<PagePlanEntry> insertAll(
    List<PagePlanEntry> plan,
    int index,
    Iterable<PagePlanEntry> entries,
  ) {
    final result = List.of(plan);
    result.insertAll(index.clamp(0, plan.length), entries);
    return result;
  }

  /// Adds [entries] to the end of the plan. This is how merging works: the
  /// pages of another document are appended and can then be moved anywhere.
  static List<PagePlanEntry> append(List<PagePlanEntry> plan, Iterable<PagePlanEntry> entries) =>
      [...plan, ...entries];

  /// Index one past the last selected entry, for "insert after the selection".
  /// With nothing selected, that is the end of the plan.
  static int insertionPointAfter(List<PagePlanEntry> plan, Set<int> selection) =>
      selection.isEmpty ? plan.length : selection.reduce((a, b) => a > b ? a : b) + 1;

  /// Maps a selection through a [reorder] so the same pages stay selected.
  static Set<int> selectionAfterReorder(int oldIndex, int newIndex, Set<int> selection) {
    return {
      for (final index in selection)
        if (index == oldIndex)
          newIndex
        else if (index > oldIndex && index <= newIndex)
          index - 1
        else if (index < oldIndex && index >= newIndex)
          index + 1
        else
          index,
    };
  }
}
