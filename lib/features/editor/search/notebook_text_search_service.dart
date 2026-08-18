import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:inknest_notes/features/editor/search/image_text_search_service.dart';
import 'package:inknest_notes/features/editor/search/pdf_ocr_text_extractor.dart';
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_text_box.dart';

enum NotebookTextSearchSource { pdf, image, textBox }

@immutable
class NotebookTextSearchResult {
  const NotebookTextSearchResult({
    required this.source,
    required this.pageId,
    required this.notebookPageNumber,
    required this.snippet,
    required this.matchText,
    this.sourcePageNumber,
    this.pdfTextSource,
    this.imageId,
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
      pdfTextSource: result.source,
      snippet: result.snippet,
      matchText: result.matchText,
      highlightRects: result.highlightRects,
    );
  }

  factory NotebookTextSearchResult.fromImage(ImageTextSearchResult result) {
    return NotebookTextSearchResult(
      source: NotebookTextSearchSource.image,
      pageId: result.pageId,
      notebookPageNumber: result.notebookPageNumber,
      imageId: result.imageId,
      snippet: result.snippet,
      matchText: result.matchText,
      highlightRects: result.highlightRects,
    );
  }

  final NotebookTextSearchSource source;
  final String pageId;
  final int notebookPageNumber;
  final int? sourcePageNumber;
  final PdfSearchTextSource? pdfTextSource;
  final String? imageId;
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
    required this.imageCount,
    required this.imageTextCount,
    required this.unavailableImageCount,
    required this.searchableTextBoxCount,
    required this.isTruncated,
  });

  final List<NotebookTextSearchResult> results;
  final int pdfPageCount;
  final int pdfTextPageCount;
  final int unavailablePdfPageCount;
  final int imageCount;
  final int imageTextCount;
  final int unavailableImageCount;
  final int searchableTextBoxCount;
  final bool isTruncated;

  bool get hasSearchableText =>
      pdfTextPageCount > 0 || imageTextCount > 0 || searchableTextBoxCount > 0;
}

class NotebookTextSearchService {
  NotebookTextSearchService({
    PdfTextSearchService? pdfTextSearchService,
    ImageTextSearchService? imageTextSearchService,
    this.maxResults = 250,
  }) : assert(maxResults > 0),
       _pdfTextSearchService =
           pdfTextSearchService ??
           PdfTextSearchService(extractor: LayeredPdfPageTextExtractor()),
       _imageTextSearchService =
           imageTextSearchService ?? ImageTextSearchService();

  final PdfTextSearchService _pdfTextSearchService;
  final ImageTextSearchService _imageTextSearchService;
  final int maxResults;

  Future<NotebookTextSearchResponse> search({
    required List<NotePage> pages,
    required String query,
    PdfSearchProgressCallback? onProgress,
  }) async {
    final pdfSourceCount = {
      for (final page in pages)
        if (page.pdfBackground case final background?)
          PdfSourcePageRef(
            filePath: background.filePath,
            pageNumber: background.pageNumber,
          ),
    }.length;
    final imageSourceCount = {
      for (final page in pages)
        for (final image in page.images) image.filePath,
    }.length;
    final totalRecognitionSources = pdfSourceCount + imageSourceCount;
    final pdfResponse = await _pdfTextSearchService.search(
      pages: pages,
      query: query,
      onProgress: (completed, _) {
        onProgress?.call(completed, totalRecognitionSources);
      },
    );
    final imageResponse = await _imageTextSearchService.search(
      pages: pages,
      query: query,
      onProgress: (completed, _) {
        onProgress?.call(pdfSourceCount + completed, totalRecognitionSources);
      },
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
    final imageResultsByPage = <String, List<ImageTextSearchResult>>{};
    for (final result in imageResponse.results) {
      imageResultsByPage.putIfAbsent(result.pageId, () => []).add(result);
    }

    final results = <NotebookTextSearchResult>[];
    var isTruncated = pdfResponse.isTruncated || imageResponse.isTruncated;

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
      for (final imageResult in imageResultsByPage[page.id] ?? const []) {
        if (!addResult(NotebookTextSearchResult.fromImage(imageResult))) {
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
      imageCount: imageResponse.imageCount,
      imageTextCount: imageResponse.textImageCount,
      unavailableImageCount: imageResponse.unavailableImageCount,
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
