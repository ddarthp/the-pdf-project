import '../model/picked_image.dart';

/// Keeping the list of images in the order the pages will come out.
abstract final class ImagePages {
  /// Moves the image at [oldIndex] so it ends up at [newIndex].
  ///
  /// Both are positions in the final list, which is what
  /// `ReorderableListView.onReorderItem` reports.
  static List<PickedImage> reorder(List<PickedImage> images, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= images.length) return List.of(images);
    final target = newIndex.clamp(0, images.length - 1);
    if (target == oldIndex) return List.of(images);
    final result = List.of(images);
    result.insert(target, result.removeAt(oldIndex));
    return result;
  }

  static List<PickedImage> remove(List<PickedImage> images, String id) => [
    for (final image in images)
      if (image.id != id) image,
  ];

  static List<PickedImage> append(List<PickedImage> images, Iterable<PickedImage> added) =>
      [...images, ...added];

  /// A file name for the PDF a set of images will become.
  ///
  /// One image gives its own name to the document; several become something
  /// generic, since no one of them speaks for the rest.
  static String suggestedFileName(List<PickedImage> images) {
    if (images.length == 1) {
      final name = images.single.displayName;
      final dot = name.lastIndexOf('.');
      // A dot at the very start is not an extension, it is the whole name —
      // there is nothing left to call the document after.
      final base = switch (dot) {
        < 0 => name,
        0 => '',
        _ => name.substring(0, dot),
      };
      return '${base.isEmpty ? 'images' : base}.pdf';
    }
    return 'images.pdf';
  }
}
