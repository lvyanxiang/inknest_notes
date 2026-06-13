import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page.dart';
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
    final reloadedPage = await reloadedRepository.loadPage(notebook);

    expect(reloadedNotebooks.single.title, 'Physics');
    expect(reloadedPage.strokes, hasLength(1));
    expect(
      reloadedPage.strokes.single.points.single.offset,
      const Offset(10, 20),
    );
  });
}
