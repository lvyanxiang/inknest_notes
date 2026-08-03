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

    testWidgets(
      'opens Pages Outline and Bookmarks on demand in a compact workspace',
      (tester) async {
        await _createFixture(tester, const Size(600, 800));

        expect(
          find.byKey(const ValueKey('editor-pages-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('page-thumbnail-page-1')),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('editor-pages-button')));
        await tester.pumpAndSettle();

        expect(find.text('Pages'), findsOneWidget);
        expect(find.text('Outline'), findsOneWidget);
        expect(find.text('Bookmarks'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('page-thumbnail-page-1')),
          findsOneWidget,
        );
      },
    );

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
        expect(find.byKey(const ValueKey('editor-zoom-chip')), findsOneWidget);
      },
    );

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
      for (final section in const ['PAGE', 'DOCUMENT', 'AUDIO', 'VIEW']) {
        expect(find.text(section), findsOneWidget);
      }
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
