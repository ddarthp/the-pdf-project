import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/features/viewer/logic/page_navigation.dart';

void main() {
  group('PageNavigation.clamp', () {
    test('keeps in-range page numbers', () => expect(PageNavigation.clamp(5, 10), 5));
    test('clamps below the first page', () => expect(PageNavigation.clamp(0, 10), 1));
    test('clamps past the last page', () => expect(PageNavigation.clamp(99, 10), 10));
    test('falls back to 1 for an empty document', () => expect(PageNavigation.clamp(3, 0), 1));
  });

  group('PageNavigation.parsePageInput', () {
    test('accepts a page inside the document', () {
      expect(PageNavigation.parsePageInput(' 7 ', 10), 7);
    });

    test('rejects non-numbers, zero and out-of-range pages', () {
      expect(PageNavigation.parsePageInput('abc', 10), isNull);
      expect(PageNavigation.parsePageInput('', 10), isNull);
      expect(PageNavigation.parsePageInput('0', 10), isNull);
      expect(PageNavigation.parsePageInput('11', 10), isNull);
    });

    test('rejects anything when the document has no pages', () {
      expect(PageNavigation.parsePageInput('1', 0), isNull);
    });
  });

  group('PageNavigation bounds', () {
    test('cannot go back from the first page', () {
      expect(PageNavigation.canGoBack(1), isFalse);
      expect(PageNavigation.canGoBack(2), isTrue);
    });

    test('cannot go forward from the last page', () {
      expect(PageNavigation.canGoForward(10, 10), isFalse);
      expect(PageNavigation.canGoForward(9, 10), isTrue);
    });
  });
}
