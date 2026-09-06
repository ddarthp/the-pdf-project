import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/convert/logic/image_page_layout.dart';

void main() {
  ImagePageSize pageFor(double width, double height) =>
      ImagePageLayout.pageSizeFor(imageWidth: width, imageHeight: height);

  test('a wide image gets a wide page', () {
    final page = pageFor(400, 200);

    expect(page.width, ImagePageLayout.longSide);
    expect(page.height, closeTo(ImagePageLayout.longSide / 2, 0.001));
    expect(page.isLandscape, isTrue);
  });

  test('a tall image gets a tall page', () {
    final page = pageFor(200, 400);

    expect(page.height, ImagePageLayout.longSide);
    expect(page.width, closeTo(ImagePageLayout.longSide / 2, 0.001));
    expect(page.isLandscape, isFalse);
  });

  test('a square image gets a square page', () {
    final page = pageFor(300, 300);

    expect(page.width, page.height);
    expect(page.width, ImagePageLayout.longSide);
  });

  test('the page always keeps the image\'s proportions', () {
    for (final (width, height) in const [(4000, 3000), (17, 500), (1, 1), (1200, 1600)]) {
      final page = pageFor(width.toDouble(), height.toDouble());

      expect(
        page.width / page.height,
        closeTo(width / height, 0.0001),
        reason: '${width}x$height',
      );
    }
  });

  test('the long side is the same whatever the image', () {
    for (final (width, height) in const [(4000, 3000), (100, 5000), (640, 640)]) {
      final page = pageFor(width.toDouble(), height.toDouble());

      expect(
        page.width > page.height ? page.width : page.height,
        closeTo(ImagePageLayout.longSide, 0.001),
        reason: '${width}x$height',
      );
    }
  });

  test('a measurement that is not a shape falls back to a square', () {
    for (final (width, height) in const [(0, 200), (400, 0), (-1, -1)]) {
      final page = pageFor(width.toDouble(), height.toDouble());

      expect(page.width, page.height, reason: '${width}x$height');
    }
  });
}
