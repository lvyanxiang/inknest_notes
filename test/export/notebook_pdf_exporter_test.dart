import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:inknest_notes/export/notebook_pdf_exporter.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_page_template.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';

void main() {
  test('defines increasing flattened-background quality presets', () {
    final compact = PdfExportQuality.compact.rasterSettings;
    final balanced = PdfExportQuality.balanced.rasterSettings;
    final best = PdfExportQuality.best.rasterSettings;

    expect(
      compact.maximumPixelDimension,
      lessThan(balanced.maximumPixelDimension),
    );
    expect(
      balanced.maximumPixelDimension,
      lessThan(best.maximumPixelDimension),
    );
    expect(compact.targetPixelRatio, lessThan(balanced.targetPixelRatio));
    expect(balanced.targetPixelRatio, lessThan(best.targetPixelRatio));
    expect(compact.backgroundEncoding, PdfExportBackgroundEncoding.jpeg);
    expect(balanced.backgroundEncoding, PdfExportBackgroundEncoding.jpeg);
    expect(best.backgroundEncoding, PdfExportBackgroundEncoding.png);
  });

  test('encodes compact backgrounds smaller than lossless backgrounds', () {
    const width = 64;
    const height = 64;
    final pixels = _noisyBgraPixels(width, height).buffer;
    final compact = PdfExportQuality.compact.rasterSettings;
    final best = PdfExportQuality.best.rasterSettings;

    final jpegBytes = encodePdfExportBackgroundImage(
      width: width,
      height: height,
      bgraPixels: pixels,
      encoding: compact.backgroundEncoding,
      jpegQuality: compact.jpegQuality,
    );
    final pngBytes = encodePdfExportBackgroundImage(
      width: width,
      height: height,
      bgraPixels: pixels,
      encoding: best.backgroundEncoding,
      jpegQuality: best.jpegQuality,
    );

    expect(jpegBytes.take(2), [0xff, 0xd8]);
    expect(pngBytes.take(8), [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
    expect(jpegBytes.length, lessThan(pngBytes.length));
  });

  test('exports blank-page notebook with strokes as PDF bytes', () async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Physics');
    final tempDirectory = Directory.systemTemp.createTempSync(
      'inknest-export-image-',
    );
    addTearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/photo.png')
      ..writeAsBytesSync(_tinyPngBytes());

    await repository.savePage(
      notebook,
      NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        template: NotePageTemplate.grid,
        images: [
          NoteImage(
            id: 'image-1',
            position: const Offset(220, 260),
            width: 180,
            height: 120,
            assetPath: imageFile.path,
            resolvedFilePath: imageFile.path,
          ),
        ],
        shapes: const [
          NoteShape(
            id: 'shape-1',
            type: NoteShapeType.arrow,
            start: Offset(96, 240),
            end: Offset(360, 280),
            width: 5,
          ),
        ],
        textBoxes: const [
          NoteTextBox(
            id: 'text-1',
            position: Offset(120, 160),
            text: 'Typed note 中文',
            style: NoteTextBoxStyle.handwriting,
          ),
        ],
        strokes: [_sampleStroke()],
      ),
    );

    final bytes = await NotebookPdfExporter(
      notebookRepository: repository,
      backgroundRenderer: _UnexpectedBackgroundRenderer(),
    ).exportNotebook(notebook);

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  test('renders PDF page backgrounds before exporting annotations', () async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Annotated PDF');
    final backgroundRenderer = _FakeBackgroundRenderer();

    await repository.savePage(
      notebook,
      NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        pdfBackground: const PdfBackground(
          assetPath: 'assets/imported.pdf',
          pageNumber: 2,
          resolvedFilePath: '/tmp/imported.pdf',
        ),
        strokes: [_sampleStroke()],
      ),
    );

    final bytes = await NotebookPdfExporter(
      notebookRepository: repository,
      backgroundRenderer: backgroundRenderer,
    ).exportNotebook(notebook);

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(backgroundRenderer.renderedBackgrounds.single.pageNumber, 2);
    expect(backgroundRenderer.renderedPages.single.id, 'page-1');
  });

  test('exports rotated pages with swapped PDF dimensions', () async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Landscape Notes');
    await repository.savePage(
      notebook,
      NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        rotationQuarterTurns: 1,
        template: NotePageTemplate.ruled,
        strokes: [_sampleStroke()],
      ),
    );

    final bytes = await NotebookPdfExporter(
      notebookRepository: repository,
      backgroundRenderer: _UnexpectedBackgroundRenderer(),
    ).exportNotebook(notebook);
    final pdfSource = String.fromCharCodes(bytes);

    expect(
      RegExp(r'/MediaBox\s*\[\s*0\s+0\s+1024\s+768\s*\]').hasMatch(pdfSource),
      isTrue,
    );
  });

  test('reuses rendered PDF backgrounds during a single export', () async {
    final repository = InMemoryNotebookRepository();
    var notebook = await repository.createNotebook(title: 'Duplicated PDF');
    notebook = await repository.addPage(notebook);
    final backgroundRenderer = _FakeBackgroundRenderer();
    const background = PdfBackground(
      assetPath: 'assets/imported.pdf',
      pageNumber: 1,
      resolvedFilePath: '/tmp/imported.pdf',
    );

    for (final pageId in notebook.pageIds) {
      await repository.savePage(
        notebook,
        NotePage(
          id: pageId,
          width: 768,
          height: 1024,
          pdfBackground: background,
          strokes: [_sampleStroke()],
        ),
      );
    }

    final bytes = await NotebookPdfExporter(
      notebookRepository: repository,
      backgroundRenderer: backgroundRenderer,
    ).exportNotebook(notebook);

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(backgroundRenderer.renderedBackgrounds, hasLength(1));
    expect(backgroundRenderer.renderedPages.single.id, 'page-1');
  });

  test('exports non-contiguous page ids in the selected order', () async {
    final repository = _TrackingNotebookRepository();
    var notebook = await repository.createNotebook(title: 'Selected Pages');
    notebook = await repository.addPage(notebook);
    notebook = await repository.addPage(notebook);
    repository.loadedPageIds.clear();

    final bytes = await NotebookPdfExporter(
      notebookRepository: repository,
      backgroundRenderer: _UnexpectedBackgroundRenderer(),
    ).exportNotebook(notebook, pageIds: const ['page-3', 'page-1']);

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(repository.loadedPageIds, ['page-3', 'page-1']);
  });
}

Stroke _sampleStroke() {
  return Stroke(
    id: 'stroke-1',
    tool: ToolType.pen,
    color: const Color(0xFF1E2526),
    width: 5,
    points: [
      StrokePoint(
        offset: const Offset(10, 20),
        pressure: 1,
        time: DateTime.utc(2026, 6, 13),
      ),
      StrokePoint(
        offset: const Offset(80, 120),
        pressure: 1,
        time: DateTime.utc(2026, 6, 13, 0, 0, 1),
      ),
    ],
  );
}

Uint8List _tinyPngBytes() {
  final png = image.Image(width: 1, height: 1);
  png.setPixelRgb(0, 0, 255, 255, 255);
  return image.encodePng(png);
}

Uint8List _noisyBgraPixels(int width, int height) {
  var seed = 0x12345678;
  final pixels = Uint8List(width * height * 4);
  for (var offset = 0; offset < pixels.length; offset += 4) {
    seed = (seed * 1664525 + 1013904223) & 0xffffffff;
    pixels[offset] = seed & 0xff;
    pixels[offset + 1] = (seed >> 8) & 0xff;
    pixels[offset + 2] = (seed >> 16) & 0xff;
    pixels[offset + 3] = 0xff;
  }
  return pixels;
}

class _FakeBackgroundRenderer implements PdfPageBackgroundRenderer {
  final List<PdfBackground> renderedBackgrounds = [];
  final List<NotePage> renderedPages = [];

  @override
  Future<RenderedPdfPageBackground?> render(
    PdfBackground background,
    NotePage page,
  ) async {
    renderedBackgrounds.add(background);
    renderedPages.add(page);

    return RenderedPdfPageBackground(pngBytes: _tinyPngBytes());
  }

  @override
  Future<void> dispose() async {}
}

class _UnexpectedBackgroundRenderer implements PdfPageBackgroundRenderer {
  @override
  Future<RenderedPdfPageBackground?> render(
    PdfBackground background,
    NotePage page,
  ) {
    throw StateError('No PDF background should be rendered in this test.');
  }

  @override
  Future<void> dispose() async {}
}

class _TrackingNotebookRepository extends InMemoryNotebookRepository {
  final List<String> loadedPageIds = [];

  @override
  Future<NotePage> loadPage(Notebook notebook, String pageId) async {
    loadedPageIds.add(pageId);
    return super.loadPage(notebook, pageId);
  }
}
