import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/theme.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/notebook.dart';
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
        final viewport = find.byKey(const ValueKey('viewport-page-1'));

        expect(tester.getSize(surface), const Size(768, 1024));
        expect(
          tester.getSize(find.byType(DrawingCanvas)),
          const Size(768, 1024),
        );
        final portraitViewportSize = tester.getSize(viewport);

        tester.view.physicalSize = const Size(1194, 834);
        await tester.pumpAndSettle();

        expect(tester.getSize(viewport), isNot(portraitViewportSize));
        expect(tester.getSize(surface), const Size(768, 1024));
        expect(
          tester.getSize(find.byType(DrawingCanvas)),
          const Size(768, 1024),
        );

        final persistedPage = await fixture.repository.loadPage(
          fixture.notebook,
          'page-1',
        );
        expect(
          Size(persistedPage.width, persistedPage.height),
          const Size(768, 1024),
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
          matching: find.byIcon(Icons.library_books_outlined),
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
      'keeps page navigation in the header without a floating page chip',
      (tester) async {
        await _createFixture(tester, const Size(834, 1194));

        expect(
          find.byKey(const ValueKey('editor-pages-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('editor-page-position-button')),
          findsNothing,
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('editor-document-context')))
              .right,
          lessThan(
            tester
                .getRect(find.byKey(const ValueKey('editor-pages-button')))
                .left,
          ),
        );
        expect(find.byKey(const ValueKey('editor-zoom-chip')), findsOneWidget);
      },
    );

    testWidgets('uses a second navigation row without overflow on phones', (
      tester,
    ) async {
      await _createFixture(tester, const Size(390, 844));

      final documentContext = find.byKey(
        const ValueKey('editor-document-context'),
      );
      final compactNavigation = find.byKey(
        const ValueKey('editor-compact-navigation-row'),
      );

      expect(documentContext, findsOneWidget);
      expect(compactNavigation, findsOneWidget);
      expect(
        tester.getRect(compactNavigation).top,
        greaterThanOrEqualTo(tester.getRect(documentContext).bottom),
      );
      expect(find.byKey(const ValueKey('editor-pages-button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-outline-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-bookmarks-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the header pager for adjacent navigation and quick add', (
      tester,
    ) async {
      await _createFixture(tester, const Size(600, 800));

      final previous = find.byKey(
        const ValueKey('editor-previous-page-button'),
      );
      final next = find.byKey(const ValueKey('editor-next-page-button'));
      final add = find.byKey(const ValueKey('editor-add-page-button'));

      expect(tester.widget<IconButton>(previous).onPressed, isNull);
      expect(tester.widget<IconButton>(next).onPressed, isNull);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(tester.getSize(previous).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(previous).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(add).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(add).height, greaterThanOrEqualTo(44));

      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(find.text('Add page'), findsOneWidget);
      await tester.tap(find.byTooltip('Close paper styles'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);

      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-template-blank')));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(tester.widget<IconButton>(previous).onPressed, isNotNull);
      expect(tester.widget<IconButton>(next).onPressed, isNull);

      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(tester.widget<IconButton>(next).onPressed, isNotNull);

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
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
      expect(find.byKey(const ValueKey('pages-rotate-button')), findsOneWidget);
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

      expect(
        find.byKey(const ValueKey('editor-document-context')),
        findsOneWidget,
      );
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

    testWidgets('exposes Fit width and Fit page from the zoom menu', (
      tester,
    ) async {
      await _createFixture(tester, const Size(834, 1194));

      expect(find.text('Fit width'), findsNothing);
      expect(find.text('Fit page'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('editor-zoom-chip')));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom and fit'));
      await tester.pumpAndSettle();

      expect(find.text('Fit width'), findsOneWidget);
      expect(find.text('Fit page'), findsOneWidget);
    });

    testWidgets('exposes Fit width and Fit page from More View actions', (
      tester,
    ) async {
      await _createFixture(tester, const Size(834, 1194));

      await tester.tap(find.byKey(const ValueKey('editor-more-actions')));
      await tester.pumpAndSettle();
      expect(find.text('Fit width'), findsOneWidget);
      expect(find.text('Fit page'), findsOneWidget);

      await tester.tap(find.text('Fit page'));
      await tester.pump();

      expect(find.byKey(const ValueKey('editor-zoom-chip')), findsNothing);
      expect(find.byTooltip('Zoom and fit'), findsOneWidget);
    });

    testWidgets(
      'saves drawing after resize in canonical document coordinates',
      (tester) async {
        final fixture = await _createFixture(tester, const Size(600, 800));

        tester.view.physicalSize = const Size(800, 600);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('editor-zoom-chip')));
        await tester.pump();
        await tester.tap(find.byTooltip('Zoom and fit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fit page'));
        await tester.pump();

        final canvas = find.byType(DrawingCanvas);
        expect(tester.getSize(canvas), const Size(768, 1024));

        final strokeStart =
            tester.getBottomRight(canvas) - const Offset(32, 32);
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
        expect(
          offsets.map((offset) => offset.dx).reduce(_maximum),
          greaterThan(650),
        );
        expect(
          offsets.map((offset) => offset.dy).reduce(_maximum),
          greaterThan(850),
        );
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

double _maximum(double first, double second) => first > second ? first : second;

class _EditorFixture {
  const _EditorFixture({required this.repository, required this.notebook});

  final InMemoryNotebookRepository repository;
  final Notebook notebook;
}
