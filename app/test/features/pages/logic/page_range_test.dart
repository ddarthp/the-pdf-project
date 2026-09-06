import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/pages/logic/page_range.dart';

void main() {
  group('parse', () {
    test('reads a single page', () => expect(PageRange.parse('3', 10), [3]));

    test('reads a closed range', () => expect(PageRange.parse('2-5', 10), [2, 3, 4, 5]));

    test('reads a range open to the end', () => expect(PageRange.parse('8-', 10), [8, 9, 10]));

    test('reads a range open from the start', () => expect(PageRange.parse('-3', 10), [1, 2, 3]));

    test('combines terms, sorted and de-duplicated', () {
      expect(PageRange.parse('5, 1-3, 2', 10), [1, 2, 3, 5]);
    });

    test('accepts whitespace as a separator', () {
      expect(PageRange.parse('1 4', 10), [1, 4]);
    });

    test('reads a backwards range as written', () {
      expect(PageRange.parse('5-2', 10), [2, 3, 4, 5]);
    });

    test('rejects pages outside the document', () {
      expect(PageRange.parse('0', 10), isNull);
      expect(PageRange.parse('11', 10), isNull);
      expect(PageRange.parse('8-12', 10), isNull);
    });

    test('rejects text that is not a range', () {
      expect(PageRange.parse('', 10), isNull);
      expect(PageRange.parse('  ', 10), isNull);
      expect(PageRange.parse('abc', 10), isNull);
      expect(PageRange.parse('-', 10), isNull);
      expect(PageRange.parse('1-2-3', 10), isNull);
    });

    test('rejects anything for an empty document', () {
      expect(PageRange.parse('1', 0), isNull);
    });
  });

  group('format', () {
    test('collapses runs into ranges', () {
      expect(PageRange.format([1, 2, 3, 7, 9, 10]), '1-3, 7, 9-10');
    });

    test('sorts and de-duplicates first', () {
      expect(PageRange.format([3, 1, 2, 3]), '1-3');
    });

    test('is empty for no pages', () => expect(PageRange.format(const []), ''));
  });

  test('format and parse round-trip', () {
    final pages = PageRange.parse('1-3, 7, 9-10', 12)!;

    expect(PageRange.parse(PageRange.format(pages), 12), pages);
  });
}
