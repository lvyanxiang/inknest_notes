import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

void main() {
  group('InMemoryNotebookRepository coordinate-space gate', () {
    test('new and empty legacy pages load as canonical v1', () async {
      final repository = InMemoryNotebookRepository();
      final notebook = await repository.createNotebook(title: 'Safe notes');

      expect(
        (await repository.loadPage(notebook, 'page-1')).coordinateSpaceStatus,
        NotePageCoordinateSpaceStatus.canonical,
      );

      await repository.savePage(
        notebook,
        const NotePage(
          id: 'page-2',
          width: 768,
          height: 1024,
          coordinateSpaceVersion: NotePage.legacyCoordinateSpaceVersion,
        ),
      );

      final upgradedPage = await repository.loadPage(notebook, 'page-2');
      expect(
        upgradedPage.coordinateSpaceVersion,
        NotePage.canonicalCoordinateSpaceVersion,
      );
    });

    test('blocks non-empty legacy and unsupported normal saves', () async {
      final repository = InMemoryNotebookRepository();
      final notebook = await repository.createNotebook(title: 'Protected');

      await expectLater(
        repository.savePage(
          notebook,
          NotePage(
            id: 'legacy-page',
            width: 768,
            height: 1024,
            coordinateSpaceVersion: NotePage.legacyCoordinateSpaceVersion,
            strokes: [_stroke()],
          ),
        ),
        throwsA(
          isA<PageCoordinateSpaceWriteException>()
              .having(
                (error) => error.reason,
                'reason',
                PageCoordinateSpaceWriteBlockReason.unresolvedLegacyContent,
              )
              .having((error) => error.pageId, 'pageId', 'legacy-page'),
        ),
      );

      await expectLater(
        repository.savePage(
          notebook,
          const NotePage(
            id: 'future-page',
            width: 768,
            height: 1024,
            coordinateSpaceVersion: 2,
          ),
        ),
        throwsA(
          isA<PageCoordinateSpaceWriteException>().having(
            (error) => error.reason,
            'reason',
            PageCoordinateSpaceWriteBlockReason.unsupportedVersion,
          ),
        ),
      );
    });
  });

  group('FileNotebookRepository coordinate-space gate', () {
    late Directory tempDirectory;
    late FileNotebookRepository repository;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'inknest-coordinate-space-test-',
      );
      repository = FileNotebookRepository(rootDirectory: tempDirectory);
    });

    tearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('persists the lossless upgrade of an empty legacy page', () async {
      final notebook = await repository.createNotebook(title: 'Empty legacy');
      final pageFile = _pageFile(tempDirectory, notebook.id, 'page-1');
      final legacyJson = const NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
      ).toJson()..remove('coordinateSpaceVersion');
      await pageFile.writeAsString(jsonEncode(legacyJson), flush: true);

      final page = await repository.loadPage(notebook, 'page-1');
      final persistedJson =
          jsonDecode(await pageFile.readAsString()) as Map<String, Object?>;

      expect(
        page.coordinateSpaceVersion,
        NotePage.canonicalCoordinateSpaceVersion,
      );
      expect(
        persistedJson['coordinateSpaceVersion'],
        NotePage.canonicalCoordinateSpaceVersion,
      );
    });

    test('does not overwrite a non-empty legacy page', () async {
      final notebook = await repository.createNotebook(title: 'Legacy ink');
      final pageFile = _pageFile(tempDirectory, notebook.id, 'page-1');
      final legacyJson = NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        strokes: [_stroke()],
      ).toJson()..remove('coordinateSpaceVersion');
      final originalJson = jsonEncode(legacyJson);
      await pageFile.writeAsString(originalJson, flush: true);

      final page = await repository.loadPage(notebook, 'page-1');
      expect(page.coordinateSpaceStatus, NotePageCoordinateSpaceStatus.legacy);
      expect(page.isCoordinateSpaceWriteProtected, isTrue);

      await expectLater(
        repository.savePage(
          notebook,
          const NotePage(id: 'page-1', width: 768, height: 1024),
        ),
        throwsA(
          isA<PageCoordinateSpaceWriteException>()
              .having(
                (error) => error.reason,
                'reason',
                PageCoordinateSpaceWriteBlockReason.unresolvedLegacyContent,
              )
              .having(
                (error) => error.coordinateSpaceVersion,
                'coordinateSpaceVersion',
                NotePage.legacyCoordinateSpaceVersion,
              ),
        ),
      );

      expect(await pageFile.readAsString(), originalJson);
    });

    test('preserves and blocks a future coordinate version', () async {
      final notebook = await repository.createNotebook(title: 'Future page');
      final pageFile = _pageFile(tempDirectory, notebook.id, 'page-1');
      final futureJson = const NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        coordinateSpaceVersion: 2,
      ).toJson();
      final originalJson = jsonEncode(futureJson);
      await pageFile.writeAsString(originalJson, flush: true);

      final page = await repository.loadPage(notebook, 'page-1');
      expect(
        page.coordinateSpaceStatus,
        NotePageCoordinateSpaceStatus.unsupported,
      );
      expect(page.persistedCoordinateSpaceVersion, 2);

      await expectLater(
        repository.savePage(
          notebook,
          const NotePage(id: 'page-1', width: 768, height: 1024),
        ),
        throwsA(
          isA<PageCoordinateSpaceWriteException>()
              .having(
                (error) => error.reason,
                'reason',
                PageCoordinateSpaceWriteBlockReason.unsupportedVersion,
              )
              .having(
                (error) => error.coordinateSpaceVersion,
                'coordinateSpaceVersion',
                2,
              ),
        ),
      );

      expect(await pageFile.readAsString(), originalJson);
    });
  });
}

File _pageFile(Directory rootDirectory, String notebookId, String pageId) {
  return File('${rootDirectory.path}/notebooks/$notebookId/pages/$pageId.json');
}

Stroke _stroke() {
  return Stroke(
    id: 'stroke-1',
    tool: ToolType.pen,
    color: const Color(0xFF1E2526),
    width: 4,
    points: [
      StrokePoint(
        offset: const Offset(10, 20),
        pressure: 1,
        time: DateTime.utc(2026, 7, 27),
      ),
    ],
  );
}
