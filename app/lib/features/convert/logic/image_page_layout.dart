/// The page one image goes on, in PDF points.
class ImagePageSize {
  const ImagePageSize({required this.width, required this.height});

  final double width;
  final double height;

  bool get isLandscape => width > height;

  @override
  bool operator ==(Object other) =>
      other is ImagePageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ImagePageSize(${width}x$height)';
}

/// Works out the page an image goes on.
///
/// Each page takes its shape from the image on it, so the picture fills it
/// edge to edge with nothing cropped and no white border — which is what
/// makes a set of photographs or scans read as a document rather than as
/// pictures stuck onto paper.
///
/// Pure arithmetic, free of both `pdf` and Flutter.
abstract final class ImagePageLayout {
  /// The long side of every page, in points.
  ///
  /// Sized like A4's long side, so a photograph does not become a page
  /// measured in thousands of points just because it has a lot of pixels, and
  /// so pages built from different cameras come out a comparable size.
  static const longSide = 841.89;

  static ImagePageSize pageSizeFor({
    required double imageWidth,
    required double imageHeight,
  }) {
    // A zero or negative measurement is not a shape; treat it as square rather
    // than dividing by it.
    final aspectRatio = imageWidth > 0 && imageHeight > 0 ? imageWidth / imageHeight : 1.0;

    return aspectRatio >= 1
        ? ImagePageSize(width: longSide, height: longSide / aspectRatio)
        : ImagePageSize(width: longSide * aspectRatio, height: longSide);
  }
}
