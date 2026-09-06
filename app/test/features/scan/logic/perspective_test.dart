import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/scan/logic/perspective.dart';
import 'package:the_pdf_project/features/scan/model/document_quad.dart';

void main() {
  void expectNear(Offset actual, Offset expected, {double tolerance = 1e-9}) {
    expect(actual.dx, closeTo(expected.dx, tolerance));
    expect(actual.dy, closeTo(expected.dy, tolerance));
  }

  group('the corners always land on the corners', () {
    for (final entry in <String, DocumentQuad>{
      'the whole picture': DocumentQuad.full,
      'an upright crop': const DocumentQuad(
        topLeft: Offset(0.1, 0.2),
        topRight: Offset(0.8, 0.2),
        bottomRight: Offset(0.8, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      ),
      'a page seen at an angle': const DocumentQuad(
        topLeft: Offset(0.2, 0.1),
        topRight: Offset(0.9, 0.25),
        bottomRight: Offset(0.75, 0.95),
        bottomLeft: Offset(0.05, 0.7),
      ),
      'a page leaning away, so the far edge is shorter': const DocumentQuad(
        topLeft: Offset(0.3, 0.1),
        topRight: Offset(0.7, 0.1),
        bottomRight: Offset(0.95, 0.9),
        bottomLeft: Offset(0.05, 0.9),
      ),
    }.entries) {
      test(entry.key, () {
        final map = PerspectiveMap.ontoQuad(entry.value);

        expectNear(map.map(0, 0), entry.value.topLeft);
        expectNear(map.map(1, 0), entry.value.topRight);
        expectNear(map.map(1, 1), entry.value.bottomRight);
        expectNear(map.map(0, 1), entry.value.bottomLeft);
      });
    }
  });

  test('the middle of the square lands inside the quad', () {
    const quad = DocumentQuad(
      topLeft: Offset(0.3, 0.1),
      topRight: Offset(0.7, 0.1),
      bottomRight: Offset(0.95, 0.9),
      bottomLeft: Offset(0.05, 0.9),
    );

    final centre = PerspectiveMap.ontoQuad(quad).map(0.5, 0.5);

    expect(centre.dx, inExclusiveRange(0.05, 0.95));
    expect(centre.dy, inExclusiveRange(0.1, 0.9));
  });

  test('a leaning page is not simply stretched', () {
    // The bottom edge is wider, so that end of the page is nearer the camera
    // and takes up more of the picture. Halfway down the real page therefore
    // appears above halfway down the quad — a plain stretch would put it
    // exactly halfway, which is what makes this the test that perspective is
    // being handled at all.
    const quad = DocumentQuad(
      topLeft: Offset(0.3, 0.1),
      topRight: Offset(0.7, 0.1),
      bottomRight: Offset(0.95, 0.9),
      bottomLeft: Offset(0.05, 0.9),
    );

    final middle = PerspectiveMap.ontoQuad(quad).map(0.5, 0.5);

    expect(middle.dy, lessThan(0.5));
  });

  test('an upright crop maps in a straight line', () {
    const quad = DocumentQuad(
      topLeft: Offset(0, 0),
      topRight: Offset(0.5, 0),
      bottomRight: Offset(0.5, 0.5),
      bottomLeft: Offset(0, 0.5),
    );

    final map = PerspectiveMap.ontoQuad(quad);

    expectNear(map.map(0.5, 0.5), const Offset(0.25, 0.25));
    expectNear(map.map(0.25, 0.75), const Offset(0.125, 0.375));
  });

  test('three corners in a line leave the picture alone rather than exploding', () {
    const degenerate = DocumentQuad(
      topLeft: Offset(0, 0),
      topRight: Offset(0.5, 0),
      bottomRight: Offset(1, 0),
      bottomLeft: Offset(0, 1),
    );

    final mapped = PerspectiveMap.ontoQuad(degenerate).map(0.5, 0.5);

    expect(mapped.dx.isFinite, isTrue);
    expect(mapped.dy.isFinite, isTrue);
  });
}
