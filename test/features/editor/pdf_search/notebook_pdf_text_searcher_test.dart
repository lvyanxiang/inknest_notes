import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/pdf_search/notebook_pdf_text_searcher.dart';

void main() {
  test('builds a compact normalized snippet around a PDF text match', () {
    const text =
        'Background context for this page. Introduction   with spacing before '
        'the important result '
        'and some explanatory text after the match.';
    final matchStart = text.indexOf('important');
    final snippet = buildPdfSearchSnippet(
      text,
      matchStart,
      matchStart + 'important'.length,
    );

    expect(snippet, contains('important'));
    expect(snippet, isNot(contains('  ')));
    expect(snippet, startsWith('…'));
    expect(snippet, endsWith('…'));
  });
}
