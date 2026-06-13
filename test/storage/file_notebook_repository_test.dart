import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';

void main() {
  late Directory tempDirectory;
  late FileNotebookRepository repository;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('inknest-notes-test-');
    repository = FileNotebookRepository(rootDirectory: tempDirectory);
  });

  tearDown(() {
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('persists notebooks and page strokes as JSON', () async {
    final notebook = await repository.createNotebook(title: 'Physics');
    final notebooks = await repository.listNotebooks();

    expect(notebooks, hasLength(1));
    expect(notebooks.single.title, 'Physics');

    final page = NotePage(
      id: 'page-1',
      width: 768,
      height: 1024,
      strokes: [
        Stroke(
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
          ],
        ),
      ],
    );

    await repository.savePage(notebook, page);

    final reloadedRepository = FileNotebookRepository(
      rootDirectory: tempDirectory,
    );
    final reloadedNotebooks = await reloadedRepository.listNotebooks();
    final reloadedPage = await reloadedRepository.loadPage(notebook, 'page-1');

    expect(reloadedNotebooks.single.title, 'Physics');
    expect(reloadedPage.strokes, hasLength(1));
    expect(
      reloadedPage.strokes.single.points.single.offset,
      const Offset(10, 20),
    );
  });

  test('persists page order and separate page content', () async {
    final notebook = await repository.createNotebook(title: 'Sketches');
    final updatedNotebook = await repository.addPage(notebook);

    expect(updatedNotebook.pageIds, ['page-1', 'page-2']);

    await repository.savePage(
      updatedNotebook,
      NotePage(
        id: 'page-2',
        width: 768,
        height: 1024,
        strokes: [
          Stroke(
            id: 'stroke-2',
            tool: ToolType.highlighter,
            color: const Color(0xFFB98A16),
            width: 12,
            points: [
              StrokePoint(
                offset: const Offset(30, 40),
                pressure: 1,
                time: DateTime.utc(2026, 6, 13),
              ),
            ],
          ),
        ],
      ),
    );

    final reloadedRepository = FileNotebookRepository(
      rootDirectory: tempDirectory,
    );
    final reloadedNotebook = (await reloadedRepository.listNotebooks()).single;
    final firstPage = await reloadedRepository.loadPage(
      reloadedNotebook,
      'page-1',
    );
    final secondPage = await reloadedRepository.loadPage(
      reloadedNotebook,
      'page-2',
    );

    expect(reloadedNotebook.pageIds, ['page-1', 'page-2']);
    expect(firstPage.strokes, isEmpty);
    expect(secondPage.strokes, hasLength(1));
  });

  test('persists pdf page background as a relative asset path', () async {
    final notebook = await repository.createNotebook(title: 'PDF Notes');

    await repository.savePage(
      notebook,
      const NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        pdfBackground: PdfBackground(
          assetPath: 'assets/imported.pdf',
          pageNumber: 1,
        ),
      ),
    );

    final reloadedRepository = FileNotebookRepository(
      rootDirectory: tempDirectory,
    );
    final reloadedPage = await reloadedRepository.loadPage(notebook, 'page-1');

    expect(reloadedPage.pdfBackground?.assetPath, 'assets/imported.pdf');
    expect(
      reloadedPage.pdfBackground?.filePath,
      '${tempDirectory.path}/notebooks/${notebook.id}/assets/imported.pdf',
    );
    expect(reloadedPage.pdfBackground?.pageNumber, 1);
  });

  test(
    'resolves old absolute pdf asset paths into the current notebook assets',
    () async {
      final notebook = await repository.createNotebook(title: 'PDF Notes');

      await repository.savePage(
        notebook,
        const NotePage(
          id: 'page-1',
          width: 768,
          height: 1024,
          pdfBackground: PdfBackground(
            assetPath:
                '/old/container/notebooks/notebook-1/assets/imported.pdf',
            pageNumber: 1,
          ),
        ),
      );

      final reloadedPage = await repository.loadPage(notebook, 'page-1');

      expect(reloadedPage.pdfBackground?.assetPath, 'assets/imported.pdf');
      expect(
        reloadedPage.pdfBackground?.filePath,
        '${tempDirectory.path}/notebooks/${notebook.id}/assets/imported.pdf',
      );
    },
  );
}
