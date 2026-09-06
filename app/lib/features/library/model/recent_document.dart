import 'package:flutter/foundation.dart';

/// A document the reader has opened before.
///
/// Identified by the same key the rest of the app uses for a document, so the
/// page it was left on and the annotations drawn on it line up with the entry
/// in the list without any separate bookkeeping.
@immutable
class RecentDocument {
  const RecentDocument({
    required this.key,
    required this.displayName,
    required this.path,
    required this.lastOpenedAt,
    this.pageCount,
  });

  /// Matches `PdfSource.key`.
  final String key;

  /// File name, as shown in the list.
  final String displayName;

  /// Where to open it from again.
  ///
  /// For a document picked as raw bytes — Android hands back a content URI
  /// with no file behind it — this is the copy the app kept, so the entry
  /// stays openable after the pick is long gone.
  final String path;

  final DateTime lastOpenedAt;

  /// How many pages it turned out to have, once it has been opened.
  final int? pageCount;

  RecentDocument copyWith({DateTime? lastOpenedAt, int? pageCount}) => RecentDocument(
    key: key,
    displayName: displayName,
    path: path,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    pageCount: pageCount ?? this.pageCount,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'name': displayName,
    'path': path,
    'openedAt': lastOpenedAt.toIso8601String(),
    if (pageCount != null) 'pages': pageCount,
  };

  static RecentDocument fromJson(Map<String, Object?> json) => RecentDocument(
    key: json['key']! as String,
    displayName: json['name']! as String,
    path: json['path']! as String,
    lastOpenedAt: DateTime.parse(json['openedAt']! as String),
    pageCount: (json['pages'] as num?)?.toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is RecentDocument &&
      other.key == key &&
      other.displayName == displayName &&
      other.path == path &&
      other.lastOpenedAt == lastOpenedAt &&
      other.pageCount == pageCount;

  @override
  int get hashCode => Object.hash(key, displayName, path, lastOpenedAt, pageCount);

  @override
  String toString() => 'RecentDocument($displayName, $key)';
}
