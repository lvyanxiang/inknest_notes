import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_background.dart';

void main() {
  test(
    'finds case-insensitive text and maps highlights into note page',
    () async {
      const fullText = 'Alpha beta\nGamma';
      final sourceRef = const PdfSourcePageRef(
        filePath: '/tmp/lesson.pdf',
        pageNumber: 2,
      );
      final extractor = _FakePdfPageTextExtractor({
        sourceRef: PdfSearchPageData(
          fullText: fullText,
          characterRects: [
            for (var index = 0; index < fullText.length; index += 1)
              fullText[index] == '\n'
                  ? Rect.zero
                  : Rect.fromLTWH(index * 10, 10, 8, 10),
          ],
          pageSize: const Size(200, 100),
        ),
      });
      final service = PdfTextSearchService(extractor: extractor);
      final page = NotePage(
        id: 'page-7',
        width: 400,
        height: 400,
        pdfBackground: const PdfBackground(
          assetPath: 'assets/lesson.pdf',
          resolvedFilePath: '/tmp/lesson.pdf',
          pageNumber: 2,
        ),
      );

      final response = await service.search(pages: [page], query: 'BETA');

      expect(response.results, hasLength(1));
      expect(response.textPageCount, 1);
      expect(response.unavailablePageCount, 0);
      expect(response.results.single.pageId, 'page-7');
      expect(response.results.single.notebookPageNumber, 1);
      expect(response.results.single.sourcePageNumber, 2);
      expect(response.results.single.matchText, 'beta');
      expect(response.results.single.snippet, 'Alpha beta Gamma');
      expect(response.results.single.highlightRects, hasLength(1));
      expect(
        response.results.single.highlightRects.single.left,
        closeTo(118.4, 0.01),
      );
      expect(
        response.results.single.highlightRects.single.top,
        closeTo(118.4, 0.01),
      );
    },
  );

  test(
    'reuses extracted source page for duplicates and later queries',
    () async {
      final sourceRef = const PdfSourcePageRef(
        filePath: '/tmp/shared.pdf',
        pageNumber: 1,
      );
      const fullText = 'one two';
      final extractor = _FakePdfPageTextExtractor({
        sourceRef: PdfSearchPageData(
          fullText: fullText,
          characterRects: [
            for (var index = 0; index < fullText.length; index += 1)
              Rect.fromLTWH(index * 8, 8, 7, 10),
          ],
          pageSize: const Size(100, 100),
        ),
      });
      final service = PdfTextSearchService(extractor: extractor);
      final pages = [
        _pdfPage(id: 'page-1', filePath: sourceRef.filePath),
        _pdfPage(id: 'page-2', filePath: sourceRef.filePath),
      ];

      final firstResponse = await service.search(pages: pages, query: 'one');
      final secondResponse = await service.search(pages: pages, query: 'two');

      expect(firstResponse.results, hasLength(2));
      expect(secondResponse.results, hasLength(2));
      expect(extractor.callCount, 1);
      expect(extractor.requestedPages.single, {sourceRef});
    },
  );

  test('reports PDFs without an extractable text layer', () async {
    final missingRef = const PdfSourcePageRef(
      filePath: '/tmp/missing.pdf',
      pageNumber: 1,
    );
    final emptyRef = const PdfSourcePageRef(
      filePath: '/tmp/scanned.pdf',
      pageNumber: 1,
    );
    final extractor = _FakePdfPageTextExtractor({
      missingRef: null,
      emptyRef: const PdfSearchPageData(
        fullText: '',
        characterRects: [],
        pageSize: Size(100, 100),
      ),
    });
    final service = PdfTextSearchService(extractor: extractor);

    final response = await service.search(
      pages: [
        _pdfPage(id: 'page-1', filePath: missingRef.filePath),
        _pdfPage(id: 'page-2', filePath: emptyRef.filePath),
      ],
      query: 'notes',
    );

    expect(response.pdfPageCount, 2);
    expect(response.textPageCount, 0);
    expect(response.unavailablePageCount, 1);
    expect(response.results, isEmpty);
  });
}

NotePage _pdfPage({required String id, required String filePath}) {
  return NotePage(
    id: id,
    width: 100,
    height: 100,
    pdfBackground: PdfBackground(
      assetPath: 'assets/source.pdf',
      resolvedFilePath: filePath,
      pageNumber: 1,
    ),
  );
}

class _FakePdfPageTextExtractor implements PdfPageTextExtractor {
  _FakePdfPageTextExtractor(this.pages);

  final Map<PdfSourcePageRef, PdfSearchPageData?> pages;
  final List<Set<PdfSourcePageRef>> requestedPages = [];
  int callCount = 0;

  @override
  Future<Map<PdfSourcePageRef, PdfSearchPageData?>> extract(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    callCount += 1;
    final requested = pages.toSet();
    requestedPages.add(requested);
    final result = <PdfSourcePageRef, PdfSearchPageData?>{};
    var completed = 0;
    for (final page in requested) {
      result[page] = this.pages[page];
      completed += 1;
      onProgress?.call(completed, requested.length);
    }
    return result;
  }
}
