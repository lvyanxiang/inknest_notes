import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image_lib;
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/features/recognition/raster_text_recognizer.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';

const int imageOcrSchemaVersion = 1;

@immutable
class ImageSourceRef {
  const ImageSourceRef({required this.filePath});

  final String filePath;

  @override
  bool operator ==(Object other) =>
      other is ImageSourceRef && other.filePath == filePath;

  @override
  int get hashCode => filePath.hashCode;
}

@immutable
class ImageSearchData {
  const ImageSearchData({
    required this.fullText,
    required this.normalizedCharacterRects,
  });

  final String fullText;
  final List<Rect> normalizedCharacterRects;
}

abstract interface class ImageTextExtractor {
  Future<Map<ImageSourceRef, ImageSearchData?>> extract(
    Iterable<ImageSourceRef> images, {
    PdfSearchProgressCallback? onProgress,
  });
}

abstract interface class ImageOcrCache {
  Future<ImageSearchData?> read(
    ImageSourceRef image, {
    required String engineIdentifier,
  });

  Future<void> write(
    ImageSourceRef image,
    ImageSearchData data, {
    required String engineIdentifier,
  });
}

class FileImageOcrCache implements ImageOcrCache {
  final Map<String, _ImageFingerprintMemo> _fingerprints = {};

  @override
  Future<ImageSearchData?> read(
    ImageSourceRef image, {
    required String engineIdentifier,
  }) async {
    try {
      final fingerprint = await _fingerprint(image.filePath);
      final file = _cacheFile(image);
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, Object?> ||
          value['schemaVersion'] != imageOcrSchemaVersion ||
          value['engineIdentifier'] != engineIdentifier ||
          value['sourceFingerprint'] != fingerprint) {
        return null;
      }
      return _dataFromJson(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(
    ImageSourceRef image,
    ImageSearchData data, {
    required String engineIdentifier,
  }) async {
    try {
      final file = _cacheFile(image);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'schemaVersion': imageOcrSchemaVersion,
          'engineIdentifier': engineIdentifier,
          'sourceFingerprint': await _fingerprint(image.filePath),
          ..._dataToJson(data),
        }),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } catch (_) {
      // Recognition remains available for this search when disposable cache
      // persistence is unavailable.
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
    _fingerprints[path] = _ImageFingerprintMemo(
      size: stat.size,
      modified: stat.modified,
      digest: digest,
    );
    return digest;
  }

  File _cacheFile(ImageSourceRef source) {
    final sourceKey = sha256.convert(utf8.encode(source.filePath)).toString();
    final notebookRoot = _findNotebookRoot(source.filePath);
    return File(
      '${notebookRoot.path}/derived/recognition/v$imageOcrSchemaVersion/'
      'images/$sourceKey.json',
    );
  }
}

class _ImageFingerprintMemo {
  const _ImageFingerprintMemo({
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

class MlKitImageTextExtractor implements ImageTextExtractor {
  MlKitImageTextExtractor({
    RasterTextRecognizer? recognizer,
    ImageOcrCache? cache,
    this.maximumPixelDimension = 2200,
  }) : recognizer = recognizer ?? const MlKitRasterTextRecognizer(),
       cache = cache ?? FileImageOcrCache();

  final RasterTextRecognizer recognizer;
  final ImageOcrCache cache;
  final int maximumPixelDimension;

  @override
  Future<Map<ImageSourceRef, ImageSearchData?>> extract(
    Iterable<ImageSourceRef> images, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    final requested = images.toSet();
    final results = <ImageSourceRef, ImageSearchData?>{};
    var completed = 0;
    for (final source in requested) {
      var data = await cache.read(
        source,
        engineIdentifier: MlKitRasterTextRecognizer.engineIdentifier,
      );
      data ??= await _recognize(source);
      results[source] = data;
      completed += 1;
      onProgress?.call(completed, requested.length);
    }
    return results;
  }

  Future<ImageSearchData?> _recognize(ImageSourceRef source) async {
    try {
      final input = await compute(
        _decodeImageForOcr,
        _ImageDecodeRequest(
          bytes: await File(source.filePath).readAsBytes(),
          maximumPixelDimension: maximumPixelDimension,
        ),
      );
      if (input == null) return null;
      final recognized = await recognizer.recognize(
        RasterTextRecognitionRequest(
          rgbaBytes: input.rgbaBytes,
          width: input.width,
          height: input.height,
        ),
      );
      final data = _dataFromRecognition(recognized, input);
      await cache.write(
        source,
        data,
        engineIdentifier: recognized.engineIdentifier,
      );
      return data;
    } catch (_) {
      return null;
    }
  }
}

@immutable
class _ImageDecodeRequest {
  const _ImageDecodeRequest({
    required this.bytes,
    required this.maximumPixelDimension,
  });

  final Uint8List bytes;
  final int maximumPixelDimension;
}

@immutable
class _DecodedOcrImage {
  const _DecodedOcrImage({
    required this.rgbaBytes,
    required this.width,
    required this.height,
  });

  final Uint8List rgbaBytes;
  final int width;
  final int height;
}

_DecodedOcrImage? _decodeImageForOcr(_ImageDecodeRequest request) {
  var decoded = image_lib.decodeImage(request.bytes);
  if (decoded == null) return null;
  decoded = image_lib.bakeOrientation(decoded);
  final longest = math.max(decoded.width, decoded.height);
  if (longest > request.maximumPixelDimension) {
    final scale = request.maximumPixelDimension / longest;
    decoded = image_lib.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
      interpolation: image_lib.Interpolation.linear,
    );
  }
  return _DecodedOcrImage(
    rgbaBytes: decoded.getBytes(order: image_lib.ChannelOrder.rgba),
    width: decoded.width,
    height: decoded.height,
  );
}

ImageSearchData _dataFromRecognition(
  RasterTextRecognitionResult recognition,
  _DecodedOcrImage input,
) {
  final lines = [...recognition.lines]
    ..sort((first, second) {
      final vertical = first.bounds.top.compareTo(second.bounds.top);
      return vertical != 0
          ? vertical
          : first.bounds.left.compareTo(second.bounds.left);
    });
  final text = StringBuffer();
  final rects = <Rect>[];
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final line = lines[lineIndex];
    if (lineIndex > 0) {
      text.write('\n');
      rects.add(Rect.zero);
    }
    text.write(line.text);
    final normalized = Rect.fromLTRB(
      line.bounds.left / input.width,
      line.bounds.top / input.height,
      line.bounds.right / input.width,
      line.bounds.bottom / input.height,
    ).intersect(const Rect.fromLTWH(0, 0, 1, 1));
    final characterWidth = line.text.isEmpty
        ? 0.0
        : normalized.width / line.text.length;
    for (var index = 0; index < line.text.length; index += 1) {
      rects.add(
        Rect.fromLTWH(
          normalized.left + characterWidth * index,
          normalized.top,
          characterWidth,
          normalized.height,
        ),
      );
    }
  }
  return ImageSearchData(
    fullText: text.toString(),
    normalizedCharacterRects: List.unmodifiable(rects),
  );
}

Map<String, Object?> _dataToJson(ImageSearchData data) => {
  'fullText': data.fullText,
  'characterRects': [
    for (final rect in data.normalizedCharacterRects)
      [rect.left, rect.top, rect.right, rect.bottom],
  ],
};

ImageSearchData _dataFromJson(Map<String, Object?> json) {
  final rawRects = json['characterRects'] as List<Object?>;
  return ImageSearchData(
    fullText: json['fullText'] as String,
    normalizedCharacterRects: [
      for (final value in rawRects)
        if (value case final List<Object?> rect when rect.length == 4)
          Rect.fromLTRB(
            (rect[0] as num).toDouble(),
            (rect[1] as num).toDouble(),
            (rect[2] as num).toDouble(),
            (rect[3] as num).toDouble(),
          ),
    ],
  );
}

@immutable
class ImageTextSearchResult {
  const ImageTextSearchResult({
    required this.pageId,
    required this.notebookPageNumber,
    required this.imageId,
    required this.snippet,
    required this.matchText,
    required this.highlightRects,
  });

  final String pageId;
  final int notebookPageNumber;
  final String imageId;
  final String snippet;
  final String matchText;
  final List<Rect> highlightRects;
}

@immutable
class ImageTextSearchResponse {
  const ImageTextSearchResponse({
    required this.results,
    required this.imageCount,
    required this.textImageCount,
    required this.unavailableImageCount,
    required this.isTruncated,
  });

  final List<ImageTextSearchResult> results;
  final int imageCount;
  final int textImageCount;
  final int unavailableImageCount;
  final bool isTruncated;
}

class ImageTextSearchService {
  ImageTextSearchService({ImageTextExtractor? extractor, this.maxResults = 250})
    : extractor = extractor ?? MlKitImageTextExtractor();

  final ImageTextExtractor extractor;
  final int maxResults;
  final Map<ImageSourceRef, ImageSearchData?> _cache = {};

  Future<ImageTextSearchResponse> search({
    required List<NotePage> pages,
    required String query,
    PdfSearchProgressCallback? onProgress,
  }) async {
    final sources = <ImageSourceRef>{
      for (final page in pages)
        for (final noteImage in page.images)
          ImageSourceRef(filePath: noteImage.filePath),
    };
    final missing = [
      for (final source in sources)
        if (!_cache.containsKey(source)) source,
    ];
    final cachedCount = sources.length - missing.length;
    onProgress?.call(cachedCount, sources.length);
    if (missing.isNotEmpty) {
      final extracted = await extractor.extract(
        missing,
        onProgress: (completed, _) =>
            onProgress?.call(cachedCount + completed, sources.length),
      );
      for (final source in missing) {
        _cache[source] = extracted[source];
      }
    }

    final normalizedQuery = query.trim().toLowerCase();
    final results = <ImageTextSearchResult>[];
    var imageCount = 0;
    var textImageCount = 0;
    var unavailableImageCount = 0;
    var isTruncated = false;
    searchPages:
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex += 1) {
      final page = pages[pageIndex];
      for (final noteImage in page.images) {
        imageCount += 1;
        final data = _cache[ImageSourceRef(filePath: noteImage.filePath)];
        if (data == null) {
          unavailableImageCount += 1;
          continue;
        }
        if (data.fullText.trim().isNotEmpty) textImageCount += 1;
        if (normalizedQuery.isEmpty) continue;
        final searchable = data.fullText.toLowerCase();
        var start = searchable.indexOf(normalizedQuery);
        while (start >= 0) {
          if (results.length >= maxResults) {
            isTruncated = true;
            break searchPages;
          }
          final end = start + normalizedQuery.length;
          results.add(
            ImageTextSearchResult(
              pageId: page.id,
              notebookPageNumber: pageIndex + 1,
              imageId: noteImage.id,
              snippet: _buildSnippet(data.fullText, start, end),
              matchText: data.fullText.substring(start, end),
              highlightRects: _pageHighlightRects(
                image: noteImage,
                normalizedRects: data.normalizedCharacterRects,
                start: start,
                end: end,
              ),
            ),
          );
          start = searchable.indexOf(normalizedQuery, end);
        }
      }
    }
    return ImageTextSearchResponse(
      results: List.unmodifiable(results),
      imageCount: imageCount,
      textImageCount: textImageCount,
      unavailableImageCount: unavailableImageCount,
      isTruncated: isTruncated,
    );
  }
}

List<Rect> _pageHighlightRects({
  required NoteImage image,
  required List<Rect> normalizedRects,
  required int start,
  required int end,
}) {
  final selected = <Rect>[];
  for (
    var index = start;
    index < end && index < normalizedRects.length;
    index += 1
  ) {
    final rect = normalizedRects[index];
    if (rect.isEmpty) continue;
    selected.add(
      Rect.fromLTWH(
        image.position.dx + rect.left * image.width,
        image.position.dy + rect.top * image.height,
        rect.width * image.width,
        rect.height * image.height,
      ),
    );
  }
  return _mergeAdjacentRects(selected);
}

List<Rect> _mergeAdjacentRects(List<Rect> rects) {
  final merged = <Rect>[];
  for (final rect in rects) {
    if (merged.isNotEmpty) {
      final previous = merged.last;
      final sameLine =
          (previous.center.dy - rect.center.dy).abs() <=
          math.max(previous.height, rect.height) * 0.5;
      if (sameLine && rect.left - previous.right <= math.max(2, rect.width)) {
        merged[merged.length - 1] = previous.expandToInclude(rect);
        continue;
      }
    }
    merged.add(rect);
  }
  return List.unmodifiable(merged);
}

String _buildSnippet(String text, int start, int end) {
  const contextLength = 44;
  final snippetStart = math.max(0, start - contextLength);
  final snippetEnd = math.min(text.length, end + contextLength);
  final normalized = text
      .substring(snippetStart, snippetEnd)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${snippetStart > 0 ? '...' : ''}$normalized'
      '${snippetEnd < text.length ? '...' : ''}';
}
