import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/theme.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

void main() {
  testWidgets('opens unresolved legacy ink read-only without overwriting it', (
    tester,
  ) async {
    final legacyPage = NotePage(
      id: 'page-1',
      width: 768,
      height: 1024,
      coordinateSpaceVersion: NotePage.legacyCoordinateSpaceVersion,
      strokes: [
        Stroke(
          id: 'legacy-stroke',
          tool: ToolType.pen,
          color: Colors.black,
          width: 4,
          points: [
            StrokePoint(
              offset: const Offset(80, 96),
              pressure: 1,
              time: DateTime.utc(2026, 7, 27),
            ),
          ],
        ),
      ],
    );
    final repository = _LegacyPageRepository(legacyPage);
    final notebook = await repository.createNotebook(title: 'Legacy notes');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildInkNestTheme(),
        home: EditorScreen(notebook: notebook, notebookRepository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('coordinate-space-read-only-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('Legacy page is read-only'), findsOneWidget);

    final canvasRect = tester.getRect(find.byType(DrawingCanvas));
    final visibleRect = canvasRect.intersect(
      Offset.zero &
          Size(
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          ),
    );
    final gesture = await tester.startGesture(
      visibleRect.topLeft + const Offset(72, 72),
      kind: ui.PointerDeviceKind.stylus,
    );
    await gesture.moveBy(const Offset(24, 18));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 240));

    final reloadedPage = await repository.loadPage(notebook, 'page-1');
    expect(
      reloadedPage.coordinateSpaceStatus,
      NotePageCoordinateSpaceStatus.legacy,
    );
    expect(reloadedPage.strokes.map((stroke) => stroke.id), ['legacy-stroke']);

    await tester.tap(find.byKey(const ValueKey('editor-pages-button')));
    await tester.pump(const Duration(milliseconds: 240));
    final rotateAction = find.byKey(const ValueKey('pages-rotate-button'));
    expect(rotateAction, findsOneWidget);
    expect(find.byTooltip('Rotate page unavailable'), findsOneWidget);
    expect(tester.widget<IconButton>(rotateAction).onPressed, isNull);
    expect(repository.normalSaveAttempts, 0);
  });
}

class _LegacyPageRepository extends InMemoryNotebookRepository {
  _LegacyPageRepository(this.legacyPage);

  final NotePage legacyPage;
  int normalSaveAttempts = 0;

  @override
  Future<NotePage> loadPage(Notebook notebook, String pageId) async {
    return pageId == legacyPage.id
        ? legacyPage
        : super.loadPage(notebook, pageId);
  }

  @override
  Future<void> savePage(Notebook notebook, NotePage page) async {
    normalSaveAttempts++;
    throw PageCoordinateSpaceWriteException.forPage(legacyPage);
  }
}
