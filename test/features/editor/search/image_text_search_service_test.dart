import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:inknest_notes/features/editor/search/image_text_search_service.dart';
import 'package:inknest_notes/features/editor/search/pdf_text_search_service.dart';
import 'package:inknest_notes/features/recognition/raster_text_recognizer.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';

void main() {
  test(
    'searches image OCR and maps normalized bounds onto the note page',
    () async {
      const source = ImageSourceRef(filePath: '/tmp/class.png');
      final extractor = _FakeImageTextExtractor({
        source: const ImageSearchData(
          fullText: '课堂笔记',
          normalizedCharacterRects: [
            Rect.fromLTWH(0.1, 0.2, 0.1, 0.2),
            Rect.fromLTWH(0.2, 0.2, 0.1, 0.2),
            Rect.fromLTWH(0.3, 0.2, 0.1, 0.2),
            Rect.fromLTWH(0.4, 0.2, 0.1, 0.2),
          ],
        ),
      });
      final service = ImageTextSearchService(extractor: extractor);
      final page = NotePage(
        id: 'page-1',
        width: 500,
        height: 700,
        images: const [
          NoteImage(
            id: 'image-1',
            position: Offset(100, 200),
            width: 200,
            height: 100,
            assetPath: 'assets/images/class.png',
            resolvedFilePath: '/tmp/class.png',
          ),
        ],
      );

      final first = await service.search(pages: [page], query: '堂笔');
      final second = await service.search(pages: [page], query: '课堂');

      expect(first.results, hasLength(1));
      expect(first.results.single.imageId, 'image-1');
      expect(first.results.single.matchText, '堂笔');
      expect(
        first.results.single.highlightRects.single,
        const Rect.fromLTRB(140, 220, 180, 240),
      );
      expect(first.imageCount, 1);
      expect(first.textImageCount, 1);
      expect(first.unavailableImageCount, 0);
      expect(second.results, hasLength(1));
      expect(extractor.callCount, 1);
    },
  );

  test(
    'reports unreadable inserted images without blocking other content',
    () async {
      const source = ImageSourceRef(filePath: '/tmp/broken.png');
      final service = ImageTextSearchService(
        extractor: _FakeImageTextExtractor({source: null}),
      );
      final response = await service.search(
        pages: [
          NotePage(
            id: 'page-1',
            width: 100,
            height: 100,
            images: const [
              NoteImage(
                id: 'image-1',
                position: Offset.zero,
                width: 50,
                height: 50,
                assetPath: '/tmp/broken.png',
              ),
            ],
          ),
        ],
        query: 'note',
      );

      expect(response.unavailableImageCount, 1);
      expect(response.results, isEmpty);
    },
  );

  test(
    'decodes an image, recognizes it, and reuses the persistent cache',
    () async {
      final root = await Directory.systemTemp.createTemp('inknest-image-ocr-');
      try {
        final imageDirectory = Directory('${root.path}/assets/images')
          ..createSync(recursive: true);
        final file = File('${imageDirectory.path}/note.png');
        final bitmap = image_lib.Image(width: 20, height: 10, numChannels: 4);
        image_lib.fill(bitmap, color: image_lib.ColorRgb8(255, 255, 255));
        file.writeAsBytesSync(image_lib.encodePng(bitmap));
        final source = ImageSourceRef(filePath: file.path);
        final firstRecognizer = _FakeRasterRecognizer();

        final first = await MlKitImageTextExtractor(
          recognizer: firstRecognizer,
          cache: FileImageOcrCache(),
        ).extract([source]);
        final secondRecognizer = _FakeRasterRecognizer();
        final second = await MlKitImageTextExtractor(
          recognizer: secondRecognizer,
          cache: FileImageOcrCache(),
        ).extract([source]);

        expect(first[source]?.fullText, 'Photo note');
        expect(first[source]?.normalizedCharacterRects, hasLength(10));
        expect(firstRecognizer.callCount, 1);
        expect(second[source]?.fullText, 'Photo note');
        expect(secondRecognizer.callCount, 0);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

class _FakeImageTextExtractor implements ImageTextExtractor {
  _FakeImageTextExtractor(this.values);

  final Map<ImageSourceRef, ImageSearchData?> values;
  int callCount = 0;

  @override
  Future<Map<ImageSourceRef, ImageSearchData?>> extract(
    Iterable<ImageSourceRef> images, {
    PdfSearchProgressCallback? onProgress,
  }) async {
    callCount += 1;
    final requested = images.toList(growable: false);
    return {
      for (var index = 0; index < requested.length; index += 1)
        requested[index]: (() {
          onProgress?.call(index + 1, requested.length);
          return values[requested[index]];
        })(),
    };
  }
}

class _FakeRasterRecognizer implements RasterTextRecognizer {
  int callCount = 0;

  @override
  Future<RasterTextRecognitionResult> recognize(
    RasterTextRecognitionRequest request,
  ) async {
    callCount += 1;
    expect(request.width, 20);
    expect(request.height, 10);
    return const RasterTextRecognitionResult(
      text: 'Photo note',
      lines: [
        RasterTextLine(text: 'Photo note', bounds: Rect.fromLTWH(2, 2, 16, 6)),
      ],
      engineIdentifier: MlKitRasterTextRecognizer.engineIdentifier,
    );
  }
}
