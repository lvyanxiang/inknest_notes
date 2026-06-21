import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:inknest_notes/export/notebook_pdf_exporter.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';

void main() {
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

  test(
    'exports only selected page ids when a page range is provided',
    () async {
      final repository = _TrackingNotebookRepository();
      var notebook = await repository.createNotebook(title: 'Selected Pages');
      notebook = await repository.addPage(notebook);

      final bytes = await NotebookPdfExporter(
        notebookRepository: repository,
        backgroundRenderer: _UnexpectedBackgroundRenderer(),
      ).exportNotebook(notebook, pageIds: const ['page-2']);

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(repository.loadedPageIds, ['page-2']);
    },
  );
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
