import 'package:flutter/foundation.dart';

import 'document_quad.dart';
import 'scan_filter.dart';

/// One captured page, as it stands.
///
/// The original photograph is kept alongside the processed result so the
/// corners and the filter can be changed later without going back to the
/// camera — a scan is rarely right first time.
@immutable
class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.originalBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.quad,
    required this.filter,
    required this.processedBytes,
    required this.processedWidth,
    required this.processedHeight,
  });

  final String id;

  /// The photograph as it was taken.
  final Uint8List originalBytes;
  final int originalWidth;
  final int originalHeight;

  /// Where the page sits in that photograph.
  final DocumentQuad quad;

  final ScanFilter filter;

  /// The straightened, filtered page — what goes into the PDF.
  final Uint8List processedBytes;
  final int processedWidth;
  final int processedHeight;

  ScannedPage copyWith({
    DocumentQuad? quad,
    ScanFilter? filter,
    Uint8List? processedBytes,
    int? processedWidth,
    int? processedHeight,
  }) => ScannedPage(
    id: id,
    originalBytes: originalBytes,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    quad: quad ?? this.quad,
    filter: filter ?? this.filter,
    processedBytes: processedBytes ?? this.processedBytes,
    processedWidth: processedWidth ?? this.processedWidth,
    processedHeight: processedHeight ?? this.processedHeight,
  );

  @override
  String toString() => 'ScannedPage($id, ${filter.label}, '
      '${processedWidth}x$processedHeight)';
}
