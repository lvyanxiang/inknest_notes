import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:inknest_notes/export/notebook_pdf_exporter.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';

void main() {
  test('exports blank-page notebook with strokes as PDF bytes', () async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Physics');

    await repository.savePage(
      notebook,
      NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
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
}

class _UnexpectedBackgroundRenderer implements PdfPageBackgroundRenderer {
  @override
  Future<RenderedPdfPageBackground?> render(
    PdfBackground background,
    NotePage page,
  ) {
    throw StateError('No PDF background should be rendered in this test.');
  }
}
