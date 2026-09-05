import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/pages/model/page_plan_entry.dart';

void main() {
  test('rotating a source page keeps its identity and source', () {
    const entry = SourcePageEntry(id: 'p0', sourceId: 'doc', pageNumber: 2);

    final rotated = entry.rotatedBy(1);

    expect(rotated.id, 'p0');
    expect(rotated.sourceId, 'doc');
    expect(rotated.pageNumber, 2);
    expect(rotated.quarterTurns, 1);
  });

  test('turns wrap around a full circle in both directions', () {
    const entry = SourcePageEntry(id: 'p0', sourceId: 'doc', pageNumber: 1);

    expect(entry.rotatedBy(4).quarterTurns, 0);
    expect(entry.rotatedBy(5).quarterTurns, 1);
    expect(entry.rotatedBy(-1).quarterTurns, 3);
    expect(entry.rotatedBy(-5).quarterTurns, 3);
  });

  test('blank pages rotate and keep their size', () {
    const entry = BlankPageEntry(id: 'b0', width: 595, height: 842);

    final rotated = entry.rotatedBy(3);

    expect(rotated.width, 595);
    expect(rotated.height, 842);
    expect(rotated.quarterTurns, 3);
  });

  test('blank pages of the same size share one size key', () {
    const a = BlankPageEntry(id: 'b0', width: 595, height: 842);
    const b = BlankPageEntry(id: 'b1', width: 595, height: 842);
    const c = BlankPageEntry(id: 'b2', width: 842, height: 595);

    expect(a.sizeKey, b.sizeKey);
    expect(a.sizeKey, isNot(c.sizeKey));
  });
}
