import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_text_box.dart';

enum NotebookTextSearchSource { pdf, textBox }

@immutable
class NotebookTextSearchResult {
  const NotebookTextSearchResult({
    required this.source,
    required this.pageId,
    required this.notebookPageNumber,
    required this.snippet,
    required this.matchText,
    this.sourcePageNumber,
    this.textBoxId,
    this.textBoxStyle,
    this.highlightRects = const [],
  });

  factory NotebookTextSearchResult.fromPdf(PdfTextSearchResult result) {
    return NotebookTextSearchResult(
      source: NotebookTextSearchSource.pdf,
      pageId: result.pageId,
      notebookPageNumber: result.notebookPageNumber,
      sourcePageNumber: result.sourcePageNumber,
      snippet: result.snippet,
      matchText: result.matchText,
      highlightRects: result.highlightRects,
    );
  }

  final NotebookTextSearchSource source;
  final String pageId;
  final int notebookPageNumber;
  final int? sourcePageNumber;
  final String? textBoxId;
  final NoteTextBoxStyle? textBoxStyle;
  final String snippet;
  final String matchText;
  final List<Rect> highlightRects;
}

@immutable
class NotebookTextSearchResponse {
  const NotebookTextSearchResponse({
    required this.results,
    required this.pdfPageCount,
    required this.pdfTextPageCount,
    required this.unavailablePdfPageCount,
    required this.searchableTextBoxCount,
    required this.isTruncated,
  });

  final List<NotebookTextSearchResult> results;
  final int pdfPageCount;
  final int pdfTextPageCount;
  final int unavailablePdfPageCount;
  final int searchableTextBoxCount;
  final bool isTruncated;

  bool get hasSearchableText =>
      pdfTextPageCount > 0 || searchableTextBoxCount > 0;
}

class NotebookTextSearchService {
  NotebookTextSearchService({
    PdfTextSearchService? pdfTextSearchService,
    this.maxResults = 250,
  }) : assert(maxResults > 0),
       _pdfTextSearchService = pdfTextSearchService ?? PdfTextSearchService();

  final PdfTextSearchService _pdfTextSearchService;
  final int maxResults;

  Future<NotebookTextSearchResponse> search({
    required List<NotePage> pages,
    required String query,
    PdfSearchProgressCallback? onProgress,
  }) async {
    final pdfResponse = await _pdfTextSearchService.search(
      pages: pages,
      query: query,
      onProgress: onProgress,
    );
    final searchableTextBoxCount = pages.fold<int>(
      0,
      (count, page) =>
          count +
          page.textBoxes
              .where((textBox) => textBox.text.trim().isNotEmpty)
              .length,
    );
    final normalizedQuery = query.trim().toLowerCase();
    final pdfResultsByPage = <String, List<PdfTextSearchResult>>{};
    for (final result in pdfResponse.results) {
      pdfResultsByPage.putIfAbsent(result.pageId, () => []).add(result);
    }

    final results = <NotebookTextSearchResult>[];
    var isTruncated = pdfResponse.isTruncated;

    bool addResult(NotebookTextSearchResult result) {
      if (results.length >= maxResults) {
        isTruncated = true;
        return false;
      }
      results.add(result);
      return true;
    }

    searchPages:
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex += 1) {
      final page = pages[pageIndex];
      for (final pdfResult in pdfResultsByPage[page.id] ?? const []) {
        if (!addResult(NotebookTextSearchResult.fromPdf(pdfResult))) {
          break searchPages;
        }
      }

      if (normalizedQuery.isEmpty) {
        continue;
      }
      for (final textBox in page.textBoxes) {
        final searchableText = textBox.text.toLowerCase();
        var matchStart = searchableText.indexOf(normalizedQuery);
        while (matchStart >= 0) {
          final matchEnd = matchStart + normalizedQuery.length;
          if (!addResult(
            NotebookTextSearchResult(
              source: NotebookTextSearchSource.textBox,
              pageId: page.id,
              notebookPageNumber: pageIndex + 1,
              textBoxId: textBox.id,
              textBoxStyle: textBox.style,
              snippet: _buildTextBoxSnippet(textBox.text, matchStart, matchEnd),
              matchText: textBox.text.substring(matchStart, matchEnd),
            ),
          )) {
            break searchPages;
          }
          matchStart = searchableText.indexOf(normalizedQuery, matchEnd);
        }
      }
    }

    return NotebookTextSearchResponse(
      results: List.unmodifiable(results),
      pdfPageCount: pdfResponse.pdfPageCount,
      pdfTextPageCount: pdfResponse.textPageCount,
      unavailablePdfPageCount: pdfResponse.unavailablePageCount,
      searchableTextBoxCount: searchableTextBoxCount,
      isTruncated: isTruncated,
    );
  }
}

String _buildTextBoxSnippet(String text, int start, int end) {
  const contextLength = 44;
  final snippetStart = math.max(0, start - contextLength);
  final snippetEnd = math.min(text.length, end + contextLength);
  final normalized = text
      .substring(snippetStart, snippetEnd)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final prefix = snippetStart > 0 ? '...' : '';
  final suffix = snippetEnd < text.length ? '...' : '';
  return '$prefix$normalized$suffix';
}
