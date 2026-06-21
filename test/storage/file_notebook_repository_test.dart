import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
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
      images: const [
        NoteImage(
          id: 'image-1',
          position: Offset(240, 320),
          width: 160,
          height: 90,
          assetPath: 'assets/images/photo.png',
        ),
      ],
      shapes: const [
        NoteShape(
          id: 'shape-1',
          type: NoteShapeType.rectangle,
          start: Offset(120, 160),
          end: Offset(280, 240),
          width: 5,
        ),
      ],
      textBoxes: const [
        NoteTextBox(
          id: 'text-1',
          position: Offset(80, 96),
          text: 'Momentum',
          width: 220,
          fontSize: 20,
          style: NoteTextBoxStyle.handwriting,
        ),
      ],
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
    expect(reloadedPage.textBoxes.single.text, 'Momentum');
    expect(reloadedPage.textBoxes.single.position, const Offset(80, 96));
    expect(reloadedPage.textBoxes.single.style, NoteTextBoxStyle.handwriting);
    expect(reloadedPage.images.single.position, const Offset(240, 320));
    expect(reloadedPage.images.single.assetPath, 'assets/images/photo.png');
    expect(reloadedPage.shapes.single.type, NoteShapeType.rectangle);
    expect(reloadedPage.shapes.single.start, const Offset(120, 160));
    expect(reloadedPage.shapes.single.end, const Offset(280, 240));
  });

  test('imports page images as notebook-relative assets', () async {
    final notebook = await repository.createNotebook(title: 'Moodboard');
    final sourceFile = File('${tempDirectory.path}/source-image.png')
      ..writeAsBytesSync(_tinyPngBytes());

    final importedImage = await repository.importImage(
      notebook,
      sourceFile,
      position: const Offset(40, 56),
      width: 180,
      height: 120,
    );

    expect(importedImage.assetPath, startsWith('assets/images/'));
    expect(File(importedImage.filePath).existsSync(), isTrue);

    await repository.savePage(
      notebook,
      NotePage(id: 'page-1', width: 768, height: 1024, images: [importedImage]),
    );

    final reloadedRepository = FileNotebookRepository(
      rootDirectory: tempDirectory,
    );
    final reloadedPage = await reloadedRepository.loadPage(notebook, 'page-1');
    final reloadedImage = reloadedPage.images.single;

    expect(reloadedImage.assetPath, importedImage.assetPath);
    expect(reloadedImage.filePath, isNot(importedImage.assetPath));
    expect(File(reloadedImage.filePath).existsSync(), isTrue);
    expect(reloadedImage.position, const Offset(40, 56));
    expect(reloadedImage.width, 180);
    expect(reloadedImage.height, 120);
  });

  test('serializes concurrent page saves without corrupting index', () async {
    final notebook = await repository.createNotebook(title: 'Fast Edits');

    await Future.wait([
      for (var index = 0; index < 24; index++)
        repository.savePage(
          notebook,
          NotePage(
            id: 'page-1',
            width: 768,
            height: 1024,
            textBoxes: [
              NoteTextBox(
                id: 'text-$index',
                position: Offset(index.toDouble(), index.toDouble()),
                text: 'Edit $index',
              ),
            ],
          ),
        ),
    ]);

    final indexFile = File('${tempDirectory.path}/notebooks/index.json');
    final indexJson = jsonDecode(await indexFile.readAsString());
    final notebooks = await repository.listNotebooks();
    final page = await repository.loadPage(notebook, 'page-1');

    expect(indexJson, isA<List<Object?>>());
    expect(notebooks.single.title, 'Fast Edits');
    expect(page.textBoxes.single.text, 'Edit 23');
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

  test('duplicates, deletes, and reorders pages persistently', () async {
    var notebook = await repository.createNotebook(title: 'Page Operations');

    await repository.savePage(
      notebook,
      NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        textBoxes: const [
          NoteTextBox(
            id: 'text-1',
            position: Offset(120, 160),
            text: 'Copied text',
          ),
        ],
        images: const [
          NoteImage(
            id: 'image-1',
            position: Offset(220, 280),
            width: 144,
            height: 96,
            assetPath: 'assets/images/photo.png',
          ),
        ],
        shapes: const [
          NoteShape(
            id: 'shape-1',
            type: NoteShapeType.arrow,
            start: Offset(220, 280),
            end: Offset(360, 320),
          ),
        ],
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
                time: DateTime.utc(2026, 6, 14),
              ),
            ],
          ),
        ],
      ),
    );

    notebook = await repository.addPage(notebook);
    notebook = await repository.duplicatePage(notebook, 'page-1');

    expect(notebook.pageIds, ['page-1', 'page-3', 'page-2']);

    final duplicatedPage = await repository.loadPage(notebook, 'page-3');
    expect(duplicatedPage.strokes, hasLength(1));
    expect(duplicatedPage.strokes.single.id, 'stroke-1');
    expect(duplicatedPage.textBoxes.single.text, 'Copied text');
    expect(duplicatedPage.images.single.id, 'image-1');
    expect(duplicatedPage.shapes.single.id, 'shape-1');

    notebook = await repository.movePage(notebook, 'page-2', 0);

    expect(notebook.pageIds, ['page-2', 'page-1', 'page-3']);

    notebook = await repository.deletePage(notebook, 'page-1');

    expect(notebook.pageIds, ['page-2', 'page-3']);
    expect(
      File(
        '${tempDirectory.path}/notebooks/${notebook.id}/pages/page-1.json',
      ).existsSync(),
      isFalse,
    );

    final reloadedNotebook = (await repository.listNotebooks()).single;
    expect(reloadedNotebook.pageIds, ['page-2', 'page-3']);
  });

  test('inserts blank pages around PDF pages persistently', () async {
    var notebook = await repository.createNotebook(title: 'PDF Study');
    await repository.savePage(
      notebook,
      const NotePage(
        id: 'page-1',
        width: 612,
        height: 792,
        pdfBackground: PdfBackground(
          assetPath: 'assets/imported.pdf',
          pageNumber: 1,
        ),
        strokes: [],
      ),
    );

    notebook = await repository.insertPage(notebook, 1);

    expect(notebook.pageIds, ['page-1', 'page-2']);

    final pageAfterPdf = await repository.loadPage(notebook, 'page-2');
    expect(pageAfterPdf.width, 612);
    expect(pageAfterPdf.height, 792);
    expect(pageAfterPdf.pdfBackground, isNull);
    expect(pageAfterPdf.strokes, isEmpty);

    notebook = await repository.insertPage(notebook, 0);

    expect(notebook.pageIds, ['page-3', 'page-1', 'page-2']);

    final pageBeforePdf = await repository.loadPage(notebook, 'page-3');
    expect(pageBeforePdf.width, 612);
    expect(pageBeforePdf.height, 792);
    expect(pageBeforePdf.pdfBackground, isNull);

    final reloadedNotebook = (await repository.listNotebooks()).single;
    expect(reloadedNotebook.pageIds, ['page-3', 'page-1', 'page-2']);
  });

  test('persists page bookmarks', () async {
    var notebook = await repository.createNotebook(title: 'Study Notes');
    notebook = await repository.addPage(notebook);

    notebook = await repository.setPageBookmarked(notebook, 'page-2', true);

    var reloadedNotebook = (await repository.listNotebooks()).single;
    expect(reloadedNotebook.bookmarkedPageIds, ['page-2']);

    reloadedNotebook = await repository.setPageBookmarked(
      reloadedNotebook,
      'page-2',
      false,
    );

    expect(reloadedNotebook.bookmarkedPageIds, isEmpty);
    expect(
      (await repository.listNotebooks()).single.bookmarkedPageIds,
      isEmpty,
    );
  });

  test(
    'renames, duplicates, archives, restores, and deletes notebooks',
    () async {
      var notebook = await repository.createNotebook(title: 'Meeting Notes');
      notebook = await repository.addPage(notebook);

      await repository.savePage(
        notebook,
        NotePage(
          id: 'page-2',
          width: 768,
          height: 1024,
          strokes: [
            Stroke(
              id: 'stroke-2',
              tool: ToolType.pen,
              color: const Color(0xFF1E2526),
              width: 5,
              points: [
                StrokePoint(
                  offset: const Offset(12, 24),
                  pressure: 1,
                  time: DateTime.utc(2026, 6, 14),
                ),
              ],
            ),
          ],
        ),
      );

      notebook = await repository.renameNotebook(notebook, 'Project Notes');

      expect((await repository.listNotebooks()).single.title, 'Project Notes');

      final duplicatedNotebook = await repository.duplicateNotebook(notebook);
      final duplicatedPage = await repository.loadPage(
        duplicatedNotebook,
        'page-2',
      );

      expect(duplicatedNotebook.title, 'Project Notes Copy');
      expect(duplicatedNotebook.pageIds, ['page-1', 'page-2']);
      expect(duplicatedPage.strokes, hasLength(1));

      notebook = await repository.setNotebookArchived(notebook, true);

      expect(
        (await repository.listNotebooks()).map((notebook) => notebook.title),
        ['Project Notes Copy'],
      );
      expect(
        (await repository.listNotebooks(
          archived: true,
        )).map((notebook) => notebook.title),
        ['Project Notes'],
      );

      notebook = await repository.setNotebookArchived(notebook, false);

      expect(await repository.listNotebooks(archived: true), isEmpty);
      expect((await repository.listNotebooks()), hasLength(2));

      await repository.deleteNotebook(duplicatedNotebook);

      expect(
        (await repository.listNotebooks()).map((notebook) => notebook.title),
        ['Project Notes'],
      );
      expect(
        Directory(
          '${tempDirectory.path}/notebooks/${duplicatedNotebook.id}',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('creates folders and moves notebooks in and out of folders', () async {
    final folder = await repository.createFolder('Class Notes');
    var notebook = await repository.createNotebook(title: 'Math');

    expect((await repository.listFolders()).single.name, 'Class Notes');
    expect((await repository.listNotebooks()).single.title, 'Math');

    notebook = await repository.moveNotebookToFolder(notebook, folder.id);

    expect(await repository.listNotebooks(), isEmpty);
    expect(
      (await repository.listNotebooks(
        folderId: folder.id,
      )).map((notebook) => notebook.title),
      ['Math'],
    );

    final renamedFolder = await repository.renameFolder(folder, 'School');

    expect((await repository.listFolders()).single.name, 'School');

    notebook = await repository.moveNotebookToFolder(notebook, null);

    expect(notebook.folderId, isNull);
    expect((await repository.listNotebooks()).single.title, 'Math');

    notebook = await repository.moveNotebookToFolder(
      notebook,
      renamedFolder.id,
    );
    await repository.deleteFolder(renamedFolder);

    expect(await repository.listFolders(), isEmpty);
    expect((await repository.listNotebooks()).single.folderId, isNull);
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

List<int> _tinyPngBytes() {
  final png = image.Image(width: 1, height: 1);
  png.setPixelRgb(0, 0, 255, 255, 255);
  return image.encodePng(png);
}
