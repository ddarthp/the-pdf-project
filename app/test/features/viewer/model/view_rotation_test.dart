import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/viewer/model/view_rotation.dart';

void main() {
  test('quarter turns match the labelled angles', () {
    expect(ViewRotation.none.quarterTurns, 0);
    expect(ViewRotation.clockwise90.quarterTurns, 1);
    expect(ViewRotation.clockwise180.quarterTurns, 2);
    expect(ViewRotation.clockwise270.quarterTurns, 3);
  });

  test('next steps clockwise and wraps back to upright', () {
    expect(ViewRotation.none.next, ViewRotation.clockwise90);
    expect(ViewRotation.clockwise90.next, ViewRotation.clockwise180);
    expect(ViewRotation.clockwise180.next, ViewRotation.clockwise270);
    expect(ViewRotation.clockwise270.next, ViewRotation.none);
  });
}
