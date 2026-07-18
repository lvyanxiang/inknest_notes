import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:pdfrx/pdfrx.dart';

@immutable
class PdfSourcePageRef {
  const PdfSourcePageRef({required this.filePath, required this.pageNumber});

  final String filePath;
  final int pageNumber;

  @override
  bool operator ==(Object other) {
    return other is PdfSourcePageRef &&
        other.filePath == filePath &&
        other.pageNumber == pageNumber;
  }

  @override
  int get hashCode => Object.hash(filePath, pageNumber);
}

@immutable
class PdfSearchPageData {
  const PdfSearchPageData({
    required this.fullText,
    required this.characterRects,
    required this.pageSize,
  });

  final String fullText;
  final List<Rect> characterRects;
  final Size pageSize;
}

@immutable
class PdfTextSearchResult {
  const PdfTextSearchResult({
    required this.pageId,
    required this.notebookPageNumber,
    required this.sourcePageNumber,
    required this.snippet,
    required this.matchText,
    required this.highlightRects,
  });

  final String pageId;
  final int notebookPageNumber;
  final int sourcePageNumber;
  final String snippet;
  final String matchText;
  final List<Rect> highlightRects;
}

@immutable
class PdfTextSearchResponse {
  const PdfTextSearchResponse({
    required this.results,
    required this.pdfPageCount,
    required this.textPageCount,
    required this.unavailablePageCount,
    required this.isTruncated,
  });

  final List<PdfTextSearchResult> results;
  final int pdfPageCount;
  final int textPageCount;
  final int unavailablePageCount;
  final bool isTruncated;
}

typedef PdfSearchProgressCallback = void Function(int completed, int total);

abstract class PdfPageTextExtractor {
  Future<Map<PdfSourcePageRef, PdfSearchPageData?>> extract(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  });
}

class PdfrxPdfPageTextExtractor implements PdfPageTextExtractor {
  const PdfrxPdfPageTextExtractor();

  @override
  Future<Map<PdfSourcePageRef, PdfSearchPageData?>> extract(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    final requestedPages = pages.toSet();
    final pagesByFile = <String, List<PdfSourcePageRef>>{};
    for (final page in requestedPages) {
      pagesByFile.putIfAbsent(page.filePath, () => []).add(page);
    }

    final extracted = <PdfSourcePageRef, PdfSearchPageData?>{};
    var completed = 0;

    for (final entry in pagesByFile.entries) {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(entry.key);
        entry.value.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

        for (final sourcePage in entry.value) {
          PdfSearchPageData? data;
          try {
            if (sourcePage.pageNumber > 0 &&
                sourcePage.pageNumber <= document.pages.length) {
              final page = document.pages[sourcePage.pageNumber - 1];
              final pageText = await page.loadStructuredText();
              data = PdfSearchPageData(
                fullText: pageText.fullText,
                characterRects: [
                  for (final rect in pageText.charRects)
                    rect.toRect(
                      page: page,
                      scaledPageSize: Size(page.width, page.height),
                    ),
                ],
                pageSize: Size(page.width, page.height),
              );
            }
          } catch (_) {
            data = null;
          }

          extracted[sourcePage] = data;
          completed += 1;
          onProgress?.call(completed, requestedPages.length);
        }
      } catch (_) {
        for (final sourcePage in entry.value) {
          if (extracted.containsKey(sourcePage)) {
            continue;
          }
          extracted[sourcePage] = null;
          completed += 1;
          onProgress?.call(completed, requestedPages.length);
        }
      } finally {
        try {
          await document?.dispose();
        } catch (_) {
          // A failed native document is already unusable.
        }
      }
    }

    return extracted;
  }
}

class PdfTextSearchService {
  PdfTextSearchService({
    this.extractor = const PdfrxPdfPageTextExtractor(),
    this.maxResults = 250,
  });

  final PdfPageTextExtractor extractor;
  final int maxResults;
  final Map<PdfSourcePageRef, PdfSearchPageData?> _pageCache = {};

  Future<PdfTextSearchResponse> search({
    required List<NotePage> pages,
    required String query,
    PdfSearchProgressCallback? onProgress,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final sourceRefs = <PdfSourcePageRef>{
      for (final page in pages)
        if (page.pdfBackground case final background?)
          PdfSourcePageRef(
            filePath: background.filePath,
            pageNumber: background.pageNumber,
          ),
    };
    final missingRefs = [
      for (final sourceRef in sourceRefs)
        if (!_pageCache.containsKey(sourceRef)) sourceRef,
    ];
    final cachedCount = sourceRefs.length - missingRefs.length;
    onProgress?.call(cachedCount, sourceRefs.length);

    if (missingRefs.isNotEmpty) {
      final extracted = await extractor.extract(
        missingRefs,
        onProgress: (completed, _) {
          onProgress?.call(cachedCount + completed, sourceRefs.length);
        },
      );
      for (final sourceRef in missingRefs) {
        _pageCache[sourceRef] = extracted[sourceRef];
      }
    }

    final results = <PdfTextSearchResult>[];
    var pdfPageCount = 0;
    var textPageCount = 0;
    var unavailablePageCount = 0;
    var isTruncated = false;

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex += 1) {
      final page = pages[pageIndex];
      final background = page.pdfBackground;
      if (background == null) {
        continue;
      }

      pdfPageCount += 1;
      final sourceRef = PdfSourcePageRef(
        filePath: background.filePath,
        pageNumber: background.pageNumber,
      );
      final pageData = _pageCache[sourceRef];
      if (pageData == null) {
        unavailablePageCount += 1;
        continue;
      }
      if (pageData.fullText.trim().isNotEmpty) {
        textPageCount += 1;
      }
      if (normalizedQuery.isEmpty || pageData.fullText.isEmpty) {
        continue;
      }

      final searchableText = pageData.fullText.toLowerCase();
      var matchStart = searchableText.indexOf(normalizedQuery);
      while (matchStart >= 0) {
        if (results.length >= maxResults) {
          isTruncated = true;
          break;
        }
        final matchEnd = matchStart + normalizedQuery.length;
        results.add(
          PdfTextSearchResult(
            pageId: page.id,
            notebookPageNumber: pageIndex + 1,
            sourcePageNumber: background.pageNumber,
            snippet: _buildSnippet(pageData.fullText, matchStart, matchEnd),
            matchText: pageData.fullText.substring(matchStart, matchEnd),
            highlightRects: _mapHighlightRects(
              pageData: pageData,
              pageSize: Size(page.width, page.height),
              start: matchStart,
              end: matchEnd,
            ),
          ),
        );
        matchStart = searchableText.indexOf(normalizedQuery, matchEnd);
      }

      if (isTruncated) {
        break;
      }
    }

    return PdfTextSearchResponse(
      results: List.unmodifiable(results),
      pdfPageCount: pdfPageCount,
      textPageCount: textPageCount,
      unavailablePageCount: unavailablePageCount,
      isTruncated: isTruncated,
    );
  }
}

String _buildSnippet(String text, int start, int end) {
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

List<Rect> _mapHighlightRects({
  required PdfSearchPageData pageData,
  required Size pageSize,
  required int start,
  required int end,
}) {
  if (pageData.pageSize.isEmpty || pageSize.isEmpty) {
    return const [];
  }

  final sourceRects = _mergeCharacterRects(
    text: pageData.fullText,
    characterRects: pageData.characterRects,
    start: start,
    end: end,
  );
  final scale = math.min(
    pageSize.width / pageData.pageSize.width,
    pageSize.height / pageData.pageSize.height,
  );
  final offset = Offset(
    (pageSize.width - pageData.pageSize.width * scale) / 2,
    (pageSize.height - pageData.pageSize.height * scale) / 2,
  );
  final pageBounds = Offset.zero & pageSize;

  return [
    for (final rect in sourceRects)
      Rect.fromLTRB(
        offset.dx + rect.left * scale,
        offset.dy + rect.top * scale,
        offset.dx + rect.right * scale,
        offset.dy + rect.bottom * scale,
      ).intersect(pageBounds),
  ].where((rect) => rect.isFinite && !rect.isEmpty).toList(growable: false);
}

List<Rect> _mergeCharacterRects({
  required String text,
  required List<Rect> characterRects,
  required int start,
  required int end,
}) {
  final safeStart = start.clamp(0, characterRects.length);
  final safeEnd = end.clamp(safeStart, characterRects.length);
  final merged = <Rect>[];
  Rect? current;

  void flush() {
    if (current case final rect?) {
      merged.add(rect.inflate(0.8));
      current = null;
    }
  }

  for (var index = safeStart; index < safeEnd; index += 1) {
    final rect = characterRects[index];
    final character = index < text.length ? text[index] : '';
    if (rect.isEmpty || character == '\n' || character == '\r') {
      flush();
      continue;
    }

    final existing = current;
    if (existing == null) {
      current = rect;
      continue;
    }

    final verticalOverlap =
        math.min(existing.bottom, rect.bottom) -
        math.max(existing.top, rect.top);
    final minimumHeight = math.min(existing.height, rect.height);
    final horizontalGap = math.max(
      rect.left - existing.right,
      existing.left - rect.right,
    );
    final isSameLine =
        verticalOverlap >= minimumHeight * 0.4 &&
        horizontalGap <= math.max(existing.height, rect.height) * 1.5;

    if (isSameLine) {
      current = existing.expandToInclude(rect);
    } else {
      flush();
      current = rect;
    }
  }
  flush();
  return merged;
}
