import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/convert/logic/image_pages.dart';
import 'package:the_pdf_project/features/convert/model/picked_image.dart';

PickedImage image(String name) => PickedImage(
  id: name,
  displayName: '$name.png',
  bytes: Uint8List(0),
  pixelWidth: 100,
  pixelHeight: 100,
);

List<String> idsOf(List<PickedImage> images) => [for (final image in images) image.id];

void main() {
  final images = [image('a'), image('b'), image('c')];

  group('reorder', () {
    test('moves an image down', () {
      expect(idsOf(ImagePages.reorder(images, 0, 2)), ['b', 'c', 'a']);
    });

    test('moves an image up', () {
      expect(idsOf(ImagePages.reorder(images, 2, 0)), ['c', 'a', 'b']);
    });

    test('is a no-op when nothing moves', () {
      expect(idsOf(ImagePages.reorder(images, 1, 1)), ['a', 'b', 'c']);
    });

    test('ignores an index that is not in the list', () {
      expect(idsOf(ImagePages.reorder(images, 9, 0)), ['a', 'b', 'c']);
    });

    test('leaves the original alone', () {
      ImagePages.reorder(images, 0, 2);

      expect(idsOf(images), ['a', 'b', 'c']);
    });
  });

  group('remove and append', () {
    test('takes one out by id', () {
      expect(idsOf(ImagePages.remove(images, 'b')), ['a', 'c']);
    });

    test('ignores an id that is not there', () {
      expect(idsOf(ImagePages.remove(images, 'z')), ['a', 'b', 'c']);
    });

    test('adds more to the end', () {
      expect(idsOf(ImagePages.append(images, [image('d')])), ['a', 'b', 'c', 'd']);
    });
  });

  group('suggestedFileName', () {
    test('one image lends the document its own name', () {
      expect(ImagePages.suggestedFileName([image('holiday')]), 'holiday.pdf');
    });

    test('several images get a generic name, since none speaks for the rest', () {
      expect(ImagePages.suggestedFileName(images), 'images.pdf');
    });

    test('copes with a name that has no extension', () {
      final noExtension = PickedImage(
        id: 'x',
        displayName: 'scan',
        bytes: Uint8List(0),
        pixelWidth: 1,
        pixelHeight: 1,
      );

      expect(ImagePages.suggestedFileName([noExtension]), 'scan.pdf');
    });

    test('copes with a name that is nothing but an extension', () {
      final hidden = PickedImage(
        id: 'x',
        displayName: '.png',
        bytes: Uint8List(0),
        pixelWidth: 1,
        pixelHeight: 1,
      );

      expect(ImagePages.suggestedFileName([hidden]), 'images.pdf');
    });
  });
}
