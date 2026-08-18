import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/search/pdf_ocr_text_extractor.dart';
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/features/recognition/raster_text_recognizer.dart';

void main() {
  group('LayeredPdfPageTextExtractor', () {
    test(
      'keeps usable embedded text and only sends scanned pages to OCR',
      () async {
        const embeddedPage = PdfSourcePageRef(
          filePath: '/tmp/mixed.pdf',
          pageNumber: 1,
        );
        const scannedPage = PdfSourcePageRef(
          filePath: '/tmp/mixed.pdf',
          pageNumber: 2,
        );
        final embeddedData = _pageData('Chapter 1');
        final ocrData = _pageData('扫描内容', source: PdfSearchTextSource.ocr);
        final embedded = _FakeExtractor({
          embeddedPage: embeddedData,
          scannedPage: const PdfSearchPageData(
            fullText: '',
            characterRects: [],
            pageSize: Size(100, 200),
          ),
        });
        final ocr = _FakeExtractor({scannedPage: ocrData});
        final extractor = LayeredPdfPageTextExtractor(
          embeddedTextExtractor: embedded,
          ocrExtractor: ocr,
        );
        final progress = <(int, int)>[];

        final result = await extractor.extract(const [
          embeddedPage,
          scannedPage,
        ], onProgress: (completed, total) => progress.add((completed, total)));

        expect(result[embeddedPage], same(embeddedData));
        expect(result[scannedPage], same(ocrData));
        expect(ocr.requestedPages.single, {scannedPage});
        expect(progress.last, (2, 2));
      },
    );
  });

  group('MlKitPdfPageTextExtractor', () {
    test('maps recognized line bounds to the PDF coordinate space', () async {
      const page = PdfSourcePageRef(
        filePath: '/tmp/scanned.pdf',
        pageNumber: 1,
      );
      final cache = _MemoryOcrCache();
      final extractor = MlKitPdfPageTextExtractor(
        recognizer: _FakeRecognizer(),
        rasterizer: _FakeRasterizer(),
        cache: cache,
      );

      final result = await extractor.extract(const [page]);
      final data = result[page]!;

      expect(data.fullText, '你好 OCR');
      expect(data.source, PdfSearchTextSource.ocr);
      expect(data.pageSize, const Size(100, 200));
      expect(data.characterRects, hasLength(6));
      expect(data.characterRects.first, const Rect.fromLTWH(10, 20, 10, 20));
      expect(cache.values[page], same(data));
    });

    test('reuses persistent OCR data without rasterizing again', () async {
      const page = PdfSourcePageRef(
        filePath: '/tmp/scanned.pdf',
        pageNumber: 3,
      );
      final cached = _pageData('cached', source: PdfSearchTextSource.ocr);
      final cache = _MemoryOcrCache()..values[page] = cached;
      final rasterizer = _FakeRasterizer();
      final recognizer = _FakeRecognizer();
      final extractor = MlKitPdfPageTextExtractor(
        recognizer: recognizer,
        rasterizer: rasterizer,
        cache: cache,
      );

      final result = await extractor.extract(const [page]);

      expect(result[page], same(cached));
      expect(rasterizer.callCount, 0);
      expect(recognizer.callCount, 0);
    });
  });

  test(
    'file cache survives recreation and invalidates changed PDF bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-pdf-ocr-');
      try {
        final assets = Directory('${root.path}/assets')..createSync();
        final source = File('${assets.path}/scan.pdf')..writeAsStringSync('v1');
        final page = PdfSourcePageRef(filePath: source.path, pageNumber: 1);
        final data = _pageData('persistent', source: PdfSearchTextSource.ocr);

        await FilePdfOcrCache().write(
          page,
          data,
          engineIdentifier: 'test-engine',
        );
        final restored = await FilePdfOcrCache().read(
          page,
          engineIdentifier: 'test-engine',
        );

        expect(restored?.fullText, data.fullText);
        expect(restored?.characterRects, data.characterRects);
        expect(restored?.source, PdfSearchTextSource.ocr);
        expect(
          Directory(
            '${root.path}/derived/recognition/v$pdfOcrSchemaVersion/pdf',
          ).listSync().whereType<File>(),
          hasLength(1),
        );

        source.writeAsStringSync('changed PDF bytes');
        final invalidated = await FilePdfOcrCache().read(
          page,
          engineIdentifier: 'test-engine',
        );
        expect(invalidated, isNull);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

PdfSearchPageData _pageData(
  String text, {
  PdfSearchTextSource source = PdfSearchTextSource.embedded,
}) {
  return PdfSearchPageData(
    fullText: text,
    characterRects: [
      for (var index = 0; index < text.length; index += 1)
        Rect.fromLTWH(index * 5, 5, 4, 8),
    ],
    pageSize: const Size(100, 200),
    source: source,
  );
}

class _FakeExtractor implements PdfPageTextExtractor {
  _FakeExtractor(this.values);

  final Map<PdfSourcePageRef, PdfSearchPageData?> values;
  final List<Set<PdfSourcePageRef>> requestedPages = [];

  @override
  Future<Map<PdfSourcePageRef, PdfSearchPageData?>> extract(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    final requested = pages.toSet();
    requestedPages.add(requested);
    var completed = 0;
    return {
      for (final page in requested)
        page: (() {
          completed += 1;
          onProgress?.call(completed, requested.length);
          return values[page];
        })(),
    };
  }
}

class _FakeRecognizer implements RasterTextRecognizer {
  int callCount = 0;

  @override
  Future<RasterTextRecognitionResult> recognize(
    RasterTextRecognitionRequest request,
  ) async {
    callCount += 1;
    return const RasterTextRecognitionResult(
      text: '你好 OCR',
      lines: [
        RasterTextLine(text: '你好 OCR', bounds: Rect.fromLTWH(20, 20, 120, 20)),
      ],
      engineIdentifier: 'fake-ocr-v1',
    );
  }
}

class _FakeRasterizer implements PdfOcrPageRasterizer {
  int callCount = 0;

  @override
  Future<Map<PdfSourcePageRef, RenderedPdfOcrPage?>> render(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    callCount += 1;
    final requested = pages.toList(growable: false);
    return {
      for (var index = 0; index < requested.length; index += 1)
        requested[index]: RenderedPdfOcrPage(
          rgbaBytes: Uint8List(200 * 200 * 4),
          width: 200,
          height: 200,
          sourcePageSize: const Size(100, 200),
        ),
    };
  }
}

class _MemoryOcrCache implements PdfOcrCache {
  final Map<PdfSourcePageRef, PdfSearchPageData> values = {};

  @override
  Future<PdfSearchPageData?> read(
    PdfSourcePageRef page, {
    required String engineIdentifier,
  }) async => values[page];

  @override
  Future<void> write(
    PdfSourcePageRef page,
    PdfSearchPageData data, {
    required String engineIdentifier,
  }) async {
    values[page] = data;
  }
}
