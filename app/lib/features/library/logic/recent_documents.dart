import '../model/recent_document.dart';

/// Keeping the recents list in order.
///
/// Pure list transforms, so the rules — most recent first, one entry per
/// document, a bounded list — are testable without a store or a file system.
abstract final class RecentDocuments {
  /// How many documents the list remembers. Beyond this the oldest fall off,
  /// which is also what stops the app's copies of picked files growing without
  /// end.
  static const maxEntries = 30;

  /// Puts [document] at the front, replacing any earlier entry for the same
  /// document rather than letting it appear twice.
  static List<RecentDocument> promote(
    List<RecentDocument> documents,
    RecentDocument document, {
    int maxEntries = maxEntries,
  }) {
    final promoted = [
      document,
      for (final existing in documents)
        if (existing.key != document.key) existing,
    ];
    return promoted.length <= maxEntries ? promoted : promoted.sublist(0, maxEntries);
  }

  static List<RecentDocument> remove(List<RecentDocument> documents, String key) => [
    for (final document in documents)
      if (document.key != key) document,
  ];

  /// Fills in a document's page count once it has actually been opened.
  static List<RecentDocument> withPageCount(
    List<RecentDocument> documents,
    String key,
    int pageCount,
  ) => [
    for (final document in documents)
      if (document.key == key) document.copyWith(pageCount: pageCount) else document,
  ];

  /// The paths the list no longer refers to.
  ///
  /// Used to delete the app's own copies of documents that have dropped off
  /// the end, so the list bounds the storage as well as itself.
  static List<String> droppedPaths(
    List<RecentDocument> before,
    List<RecentDocument> after,
  ) {
    final kept = {for (final document in after) document.path};
    return [
      for (final document in before)
        if (!kept.contains(document.path)) document.path,
    ];
  }
}
