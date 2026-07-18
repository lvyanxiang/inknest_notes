import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/search/notebook_text_search_service.dart';
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/pdf_background.dart';

void main() {
  test(
    'combines PDF, typed, and handwriting-style text by notebook page',
    () async {
      const sourceRef = PdfSourcePageRef(
        filePath: '/tmp/lesson.pdf',
        pageNumber: 1,
      );
      const pdfText = 'PDF alpha';
      final extractor = _FakePdfPageTextExtractor({
        sourceRef: PdfSearchPageData(
          fullText: pdfText,
          characterRects: [
            for (var index = 0; index < pdfText.length; index += 1)
              Rect.fromLTWH(index * 8, 8, 7, 10),
          ],
          pageSize: const Size(100, 100),
        ),
      });
      final service = NotebookTextSearchService(
        pdfTextSearchService: PdfTextSearchService(extractor: extractor),
      );
      final pages = [
        NotePage(
          id: 'page-1',
          width: 100,
          height: 100,
          pdfBackground: const PdfBackground(
            assetPath: 'assets/lesson.pdf',
            resolvedFilePath: '/tmp/lesson.pdf',
            pageNumber: 1,
          ),
          textBoxes: const [
            NoteTextBox(
              id: 'typed-1',
              position: Offset.zero,
              text: 'Typed Alpha note',
            ),
          ],
        ),
        const NotePage(
          id: 'page-2',
          width: 100,
          height: 100,
          textBoxes: [
            NoteTextBox(
              id: 'smart-1',
              position: Offset.zero,
              text: 'Smart alpha result',
              style: NoteTextBoxStyle.handwriting,
            ),
          ],
        ),
      ];

      final response = await service.search(pages: pages, query: 'ALPHA');

      expect(response.results, hasLength(3));
      expect(response.results.map((result) => result.source), [
        NotebookTextSearchSource.pdf,
        NotebookTextSearchSource.textBox,
        NotebookTextSearchSource.textBox,
      ]);
      expect(response.results.map((result) => result.notebookPageNumber), [
        1,
        1,
        2,
      ]);
      expect(response.results[1].textBoxId, 'typed-1');
      expect(response.results[1].textBoxStyle, NoteTextBoxStyle.regular);
      expect(response.results[2].textBoxId, 'smart-1');
      expect(response.results[2].textBoxStyle, NoteTextBoxStyle.handwriting);
      expect(response.pdfPageCount, 1);
      expect(response.pdfTextPageCount, 1);
      expect(response.searchableTextBoxCount, 2);
      expect(response.hasSearchableText, isTrue);
    },
  );

  test(
    'searches text-only notebooks and reports combined result truncation',
    () async {
      final service = NotebookTextSearchService(
        pdfTextSearchService: PdfTextSearchService(
          extractor: _FakePdfPageTextExtractor(const {}),
        ),
        maxResults: 2,
      );
      const page = NotePage(
        id: 'page-1',
        width: 100,
        height: 100,
        textBoxes: [
          NoteTextBox(
            id: 'typed-1',
            position: Offset.zero,
            text: 'Note note note',
          ),
        ],
      );

      final response = await service.search(pages: [page], query: 'note');

      expect(response.results, hasLength(2));
      expect(
        response.results.every(
          (result) => result.matchText == 'Note' || result.matchText == 'note',
        ),
        isTrue,
      );
      expect(response.isTruncated, isTrue);
      expect(response.pdfPageCount, 0);
      expect(response.searchableTextBoxCount, 1);
    },
  );
}

class _FakePdfPageTextExtractor implements PdfPageTextExtractor {
  _FakePdfPageTextExtractor(this.pages);

  final Map<PdfSourcePageRef, PdfSearchPageData?> pages;

  @override
  Future<Map<PdfSourcePageRef, PdfSearchPageData?>> extract(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    final requested = pages.toList(growable: false);
    final result = <PdfSourcePageRef, PdfSearchPageData?>{};
    for (var index = 0; index < requested.length; index += 1) {
      final page = requested[index];
      result[page] = this.pages[page];
      onProgress?.call(index + 1, requested.length);
    }
    return result;
  }
}
