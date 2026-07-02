import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:pdfrx/pdfrx.dart';

@immutable
class PdfTextSearchResult {
  const PdfTextSearchResult({
    required this.pageId,
    required this.pdfPageNumber,
    required this.matchText,
    required this.snippet,
    required this.normalizedBounds,
    required this.pdfPageSize,
  });

  final String pageId;
  final int pdfPageNumber;
  final String matchText;
  final String snippet;
  final Rect normalizedBounds;
  final Size pdfPageSize;
}

abstract class NotebookPdfTextSearcher {
  Future<List<PdfTextSearchResult>> search({
    required Iterable<NotePage> pages,
    required String query,
  });

  Future<void> dispose();
}

class PdfrxNotebookPdfTextSearcher implements NotebookPdfTextSearcher {
  final Map<String, Future<PdfDocument>> _documentsByPath = {};
  final Map<_PdfPageCacheKey, Future<PdfPageText?>> _textByPage = {};

  @override
  Future<List<PdfTextSearchResult>> search({
    required Iterable<NotePage> pages,
    required String query,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final results = <PdfTextSearchResult>[];
    for (final notePage in pages) {
      final background = notePage.pdfBackground;
      if (background == null) {
        continue;
      }

      final document = await _documentFor(background.filePath);
      final pageIndex = background.pageNumber - 1;
      if (pageIndex < 0 || pageIndex >= document.pages.length) {
        continue;
      }

      final pdfPage = document.pages[pageIndex];
      final pageText = await _textFor(
        filePath: background.filePath,
        pdfPage: pdfPage,
      );
      if (pageText == null || pageText.fullText.isEmpty) {
        continue;
      }

      await for (final match in pageText.allMatches(normalizedQuery)) {
        final bounds = match.bounds.toRect(page: pdfPage);
        results.add(
          PdfTextSearchResult(
            pageId: notePage.id,
            pdfPageNumber: background.pageNumber,
            matchText: match.text,
            snippet: buildPdfSearchSnippet(
              pageText.fullText,
              match.start,
              match.end,
            ),
            normalizedBounds: Rect.fromLTRB(
              _normalized(bounds.left, pdfPage.width),
              _normalized(bounds.top, pdfPage.height),
              _normalized(bounds.right, pdfPage.width),
              _normalized(bounds.bottom, pdfPage.height),
            ),
            pdfPageSize: Size(pdfPage.width, pdfPage.height),
          ),
        );
      }
    }

    return List.unmodifiable(results);
  }

  Future<PdfDocument> _documentFor(String filePath) {
    return _documentsByPath.putIfAbsent(
      filePath,
      () => PdfDocument.openFile(filePath),
    );
  }

  Future<PdfPageText?> _textFor({
    required String filePath,
    required PdfPage pdfPage,
  }) {
    final key = _PdfPageCacheKey(filePath, pdfPage.pageNumber);
    return _textByPage.putIfAbsent(key, pdfPage.loadStructuredText);
  }

  @override
  Future<void> dispose() async {
    final documentFutures = _documentsByPath.values.toList();
    _documentsByPath.clear();
    _textByPage.clear();
    for (final documentFuture in documentFutures) {
      try {
        final document = await documentFuture;
        await document.dispose();
      } catch (_) {
        // Opening may have failed before there was a document to dispose.
      }
    }
  }
}

String buildPdfSearchSnippet(String text, int matchStart, int matchEnd) {
  const surroundingCharacters = 42;
  final start = math.max(0, matchStart - surroundingCharacters);
  final end = math.min(text.length, matchEnd + surroundingCharacters);
  final snippet = text
      .substring(start, end)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${start > 0 ? '…' : ''}$snippet${end < text.length ? '…' : ''}';
}

double _normalized(double value, double extent) {
  if (extent <= 0) {
    return 0;
  }
  return (value / extent).clamp(0, 1).toDouble();
}

@immutable
class _PdfPageCacheKey {
  const _PdfPageCacheKey(this.filePath, this.pageNumber);

  final String filePath;
  final int pageNumber;

  @override
  bool operator ==(Object other) {
    return other is _PdfPageCacheKey &&
        other.filePath == filePath &&
        other.pageNumber == pageNumber;
  }

  @override
  int get hashCode => Object.hash(filePath, pageNumber);
}
