import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/export/pdf_page_selection.dart';

void main() {
  test('parses individual pages and ranges in input order', () {
    final result = parsePdfPageSelection('5, 1, 3-4', pageCount: 6);

    expect(result.isValid, isTrue);
    expect(result.pageNumbers, [5, 1, 3, 4]);
  });

  test('removes duplicates while preserving their first position', () {
    final result = parsePdfPageSelection('1-3,2,3-5', pageCount: 5);

    expect(result.isValid, isTrue);
    expect(result.pageNumbers, [1, 2, 3, 4, 5]);
  });

  test('accepts localized comma and dash characters', () {
    final result = parsePdfPageSelection('1，3–4', pageCount: 4);

    expect(result.isValid, isTrue);
    expect(result.pageNumbers, [1, 3, 4]);
  });

  test('rejects pages outside the notebook', () {
    final result = parsePdfPageSelection('1,7', pageCount: 6);

    expect(result.isValid, isFalse);
    expect(result.errorMessage, 'Pages must be between 1 and 6.');
  });

  test('rejects descending ranges', () {
    final result = parsePdfPageSelection('5-3', pageCount: 6);

    expect(result.isValid, isFalse);
    expect(result.errorMessage, 'Page ranges must use ascending order.');
  });

  test('rejects malformed input', () {
    final result = parsePdfPageSelection('1,,3', pageCount: 6);

    expect(result.isValid, isFalse);
    expect(result.errorMessage, 'Use page numbers and ranges such as 1,3,5-7.');
  });

  test('rejects integer values too large to parse', () {
    final result = parsePdfPageSelection(
      '1-999999999999999999999999999999999999999999',
      pageCount: 6,
    );

    expect(result.isValid, isFalse);
    expect(result.errorMessage, 'Use page numbers and ranges such as 1,3,5-7.');
  });
}
