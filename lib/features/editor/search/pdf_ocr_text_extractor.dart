import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/features/recognition/raster_text_recognizer.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

const int pdfOcrSchemaVersion = 1;

/// Uses selectable PDF text when it is meaningful and invokes OCR only for
/// pages that are empty, unreadable, or contain only a trivial page marker.
class LayeredPdfPageTextExtractor implements PdfPageTextExtractor {
  LayeredPdfPageTextExtractor({
    PdfPageTextExtractor? embeddedTextExtractor,
    PdfPageTextExtractor? ocrExtractor,
  }) : embeddedTextExtractor =
           embeddedTextExtractor ?? const PdfrxPdfPageTextExtractor(),
       ocrExtractor = ocrExtractor ?? MlKitPdfPageTextExtractor();

  final PdfPageTextExtractor embeddedTextExtractor;
  final PdfPageTextExtractor ocrExtractor;

  @override
  Future<Map<PdfSourcePageRef, PdfSearchPageData?>> extract(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    final requested = pages.toSet();
    final embedded = await embeddedTextExtractor.extract(requested);
    final needsOcr = <PdfSourcePageRef>[
      for (final page in requested)
        if (!_hasUsableEmbeddedText(embedded[page])) page,
    ];
    final completedWithoutOcr = requested.length - needsOcr.length;
    onProgress?.call(completedWithoutOcr, requested.length);
    if (needsOcr.isEmpty) {
      return embedded;
    }

    final recognized = await ocrExtractor.extract(
      needsOcr,
      onProgress: (completed, _) {
        onProgress?.call(completedWithoutOcr + completed, requested.length);
      },
    );
    return {
      for (final page in requested) page: recognized[page] ?? embedded[page],
    };
  }
}

bool _hasUsableEmbeddedText(PdfSearchPageData? data) {
  if (data == null || !data.characterRects.any((rect) => !rect.isEmpty)) {
    return false;
  }
  final meaningfulCharacters = RegExp(
    r'[A-Za-z0-9\u3400-\u4DBF\u4E00-\u9FFF]',
  ).allMatches(data.fullText).length;
  return meaningfulCharacters >= 2;
}

@immutable
class RenderedPdfOcrPage {
  const RenderedPdfOcrPage({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.sourcePageSize,
  });

  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final Size sourcePageSize;
}

abstract interface class PdfOcrPageRasterizer {
  Future<Map<PdfSourcePageRef, RenderedPdfOcrPage?>> render(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  });
}

class PdfrxPdfOcrPageRasterizer implements PdfOcrPageRasterizer {
  const PdfrxPdfOcrPageRasterizer({this.maximumPixelDimension = 2200});

  final int maximumPixelDimension;

  @override
  Future<Map<PdfSourcePageRef, RenderedPdfOcrPage?>> render(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    final requested = pages.toSet();
    final pagesByFile = <String, List<PdfSourcePageRef>>{};
    for (final page in requested) {
      pagesByFile.putIfAbsent(page.filePath, () => []).add(page);
    }

    final rendered = <PdfSourcePageRef, RenderedPdfOcrPage?>{};
    var completed = 0;
    for (final entry in pagesByFile.entries) {
      pdfrx.PdfDocument? document;
      try {
        document = await pdfrx.PdfDocument.openFile(entry.key);
        entry.value.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
        for (final sourcePage in entry.value) {
          RenderedPdfOcrPage? result;
          try {
            if (sourcePage.pageNumber > 0 &&
                sourcePage.pageNumber <= document.pages.length) {
              final page = await document.pages[sourcePage.pageNumber - 1]
                  .ensureLoaded();
              final longest = math.max(page.width, page.height);
              final scale = math.min(3.0, maximumPixelDimension / longest);
              final width = math.max(1, (page.width * scale).round());
              final height = math.max(1, (page.height * scale).round());
              final pdfImage = await page.render(
                fullWidth: width.toDouble(),
                fullHeight: height.toDouble(),
                backgroundColor: 0xffffffff,
              );
              if (pdfImage != null) {
                try {
                  final image = await pdfImage.createImage();
                  try {
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    );
                    if (bytes != null) {
                      result = RenderedPdfOcrPage(
                        rgbaBytes: bytes.buffer.asUint8List(
                          bytes.offsetInBytes,
                          bytes.lengthInBytes,
                        ),
                        width: image.width,
                        height: image.height,
                        sourcePageSize: Size(page.width, page.height),
                      );
                    }
                  } finally {
                    image.dispose();
                  }
                } finally {
                  pdfImage.dispose();
                }
              }
            }
          } catch (_) {
            result = null;
          }
          rendered[sourcePage] = result;
          completed += 1;
          onProgress?.call(completed, requested.length);
        }
      } catch (_) {
        for (final sourcePage in entry.value) {
          if (rendered.containsKey(sourcePage)) continue;
          rendered[sourcePage] = null;
          completed += 1;
          onProgress?.call(completed, requested.length);
        }
      } finally {
        try {
          await document?.dispose();
        } catch (_) {
          // A failed native document is already unusable.
        }
      }
    }
    return rendered;
  }
}

abstract interface class PdfOcrCache {
  Future<PdfSearchPageData?> read(
    PdfSourcePageRef page, {
    required String engineIdentifier,
  });

  Future<void> write(
    PdfSourcePageRef page,
    PdfSearchPageData data, {
    required String engineIdentifier,
  });
}

class FilePdfOcrCache implements PdfOcrCache {
  FilePdfOcrCache();

  final Map<String, _FingerprintMemo> _fingerprints = {};

  @override
  Future<PdfSearchPageData?> read(
    PdfSourcePageRef page, {
    required String engineIdentifier,
  }) async {
    try {
      final fingerprint = await _fingerprint(page.filePath);
      final file = _cacheFile(page);
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, Object?> ||
          value['schemaVersion'] != pdfOcrSchemaVersion ||
          value['engineIdentifier'] != engineIdentifier ||
          value['sourceFingerprint'] != fingerprint ||
          value['pageNumber'] != page.pageNumber) {
        return null;
      }
      return _pageDataFromJson(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(
    PdfSourcePageRef page,
    PdfSearchPageData data, {
    required String engineIdentifier,
  }) async {
    try {
      final fingerprint = await _fingerprint(page.filePath);
      final file = _cacheFile(page);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'schemaVersion': pdfOcrSchemaVersion,
          'engineIdentifier': engineIdentifier,
          'sourceFingerprint': fingerprint,
          'pageNumber': page.pageNumber,
          ..._pageDataToJson(data),
        }),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } catch (_) {
      // OCR remains useful for this search even when its disposable cache
      // cannot be persisted.
    }
  }

  Future<String> _fingerprint(String path) async {
    final file = File(path);
    final stat = await file.stat();
    final memo = _fingerprints[path];
    if (memo != null &&
        memo.size == stat.size &&
        memo.modified == stat.modified) {
      return memo.digest;
    }
    final digest = (await sha256.bind(file.openRead()).first).toString();
    _fingerprints[path] = _FingerprintMemo(
      size: stat.size,
      modified: stat.modified,
      digest: digest,
    );
    return digest;
  }

  File _cacheFile(PdfSourcePageRef page) {
    final sourceKey = sha256
        .convert(utf8.encode('${page.filePath}|${page.pageNumber}'))
        .toString();
    final notebookRoot = _findNotebookRoot(page.filePath);
    return File(
      '${notebookRoot.path}/derived/recognition/v$pdfOcrSchemaVersion/'
      'pdf/$sourceKey.json',
    );
  }
}

class _FingerprintMemo {
  const _FingerprintMemo({
    required this.size,
    required this.modified,
    required this.digest,
  });

  final int size;
  final DateTime modified;
  final String digest;
}

Directory _findNotebookRoot(String filePath) {
  var directory = File(filePath).parent;
  while (directory.path != directory.parent.path) {
    final segments = directory.uri.pathSegments.where(
      (part) => part.isNotEmpty,
    );
    if (segments.isNotEmpty && segments.last == 'assets') {
      return directory.parent;
    }
    directory = directory.parent;
  }
  return File(filePath).parent;
}

class MlKitPdfPageTextExtractor implements PdfPageTextExtractor {
  MlKitPdfPageTextExtractor({
    RasterTextRecognizer? recognizer,
    PdfOcrPageRasterizer? rasterizer,
    PdfOcrCache? cache,
  }) : recognizer = recognizer ?? const MlKitRasterTextRecognizer(),
       rasterizer = rasterizer ?? const PdfrxPdfOcrPageRasterizer(),
       cache = cache ?? FilePdfOcrCache();

  final RasterTextRecognizer recognizer;
  final PdfOcrPageRasterizer rasterizer;
  final PdfOcrCache cache;

  @override
  Future<Map<PdfSourcePageRef, PdfSearchPageData?>> extract(
    Iterable<PdfSourcePageRef> pages, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    final requested = pages.toList(growable: false);
    final results = <PdfSourcePageRef, PdfSearchPageData?>{};
    final missing = <PdfSourcePageRef>[];
    var completed = 0;
    for (final page in requested) {
      final cached = await cache.read(
        page,
        engineIdentifier: MlKitRasterTextRecognizer.engineIdentifier,
      );
      if (cached == null) {
        missing.add(page);
      } else {
        results[page] = cached;
        completed += 1;
        onProgress?.call(completed, requested.length);
      }
    }

    if (missing.isEmpty) {
      return results;
    }

    final rendered = await rasterizer.render(missing);
    for (final page in missing) {
      PdfSearchPageData? data;
      final bitmap = rendered[page];
      if (bitmap != null) {
        try {
          final recognized = await recognizer.recognize(
            RasterTextRecognitionRequest(
              rgbaBytes: bitmap.rgbaBytes,
              width: bitmap.width,
              height: bitmap.height,
            ),
          );
          data = _pageDataFromRecognition(recognized, bitmap);
          await cache.write(
            page,
            data,
            engineIdentifier: recognized.engineIdentifier,
          );
        } catch (_) {
          data = null;
        }
      }
      results[page] = data;
      completed += 1;
      onProgress?.call(completed, requested.length);
    }
    return results;
  }
}

PdfSearchPageData _pageDataFromRecognition(
  RasterTextRecognitionResult recognition,
  RenderedPdfOcrPage bitmap,
) {
  final sourceLines =
      recognition.lines.isEmpty && recognition.text.trim().isNotEmpty
      ? [
          RasterTextLine(
            text: recognition.text.trim(),
            bounds: Rect.fromLTWH(
              0,
              0,
              bitmap.width.toDouble(),
              bitmap.height.toDouble(),
            ),
          ),
        ]
      : recognition.lines;
  final lines = [...sourceLines]
    ..sort((first, second) {
      final vertical = first.bounds.top.compareTo(second.bounds.top);
      return vertical != 0
          ? vertical
          : first.bounds.left.compareTo(second.bounds.left);
    });
  final text = StringBuffer();
  final characterRects = <Rect>[];
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final line = lines[lineIndex];
    if (lineIndex > 0) {
      text.write('\n');
      characterRects.add(Rect.zero);
    }
    text.write(line.text);
    final scaled = Rect.fromLTRB(
      line.bounds.left / bitmap.width * bitmap.sourcePageSize.width,
      line.bounds.top / bitmap.height * bitmap.sourcePageSize.height,
      line.bounds.right / bitmap.width * bitmap.sourcePageSize.width,
      line.bounds.bottom / bitmap.height * bitmap.sourcePageSize.height,
    );
    final characterWidth = line.text.isEmpty
        ? 0.0
        : scaled.width / line.text.length;
    for (var index = 0; index < line.text.length; index += 1) {
      characterRects.add(
        Rect.fromLTWH(
          scaled.left + characterWidth * index,
          scaled.top,
          characterWidth,
          scaled.height,
        ),
      );
    }
  }
  return PdfSearchPageData(
    fullText: text.toString(),
    characterRects: List.unmodifiable(characterRects),
    pageSize: bitmap.sourcePageSize,
    source: PdfSearchTextSource.ocr,
  );
}

Map<String, Object?> _pageDataToJson(PdfSearchPageData data) => {
  'fullText': data.fullText,
  'characterRects': [
    for (final rect in data.characterRects)
      [rect.left, rect.top, rect.right, rect.bottom],
  ],
  'pageSize': [data.pageSize.width, data.pageSize.height],
  'source': data.source.name,
};

PdfSearchPageData _pageDataFromJson(Map<String, Object?> json) {
  final rawSize = json['pageSize'] as List<Object?>;
  final rawRects = json['characterRects'] as List<Object?>;
  return PdfSearchPageData(
    fullText: json['fullText'] as String,
    characterRects: [
      for (final value in rawRects)
        if (value case final List<Object?> rect when rect.length == 4)
          Rect.fromLTRB(
            (rect[0] as num).toDouble(),
            (rect[1] as num).toDouble(),
            (rect[2] as num).toDouble(),
            (rect[3] as num).toDouble(),
          ),
    ],
    pageSize: Size(
      (rawSize[0] as num).toDouble(),
      (rawSize[1] as num).toDouble(),
    ),
    source: PdfSearchTextSource.values.byName(json['source'] as String),
  );
}
