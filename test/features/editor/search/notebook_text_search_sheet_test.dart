import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/search/notebook_text_search_service.dart';
import 'package:inknest_notes/features/editor/search/notebook_text_search_sheet.dart';
import 'package:inknest_notes/models/note_page.dart';

void main() {
  testWidgets('labels inserted-image OCR results in the unified search list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: NotebookTextSearchSheet(
              searchService: _FakeNotebookTextSearchService(),
              pages: const [NotePage(id: 'page-1', width: 100, height: 100)],
              initialQuery: '',
              onQueryChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'photo');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.textContaining('Image text'), findsOneWidget);
    expect(find.text('Photo class notes'), findsOneWidget);
    expect(find.byIcon(Icons.image_search_outlined), findsOneWidget);
  });
}

class _FakeNotebookTextSearchService extends NotebookTextSearchService {
  @override
  Future<NotebookTextSearchResponse> search({
    required List<NotePage> pages,
    required String query,
    void Function(int completed, int total)? onProgress,
  }) async {
    onProgress?.call(1, 1);
    return const NotebookTextSearchResponse(
      results: [
        NotebookTextSearchResult(
          source: NotebookTextSearchSource.image,
          pageId: 'page-1',
          notebookPageNumber: 1,
          imageId: 'image-1',
          snippet: 'Photo class notes',
          matchText: 'Photo',
          highlightRects: [Rect.fromLTWH(10, 10, 20, 10)],
        ),
      ],
      pdfPageCount: 0,
      pdfTextPageCount: 0,
      unavailablePdfPageCount: 0,
      imageCount: 1,
      imageTextCount: 1,
      unavailableImageCount: 0,
      searchableTextBoxCount: 0,
      isTruncated: false,
    );
  }
}
