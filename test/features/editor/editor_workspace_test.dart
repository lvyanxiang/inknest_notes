import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/theme.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page_size.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';

void main() {
  group('editor workspace', () {
    testWidgets(
      'keeps the document surface at canonical size across viewport rotation',
      (tester) async {
        final fixture = await _createFixture(tester, const Size(834, 1194));

        final surface = find.byKey(
          const ValueKey('rotated-page-surface-page-1-0'),
        );
        final viewport = find.byKey(
          const ValueKey('continuous-paged-viewport'),
        );

        expect(tester.getSize(surface), defaultNotePageSize);
        expect(tester.getSize(find.byType(DrawingCanvas)), defaultNotePageSize);
        final portraitViewportSize = tester.getSize(viewport);

        tester.view.physicalSize = const Size(1194, 834);
        await tester.pumpAndSettle();

        expect(tester.getSize(viewport), isNot(portraitViewportSize));
        expect(tester.getSize(surface), defaultNotePageSize);
        expect(tester.getSize(find.byType(DrawingCanvas)), defaultNotePageSize);

        final persistedPage = await fixture.repository.loadPage(
          fixture.notebook,
          'page-1',
        );
        expect(
          Size(persistedPage.width, persistedPage.height),
          defaultNotePageSize,
        );
      },
    );

    testWidgets('opens Pages Outline and Bookmarks as focused compact panels', (
      tester,
    ) async {
      await _createFixture(tester, const Size(600, 800));

      expect(find.byKey(const ValueKey('editor-pages-button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-outline-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-bookmarks-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('editor-pages-button')),
          matching: find.byIcon(Icons.layers_outlined),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('editor-pages-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('editor-pages-panel')), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(
        find.byKey(const ValueKey('page-thumbnail-page-1')),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-outline-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-outline-panel')),
        findsOneWidget,
      );
      expect(find.text('No PDF outline'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);

      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-bookmarks-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-bookmarks-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('bookmarks-toggle-current-page')),
        findsOneWidget,
      );
      expect(find.text('No bookmarks'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets(
      'opens Pages from the header icon without a floating page chip',
      (tester) async {
        await _createFixture(tester, const Size(834, 1194));

        expect(
          find.byKey(const ValueKey('editor-document-context')),
          findsNothing,
        );
        expect(find.byTooltip('Open Pages, page 1 of 1'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-page-position-button')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('editor-pages-button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('editor-pages-panel')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('editor-zoom-chip')), findsNothing);
      },
    );

    testWidgets('keeps a two-row editor chrome without overflow on phones', (
      tester,
    ) async {
      await _createFixture(tester, const Size(390, 844));

      final compactNavigation = find.byKey(
        const ValueKey('editor-compact-navigation-row'),
      );
      final appBar = tester.widget<AppBar>(find.byType(AppBar));

      expect(
        find.byKey(const ValueKey('editor-document-context')),
        findsNothing,
      );
      expect(appBar.preferredSize.height, 104);
      expect(compactNavigation, findsNothing);
      final pagesButton = find.byKey(const ValueKey('editor-pages-button'));
      expect(pagesButton, findsOneWidget);
      expect(tester.getSize(pagesButton), const Size.square(44));
      final addPageButton = find.byKey(
        const ValueKey('editor-add-page-button'),
      );
      expect(addPageButton, findsOneWidget);
      final addPageSize = tester.getSize(addPageButton);
      expect(addPageSize.width, greaterThanOrEqualTo(44));
      expect(addPageSize.height, greaterThanOrEqualTo(44));
      expect(
        tester.getRect(pagesButton).right,
        closeTo(tester.getRect(addPageButton).left, 0.01),
      );
      expect(
        find.byKey(const ValueKey('editor-previous-page-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('editor-next-page-button')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor-outline-button')), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-bookmarks-button')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('editor-undo-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-redo-button')), findsOneWidget);
      final undoButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('editor-undo-button')),
      );
      expect(undoButton.iconSize, 20);
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-undo-button'))),
        const Size.square(44),
      );
      final fitWidth = find.byKey(const ValueKey('editor-fit-width-button'));
      expect(fitWidth, findsOneWidget);
      expect(tester.getSize(fitWidth), const Size.square(44));
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-more-actions'))),
        const Size.square(44),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('editor-more-actions'))).right,
        greaterThan(380),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('editor-more-actions')));
      await tester.pumpAndSettle();
      expect(find.text('Outline'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-outline-panel')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps only Add page as the direct pagination action', (
      tester,
    ) async {
      await _createFixture(tester, const Size(600, 800));

      final previous = find.byKey(
        const ValueKey('editor-previous-page-button'),
      );
      final next = find.byKey(const ValueKey('editor-next-page-button'));
      final add = find.byKey(const ValueKey('editor-add-page-button'));

      expect(previous, findsNothing);
      expect(next, findsNothing);
      expect(find.byTooltip('Open Pages, page 1 of 1'), findsOneWidget);
      expect(tester.getSize(add).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(add).height, greaterThanOrEqualTo(44));

      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(find.text('Add page'), findsOneWidget);
      await tester.tap(find.byTooltip('Close paper styles'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open Pages, page 1 of 1'), findsOneWidget);

      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-template-blank')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open Pages, page 2 of 2'), findsOneWidget);
      expect(previous, findsNothing);
      expect(next, findsNothing);

      await tester.tap(find.byKey(const ValueKey('editor-pages-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('editor-pages-panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selects and remembers paper setup on compact phones', (
      tester,
    ) async {
      final fixture = await _createFixture(tester, const Size(320, 568));

      await tester.tap(find.byKey(const ValueKey('editor-add-page-button')));
      await tester.pumpAndSettle();
      expect(find.text('Paper size'), findsOneWidget);
      expect(find.byKey(const ValueKey('page-size-a4')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('page-size-digital')));
      await tester.pump();
      await tester.tap(find.byTooltip('Landscape paper'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-template-blank')));
      await tester.pumpAndSettle();

      final addedPage = await fixture.repository.loadPage(
        fixture.notebook,
        'page-2',
      );
      expect(
        Size(addedPage.width, addedPage.height),
        NotePageSizePreset.digital.sizeFor(NotePageOrientation.landscape),
      );

      await tester.tap(find.byKey(const ValueKey('editor-add-page-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('page-size-digital')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<SegmentedButton<NotePageOrientation>>(
              find.byType(SegmentedButton<NotePageOrientation>),
            )
            .selected,
        {NotePageOrientation.landscape},
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolls continuously between pages on phone and tablet', (
      tester,
    ) async {
      final fixture = await _createFixture(tester, const Size(390, 844));

      await tester.tap(find.byKey(const ValueKey('editor-add-page-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-template-blank')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('continuous-page-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('continuous-page-item-page-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('continuous-page-item-page-2')),
        findsOneWidget,
      );

      await tester.drag(
        find.byKey(const ValueKey('continuous-page-list')),
        const Offset(0, 520),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open Pages, page 1 of 2'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('continuous-page-list')),
        const Offset(0, -520),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open Pages, page 2 of 2'), findsOneWidget);

      final pageTwoCanvas = find.descendant(
        of: find.byKey(const ValueKey('continuous-page-item-page-2')),
        matching: find.byType(DrawingCanvas),
      );
      final canvasRect = tester.getRect(pageTwoCanvas);
      final visibleRect = canvasRect.intersect(
        Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio),
      );
      final drawStart = visibleRect.center;
      final stylus = await tester.startGesture(
        drawStart,
        kind: ui.PointerDeviceKind.stylus,
      );
      await stylus.moveBy(const Offset(32, 12));
      await stylus.up();
      await tester.pumpAndSettle();
      expect(
        (await fixture.repository.loadPage(fixture.notebook, 'page-1')).strokes,
        isEmpty,
      );
      expect(
        (await fixture.repository.loadPage(fixture.notebook, 'page-2')).strokes,
        hasLength(1),
      );

      tester.view.physicalSize = const Size(834, 1194);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('continuous-page-list')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('centralizes current-page actions in the Pages panel', (
      tester,
    ) async {
      await _createFixture(tester, const Size(834, 1194));

      await tester.tap(find.byKey(const ValueKey('editor-pages-button')));
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 1'), findsWidgets);
      expect(
        find.byKey(const ValueKey('pages-add-page-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pages-template-button')), findsNothing);
      expect(find.byKey(const ValueKey('pages-bookmark-button')), findsNothing);
      expect(find.byKey(const ValueKey('pages-rotate-button')), findsNothing);
      expect(
        find.byKey(const ValueKey('page-thumbnail-page-1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('pages-add-page-button')));
      await tester.pumpAndSettle();
      expect(find.text('Add page'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-template-ruled')));
      await tester.pumpAndSettle();

      expect(find.text('Page 2 of 2'), findsWidgets);
      expect(
        find.byKey(const ValueKey('page-thumbnail-page-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('page-template-layer-page-2-ruled')),
        findsOneWidget,
      );
      expect(find.text('Pages'), findsOneWidget);

      await tester.tap(find.byTooltip('Page 1'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsWidgets);
      expect(find.text('Pages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('separates document history from the editing dock', (
      tester,
    ) async {
      await _createFixture(tester, const Size(600, 800));

      expect(find.byKey(const ValueKey('editor-pages-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-undo-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-redo-button')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EditorToolbar),
          matching: find.byTooltip('Undo ink stroke'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('adapts direct actions and groups the More menu by purpose', (
      tester,
    ) async {
      await _createFixture(tester, const Size(600, 800));

      expect(find.byKey(const ValueKey('editor-record-button')), findsNothing);
      expect(find.byKey(const ValueKey('editor-export-button')), findsNothing);
      expect(
        find.byKey(const ValueKey('editor-fit-width-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('editor-more-actions')));
      await tester.pumpAndSettle();
      for (final section in const ['DOCUMENT', 'AUDIO', 'VIEW']) {
        expect(find.text(section), findsOneWidget);
      }
      expect(find.text('PAGE'), findsNothing);
      expect(find.text('Add page'), findsNothing);
      expect(find.text('Page template'), findsNothing);
      expect(find.text('Start recording'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      await tester.tapAt(const Offset(12, 300));
      await tester.pumpAndSettle();

      await _createFixture(tester, const Size(834, 1194));
      expect(
        find.byKey(const ValueKey('editor-record-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('editor-export-button')), findsNothing);

      await _createFixture(tester, const Size(1194, 834));
      expect(
        find.byKey(const ValueKey('editor-record-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-export-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps zoom off paper and exposes Fit width in the header', (
      tester,
    ) async {
      await _createFixture(tester, const Size(834, 1194));

      final pageItem = find.byKey(
        const ValueKey('continuous-page-item-page-1'),
      );
      final fitWidthButton = find.byKey(
        const ValueKey('editor-fit-width-button'),
      );
      final fitWidthPageHeight = tester.getSize(pageItem).height;
      expect(find.byKey(const ValueKey('editor-zoom-chip')), findsNothing);
      expect(find.byTooltip('Zoom and fit'), findsNothing);
      expect(fitWidthButton, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('editor-more-actions')));
      await tester.pumpAndSettle();
      expect(find.text('Zoom out'), findsOneWidget);
      expect(find.text('Zoom in'), findsOneWidget);
      expect(find.text('Fit width'), findsNothing);
      expect(find.text('Fit page'), findsNothing);

      await tester.tap(find.text('Zoom in'));
      await tester.pumpAndSettle();
      expect(tester.getSize(pageItem).height, greaterThan(fitWidthPageHeight));

      await tester.pump(const Duration(milliseconds: 1800));
      await tester.tap(fitWidthButton);
      await tester.pump();

      expect(
        tester.getSize(pageItem).height,
        closeTo(fitWidthPageHeight, 0.01),
      );
      expect(find.textContaining('%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'saves drawing after resize in canonical document coordinates',
      (tester) async {
        final fixture = await _createFixture(tester, const Size(600, 800));

        tester.view.physicalSize = const Size(800, 600);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('editor-more-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zoom in'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('editor-fit-width-button')));
        await tester.pump();

        final canvas = find.byType(DrawingCanvas);
        expect(tester.getSize(canvas), defaultNotePageSize);

        final canvasRect = tester.getRect(canvas);
        final visibleRect = canvasRect.intersect(
          Offset.zero &
              (tester.view.physicalSize / tester.view.devicePixelRatio),
        );
        final strokeStart = visibleRect.center;
        final gesture = await tester.startGesture(
          strokeStart,
          kind: ui.PointerDeviceKind.stylus,
        );
        await gesture.moveBy(const Offset(8, 8));
        await gesture.up();
        await tester.pumpAndSettle();

        final persistedPage = await fixture.repository.loadPage(
          fixture.notebook,
          'page-1',
        );
        expect(persistedPage.strokes, hasLength(1));

        final offsets = [
          for (final point in persistedPage.strokes.single.points) point.offset,
        ];
        expect(offsets, isNotEmpty);
        expect(
          offsets.every(
            (offset) =>
                offset.dx >= 0 &&
                offset.dx <= persistedPage.width &&
                offset.dy >= 0 &&
                offset.dy <= persistedPage.height,
          ),
          isTrue,
        );
        expect(offsets.last.dx, greaterThan(offsets.first.dx));
        expect(offsets.last.dy, greaterThan(offsets.first.dy));
      },
    );
  });
}

Future<_EditorFixture> _createFixture(
  WidgetTester tester,
  Size surfaceSize,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final repository = InMemoryNotebookRepository();
  final notebook = await repository.createNotebook(title: 'Workspace notes');

  await tester.pumpWidget(
    MaterialApp(
      theme: buildInkNestTheme(),
      home: EditorScreen(notebook: notebook, notebookRepository: repository),
    ),
  );
  await tester.pumpAndSettle();

  return _EditorFixture(repository: repository, notebook: notebook);
}

class _EditorFixture {
  const _EditorFixture({required this.repository, required this.notebook});

  final InMemoryNotebookRepository repository;
  final Notebook notebook;
}
