import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/features/editor/infinite_canvas_screen.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_page_template.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/notebook_audio_recording.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';

void main() {
  const digitalInkChannel = MethodChannel(
    'google_mlkit_digital_ink_recognizer',
  );

  Future<void> pumpInkNestApp(WidgetTester tester) async {
    await tester.pumpWidget(
      InkNestApp(notebookRepository: InMemoryNotebookRepository()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> createPagedNotebook(
    WidgetTester tester, {
    bool useTooltip = false,
  }) async {
    await tester.tap(
      useTooltip
          ? find.byTooltip('New notebook')
          : find.text('New notebook').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-paged-notebook')));
    await tester.pumpAndSettle();
  }

  Future<void> selectEditorMoreAction(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('editor-more-actions')));
    await tester.pumpAndSettle();
    final action = find.text(label).last;
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  Future<void> openEditorPages(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('editor-pages-button')));
    await tester.pumpAndSettle();
  }

  Future<void> dismissEditorPages(WidgetTester tester) async {
    final logicalSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(logicalSize.width - 12, logicalSize.height / 2));
    await tester.pumpAndSettle();
  }

  Future<void> addPageAfterCurrent(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('editor-add-page-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-template-blank')));
    await tester.pumpAndSettle();
  }

  Future<void> selectInsertAction(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('editor-insert-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Offset visibleCanvasPoint(
    WidgetTester tester, {
    double horizontalFraction = 0.35,
    double verticalInset = 112,
  }) {
    final canvasRect = tester.getRect(find.byType(DrawingCanvas));
    final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final visibleRect = canvasRect.intersect(Offset.zero & viewSize);
    expect(visibleRect.width, greaterThan(96));
    expect(visibleRect.height, greaterThan(96));
    return Offset(
      visibleRect.left + visibleRect.width * horizontalFraction,
      (visibleRect.top + verticalInset).clamp(
        visibleRect.top + 24,
        visibleRect.bottom - 24,
      ),
    );
  }

  Future<void> drawVisibleStroke(
    WidgetTester tester, {
    ui.PointerDeviceKind kind = ui.PointerDeviceKind.touch,
  }) async {
    final start = visibleCanvasPoint(tester);
    final gesture = await tester.startGesture(start, kind: kind);
    await gesture.moveBy(const Offset(48, 16));
    await gesture.up();
    await tester.pump();
  }

  Future<void> selectVisibleStrokeWithLasso(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Lasso'));
    await tester.pumpAndSettle();

    final start = visibleCanvasPoint(tester);
    final lasso = await tester.startGesture(start - const Offset(24, 24));
    await lasso.moveTo(start + const Offset(88, -24));
    await lasso.moveTo(start + const Offset(88, 56));
    await lasso.moveTo(start + const Offset(-24, 56));
    await lasso.moveTo(start - const Offset(24, 24));
    await lasso.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lasso-selection-toolbar')),
      findsOneWidget,
    );
  }

  testWidgets('shows the notebook library shell', (WidgetTester tester) async {
    await pumpInkNestApp(tester);

    expect(find.text('InkNest Notes'), findsOneWidget);
    expect(find.text('No notebooks yet'), findsOneWidget);
    expect(find.text('New notebook'), findsWidgets);
    expect(find.text('Import PDF'), findsOneWidget);
  });

  testWidgets('creates and opens a notebook', (WidgetTester tester) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    expect(find.text('Notebook 1'), findsOneWidget);
    expect(find.byTooltip('Start audio recording'), findsOneWidget);
    expect(find.byTooltip('Search notebook'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-more-actions')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-more-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Start recording'), findsOneWidget);
    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pen'), findsOneWidget);
    expect(find.byTooltip('Highlighter'), findsOneWidget);
    expect(find.byTooltip('Eraser'), findsOneWidget);
    expect(find.byTooltip('Lasso'), findsOneWidget);
    expect(find.byTooltip('Insert'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byTooltip('Lasso'),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('editor-insert-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Shape'), findsOneWidget);
    await tester.tapAt(const Offset(8, 180));
    await tester.pumpAndSettle();

    await openEditorPages(tester);
    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsOneWidget);
    expect(find.text('No notebooks yet'), findsNothing);
  });

  testWidgets('creates, draws, and configures an infinite canvas', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New notebook').first);
    await tester.pumpAndSettle();
    expect(find.text('Paged notebook'), findsOneWidget);
    expect(find.text('Infinite canvas'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(await repository.listNotebooks(), isEmpty);

    await tester.tap(find.text('New notebook').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-infinite-canvas')));
    await tester.pumpAndSettle();

    expect(find.text('Infinite canvas'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-pages-button')), findsNothing);
    expect(find.byKey(const ValueKey('editor-bookmarks-button')), findsNothing);
    expect(find.byTooltip('Lasso'), findsOneWidget);
    expect(find.byTooltip('Insert'), findsOneWidget);
    final topToolbar = find.byKey(
      const ValueKey('infinite-canvas-top-toolbar'),
    );
    expect(topToolbar, findsOneWidget);
    expect(
      find.ancestor(of: topToolbar, matching: find.byType(AppBar)),
      findsOneWidget,
    );

    final viewport = find.byKey(const ValueKey('infinite-canvas-viewport'));
    final viewportClip = find.byKey(
      const ValueKey('infinite-canvas-viewport-clip'),
    );
    expect(viewportClip, findsOneWidget);
    expect(
      find.descendant(of: viewportClip, matching: find.byType(CustomPaint)),
      findsWidgets,
    );
    expect(
      tester.getBottomLeft(topToolbar).dy,
      lessThanOrEqualTo(tester.getTopLeft(viewport).dy),
    );
    final center = tester.getCenter(viewport);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(64, 24));
    await gesture.up();
    await tester.pumpAndSettle();

    final notebook = (await repository.listNotebooks()).single;
    expect(notebook.layoutMode, NotebookLayoutMode.infiniteCanvas);
    expect(notebook.pageIds, isEmpty);
    expect(
      (await repository.loadInfiniteCanvas(notebook)).strokes,
      hasLength(1),
    );

    final firstFinger = await tester.startGesture(
      center - const Offset(28, 0),
      pointer: 17,
    );
    final secondFinger = await tester.startGesture(
      center + const Offset(28, 0),
      pointer: 18,
    );
    await firstFinger.moveBy(const Offset(-24, 8));
    await secondFinger.moveBy(const Offset(24, 8));
    await firstFinger.up();
    await secondFinger.up();
    await tester.pumpAndSettle();
    final transformed = await repository.loadInfiniteCanvas(notebook);
    expect(transformed.strokes, hasLength(1));
    expect(transformed.viewportScale, greaterThan(1));

    await tester.tap(find.byKey(const ValueKey('infinite-canvas-background')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grid').last);
    await tester.pumpAndSettle();
    expect(
      (await repository.loadInfiniteCanvas(notebook)).background,
      InfiniteCanvasBackground.grid,
    );

    await tester.tap(find.byKey(const ValueKey('infinite-canvas-undo')));
    await tester.pumpAndSettle();
    expect((await repository.loadInfiniteCanvas(notebook)).strokes, isEmpty);
  });

  testWidgets('keeps the infinite canvas header responsive', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(600, 800),
      Size(834, 1194),
      Size(1194, 834),
    ]) {
      tester.view.physicalSize = size;
      final repository = InMemoryNotebookRepository();
      final notebook = await repository.createNotebook(
        title: 'Spatial notes',
        layoutMode: NotebookLayoutMode.infiniteCanvas,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InfiniteCanvasScreen(
            notebook: notebook,
            notebookRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final toolbar = find.byKey(const ValueKey('infinite-canvas-top-toolbar'));
      final viewport = find.byKey(const ValueKey('infinite-canvas-viewport'));
      expect(toolbar, findsOneWidget);
      expect(
        find.ancestor(of: toolbar, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(toolbar).dy,
        lessThanOrEqualTo(tester.getTopLeft(viewport).dy),
      );
      expect(
        find.byKey(const ValueKey('infinite-canvas-compact-toolbar-row')),
        size.width < 600 ? findsOneWidget : findsNothing,
      );
      if (size.width < 600) {
        expect(
          find.byKey(const ValueKey('infinite-canvas-document-context')),
          findsOneWidget,
        );
      }
      expect(find.byTooltip('Pen'), findsOneWidget);
      expect(find.byTooltip('Highlighter'), findsOneWidget);
      expect(find.byTooltip('Eraser'), findsOneWidget);
      expect(find.byTooltip('Lasso'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-insert-menu')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('infinite-canvas-undo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('infinite-canvas-recenter')),
        findsOneWidget,
      );
    }
  });

  testWidgets('adds and persists infinite canvas text and shapes', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(
      title: 'Rich canvas',
      layoutMode: NotebookLayoutMode.infiniteCanvas,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InfiniteCanvasScreen(
          notebook: notebook,
          notebookRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await selectInsertAction(tester, 'Text');
    final viewport = find.byKey(const ValueKey('infinite-canvas-viewport'));
    final center = tester.getCenter(viewport);
    await tester.tapAt(center - const Offset(120, 80));
    await tester.pumpAndSettle();
    final textField = find.byKey(
      const ValueKey('text-box-field-text-placeholder'),
    );
    final actualTextField = find.byType(TextField).last;
    expect(actualTextField, findsOneWidget);
    expect(textField, findsNothing);
    await tester.enterText(actualTextField, 'Spatial idea');
    await tester.pump();

    var document = await repository.loadInfiniteCanvas(notebook);
    expect(document.textBoxes.single.text, 'Spatial idea');
    final initialTextPosition = document.textBoxes.single.position;
    await tester.drag(find.byTooltip('Move text box'), const Offset(44, 28));
    await tester.pump();
    document = await repository.loadInfiniteCanvas(notebook);
    expect(document.textBoxes.single.position, isNot(initialTextPosition));

    await selectInsertAction(tester, 'Shape');
    final shapeGesture = await tester.startGesture(
      center + const Offset(80, 80),
      kind: ui.PointerDeviceKind.stylus,
    );
    await shapeGesture.moveBy(const Offset(120, 72));
    await shapeGesture.up();
    await tester.pumpAndSettle();

    document = await repository.loadInfiniteCanvas(notebook);
    expect(document.shapes, hasLength(1));
    expect(
      document.shapes.single.start.dx,
      isNot(document.shapes.single.end.dx),
    );

    await tester.tap(find.byKey(const ValueKey('infinite-canvas-undo')));
    await tester.pumpAndSettle();
    document = await repository.loadInfiniteCanvas(notebook);
    expect(document.shapes, isEmpty);
    expect(document.textBoxes.single.text, 'Spatial idea');

    await tester.tap(find.byKey(const ValueKey('infinite-canvas-redo')));
    await tester.pumpAndSettle();
    document = await repository.loadInfiniteCanvas(notebook);
    expect(document.shapes, hasLength(1));

    await tester.tap(find.byTooltip('Delete text box'));
    await tester.pumpAndSettle();
    expect((await repository.loadInfiniteCanvas(notebook)).textBoxes, isEmpty);
  });

  testWidgets('infinite canvas lasso selects and deletes ink', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(
      title: 'Lasso canvas',
      layoutMode: NotebookLayoutMode.infiniteCanvas,
    );
    await repository.saveInfiniteCanvas(
      notebook,
      InfiniteCanvasDocument(
        strokes: [
          Stroke(
            id: 'canvas-ink',
            tool: ToolType.pen,
            color: const Color(0xFF1E2526),
            width: 4,
            points: [
              StrokePoint(
                offset: const Offset(-24, 0),
                pressure: 1,
                time: DateTime.utc(2026, 8, 4),
              ),
              StrokePoint(
                offset: const Offset(24, 0),
                pressure: 1,
                time: DateTime.utc(2026, 8, 4),
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InfiniteCanvasScreen(
          notebook: notebook,
          notebookRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Lasso'));
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(const ValueKey('infinite-canvas-viewport')),
    );
    final lasso = await tester.startGesture(center - const Offset(60, 50));
    await lasso.moveTo(center + const Offset(60, -50));
    await lasso.moveTo(center + const Offset(60, 50));
    await lasso.moveTo(center + const Offset(-60, 50));
    await lasso.moveTo(center - const Offset(60, 50));
    await lasso.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lasso-selection-toolbar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lasso-smart-ink')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lasso-delete-selection')));
    await tester.pumpAndSettle();
    expect((await repository.loadInfiniteCanvas(notebook)).strokes, isEmpty);
  });

  testWidgets('infinite canvas inserts moves resizes and deletes an image', (
    WidgetTester tester,
  ) async {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'inknest-canvas-widget-',
    );
    addTearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });
    final sourceFile = File('${tempDirectory.path}/source.png');
    sourceFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA'
        'ASsJTYQAAAAASUVORK5CYII=',
      ),
    );
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(
      title: 'Image canvas',
      layoutMode: NotebookLayoutMode.infiniteCanvas,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InfiniteCanvasScreen(
          notebook: notebook,
          notebookRepository: repository,
          imageFilePicker: () async => sourceFile,
          imageSizeReader: (_) async => const Size(1, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('editor-insert-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image').last);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
    var document = await repository.loadInfiniteCanvas(notebook);
    expect(document.images, hasLength(1));
    final initial = document.images.single;

    await tester.drag(find.byTooltip('Move image'), const Offset(48, 32));
    await tester.pump();
    document = await repository.loadInfiniteCanvas(notebook);
    expect(document.images.single.position, isNot(initial.position));

    final beforeResize = document.images.single.width;
    await tester.drag(find.byTooltip('Resize image'), const Offset(36, 20));
    await tester.pump();
    document = await repository.loadInfiniteCanvas(notebook);
    expect(document.images.single.width, greaterThan(beforeResize));

    await tester.tap(find.byTooltip('Delete image'));
    await tester.pump();
    expect((await repository.loadInfiniteCanvas(notebook)).images, isEmpty);
  });

  testWidgets('opens notebook search from the editor app bar', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);
    await createPagedNotebook(tester);

    await tester.tap(find.byTooltip('Search notebook'));
    await tester.pumpAndSettle();

    expect(find.text('Search notebook'), findsOneWidget);
    expect(
      find.text(
        'Search PDF text, images, scanned pages, and editable text boxes, including Smart Ink results.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Close notebook search'), findsOneWidget);
  });

  testWidgets('imports multiple PDFs into the open notebook', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'PDF collection');
    final tempDirectory = Directory.systemTemp.createTempSync(
      'inknest-multi-pdf-widget-',
    );
    addTearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });
    final firstPdf = File('${tempDirectory.path}/biology.pdf')
      ..writeAsBytesSync([1]);
    final secondPdf = File('${tempDirectory.path}/chemistry.pdf')
      ..writeAsBytesSync([2]);

    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(
          notebook: notebook,
          notebookRepository: repository,
          pdfFilePicker: () async => [firstPdf, secondPdf],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await selectEditorMoreAction(tester, 'Import PDF');

    final updatedNotebook = (await repository.listNotebooks()).single;
    expect(updatedNotebook.pageIds, ['page-1', 'page-2', 'page-3']);
    expect(updatedNotebook.pdfOutlines.map((outline) => outline.title), [
      'biology',
      'chemistry',
    ]);
    expect(
      find.byKey(const ValueKey('rotated-page-surface-page-2-0')),
      findsOneWidget,
    );
    await openEditorPages(tester);
    expect(find.byKey(const ValueKey('page-thumbnail-page-3')), findsOneWidget);
    expect(find.text('Imported 2 PDFs · 2 pages'), findsOneWidget);
  });

  testWidgets('chooses a paper style before adding a page', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Template notes');

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text(notebook.title));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('editor-add-page-button')));
    await tester.pumpAndSettle();

    expect(find.text('Add page'), findsOneWidget);
    for (final template in NotePageTemplate.values) {
      expect(find.text(template.label), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('page-template-grid')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('page-template-layer-page-2-grid')),
      findsOneWidget,
    );
    expect(
      (await repository.loadPage(notebook, 'page-2')).template,
      NotePageTemplate.grid,
    );
    expect(
      (await repository.loadPage(notebook, 'page-1')).template,
      NotePageTemplate.blank,
    );
  });

  testWidgets('rotates a page from its thumbnail action menu', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Rotated notes');

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text(notebook.title));
    await tester.pumpAndSettle();

    final portraitSurface = find.byKey(
      const ValueKey('rotated-page-surface-page-1-0'),
    );
    expect(
      tester.getSize(portraitSurface).height,
      greaterThan(tester.getSize(portraitSurface).width),
    );

    await openEditorPages(tester);
    await tester.tap(find.byTooltip('Page 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate page clockwise'));
    await tester.pumpAndSettle();

    final landscapeSurface = find.byKey(
      const ValueKey('rotated-page-surface-page-1-1'),
    );
    expect(
      tester.getSize(landscapeSurface).width,
      greaterThan(tester.getSize(landscapeSurface).height),
    );
    expect(
      (await repository.loadPage(notebook, 'page-1')).rotationQuarterTurns,
      1,
    );

    await dismissEditorPages(tester);

    await drawVisibleStroke(tester);

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });

  testWidgets('lasso moves resizes recolors and deletes selected strokes', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Lasso notes');
    await repository.savePage(
      notebook,
      NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
        strokes: [
          _testStroke(
            id: 'selected-stroke',
            offsets: const [Offset(70, 70), Offset(90, 90)],
          ),
          _testStroke(
            id: 'outside-stroke',
            offsets: const [Offset(260, 260), Offset(290, 290)],
          ),
        ],
      ),
    );

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text(notebook.title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lasso'));
    await tester.pumpAndSettle();

    final lassoRegion = find.byKey(const ValueKey('lasso-drawing-region'));
    final pageOrigin = tester.getTopLeft(lassoRegion);
    final lasso = await tester.startGesture(pageOrigin + const Offset(40, 40));
    await lasso.moveTo(pageOrigin + const Offset(130, 40));
    await lasso.moveTo(pageOrigin + const Offset(130, 130));
    await lasso.moveTo(pageOrigin + const Offset(40, 130));
    await lasso.moveTo(pageOrigin + const Offset(40, 40));
    await lasso.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lasso-selection-toolbar')),
      findsOneWidget,
    );

    var selectedStroke = (await repository.loadPage(
      notebook,
      'page-1',
    )).strokes.first;
    final originalFirstPoint = selectedStroke.points.first.offset;

    final moveRegion = find.byKey(const ValueKey('lasso-move-region'));
    final moveGesture = await tester.startGesture(
      tester.getTopLeft(moveRegion) + const Offset(3, 3),
    );
    await moveGesture.moveBy(const Offset(10, 6));
    await moveGesture.moveBy(const Offset(20, 14));
    await moveGesture.moveBy(const Offset(10, 6));
    await moveGesture.up();
    await tester.pumpAndSettle();
    selectedStroke = (await repository.loadPage(
      notebook,
      'page-1',
    )).strokes.first;
    expect(
      selectedStroke.points.first.offset.dx,
      greaterThan(originalFirstPoint.dx),
    );
    expect(
      selectedStroke.points.first.offset.dy,
      greaterThan(originalFirstPoint.dy),
    );

    final widthBeforeResize = selectedStroke.width;
    await tester.drag(
      find.byKey(const ValueKey('lasso-resize-handle')),
      const Offset(30, 30),
    );
    await tester.pumpAndSettle();
    selectedStroke = (await repository.loadPage(
      notebook,
      'page-1',
    )).strokes.first;
    expect(selectedStroke.width, greaterThan(widthBeforeResize));

    const teal = Color(0xFF2F6F73);
    await tester.tap(find.byKey(ValueKey('lasso-color-${teal.toARGB32()}')));
    await tester.pumpAndSettle();
    selectedStroke = (await repository.loadPage(
      notebook,
      'page-1',
    )).strokes.first;
    expect(selectedStroke.color, teal);

    await tester.tap(find.byKey(const ValueKey('lasso-delete-selection')));
    await tester.pumpAndSettle();
    final remainingPage = await repository.loadPage(notebook, 'page-1');
    expect(remainingPage.strokes.map((stroke) => stroke.id), [
      'outside-stroke',
    ]);
    expect(find.byKey(const ValueKey('lasso-selection-toolbar')), findsNothing);
  });

  testWidgets('searches Smart Ink text and highlights it after a page jump', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    var notebook = await repository.createNotebook(title: 'Search notes');
    notebook = await repository.addPage(notebook);
    await repository.savePage(
      notebook,
      const NotePage(
        id: 'page-2',
        width: 768,
        height: 1024,
        textBoxes: [
          NoteTextBox(
            id: 'smart-search-result',
            position: Offset(40, 48),
            text: 'Photosynthesis summary',
            style: NoteTextBoxStyle.handwriting,
          ),
        ],
      ),
    );

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search notebook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'photosynthesis');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.textContaining('Handwriting text'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebook-search-result-0')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('text-box-search-highlight-smart-search-result'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('lists saved audio recordings with playback controls', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    var notebook = await repository.createNotebook(title: 'Lecture');
    final recording = NotebookAudioRecording(
      id: 'audio-1',
      createdAt: DateTime.utc(2026, 7, 18, 9),
      duration: const Duration(seconds: 8),
      assetPath: '/tmp/audio-1.m4a',
      pageId: 'page-1',
    );
    notebook = await repository.saveAudioRecording(notebook, recording);

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(notebook.title));
    await tester.pumpAndSettle();
    await selectEditorMoreAction(tester, 'Audio recordings');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Recording 1'), findsOneWidget);
    expect(find.byTooltip('Play recording 1'), findsOneWidget);
    expect(
      find.textContaining('0:08 - 2026-07-18 09:00 - Page 1'),
      findsOneWidget,
    );
  });

  testWidgets('keeps replay ink visible and highlights the current segment', (
    WidgetTester tester,
  ) async {
    final recordingStartedAt = DateTime.utc(2026, 7, 18, 9);
    final page = NotePage(
      id: 'page-1',
      width: 200,
      height: 100,
      strokes: [
        Stroke(
          id: 'stroke-1',
          tool: ToolType.pen,
          color: Colors.black,
          width: 4,
          audioRecordingId: 'audio-1',
          points: [
            StrokePoint(
              offset: const Offset(20, 50),
              pressure: 1,
              time: recordingStartedAt.add(const Duration(seconds: 5)),
            ),
            StrokePoint(
              offset: const Offset(180, 50),
              pressure: 1,
              time: recordingStartedAt.add(const Duration(milliseconds: 5500)),
            ),
          ],
        ),
      ],
    );
    final boundaryKey = GlobalKey();

    Widget buildCanvas(Duration replayPosition) {
      return MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 200,
            height: 100,
            child: DrawingCanvas(
              page: page,
              tool: const DrawingTool(),
              fingerPanEnabled: false,
              fingerWritingAssistEnabled: true,
              onStrokeComplete: (_) {},
              onErase: (_) {},
              replayRecordingId: 'audio-1',
              replayStartedAt: recordingStartedAt,
              replayPosition: replayPosition,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildCanvas(Duration.zero));
    await tester.pump();

    expect(
      await _capturePixelAlpha(tester, boundaryKey, 100, 50),
      greaterThan(0),
    );
    expect(await _capturePixelAlpha(tester, boundaryKey, 100, 55), 0);

    await tester.pumpWidget(buildCanvas(const Duration(milliseconds: 5500)));
    await tester.pump();

    expect(
      await _capturePixelAlpha(tester, boundaryKey, 100, 55),
      greaterThan(0),
    );
  });

  testWidgets('adds edits persists and deletes editor text boxes', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);
    await selectInsertAction(tester, 'Text');

    await tester.tapAt(visibleCanvasPoint(tester));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Typed note');
    await tester.pumpAndSettle();

    expect(find.text('Typed note'), findsOneWidget);
    expect(find.byTooltip('Handwriting style'), findsOneWidget);

    await tester.tap(find.byTooltip('Handwriting style'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Plain text'), findsOneWidget);

    await addPageAfterCurrent(tester);
    await openEditorPages(tester);
    await tester.tap(find.byTooltip('Page 1'));
    await tester.pumpAndSettle();
    await dismissEditorPages(tester);

    expect(find.text('Typed note'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete text box'));
    await tester.pumpAndSettle();

    expect(find.text('Typed note'), findsNothing);
  });

  testWidgets('beautifies selected handwriting into ink strokes', (
    WidgetTester tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const recordChannel = MethodChannel('com.llfbandit.record/messages');
    messenger.setMockMethodCallHandler(recordChannel, (call) async => null);
    messenger.setMockMethodCallHandler(
      digitalInkChannel,
      (call) => throw PlatformException(code: 'recognition_unavailable'),
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(digitalInkChannel, null);
      messenger.setMockMethodCallHandler(recordChannel, null);
    });
    final repository = InMemoryNotebookRepository();
    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    await createPagedNotebook(tester);

    await drawVisibleStroke(tester);
    final originalPage = tester
        .widget<DrawingCanvas>(find.byType(DrawingCanvas))
        .page;
    expect(originalPage.strokes, hasLength(1));
    await selectVisibleStrokeWithLasso(tester);
    await tester.tap(find.byKey(const ValueKey('lasso-smart-ink')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Beautify ink'),
      ),
      findsOneWidget,
    );
    expect(find.text('Selected 1 strokes'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.byKey(const ValueKey('beautify-font-liu_jian_mao_cao')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('beautify-font-long_cang')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('beautify-font-zhi_mang_xing')),
      findsOneWidget,
    );

    // Use a glyph available in Flutter's test font. The production app loads
    // the bundled Chinese handwriting fonts declared in pubspec.yaml.
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('beautify-font-long_cang')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('beautify-confirm')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    // Glyph thinning can take multiple frames; avoid pumpAndSettle hanging on
    // transient overlays.
    for (var i = 0; i < 80; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      final canvasPage = tester
          .widget<DrawingCanvas>(find.byType(DrawingCanvas))
          .page;
      if (canvasPage.strokes.any(
            (stroke) => stroke.id.startsWith('beautify-'),
          ) &&
          find.byType(AlertDialog).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Plain text'), findsNothing);
    expect(
      find.byKey(const ValueKey('lasso-selection-toolbar')),
      findsOneWidget,
    );

    final beautifiedPage = tester
        .widget<DrawingCanvas>(find.byType(DrawingCanvas))
        .page;
    expect(beautifiedPage.strokes, isNotEmpty);
    expect(
      beautifiedPage.strokes.every(
        (stroke) => stroke.id.startsWith('beautify-'),
      ),
      isTrue,
    );
    expect(
      beautifiedPage.strokes.map((stroke) => stroke.toJson()).toList(),
      isNot(originalPage.strokes.map((stroke) => stroke.toJson()).toList()),
    );

    final undoButton = find.byKey(const ValueKey('editor-undo-button'));
    final redoButton = find.byKey(const ValueKey('editor-redo-button'));
    await tester.tap(undoButton);
    await tester.pump();
    final restoredRoughPage = tester
        .widget<DrawingCanvas>(find.byType(DrawingCanvas))
        .page;
    expect(
      restoredRoughPage.strokes.map((stroke) => stroke.toJson()).toList(),
      originalPage.strokes.map((stroke) => stroke.toJson()).toList(),
    );

    await tester.tap(redoButton);
    await tester.pump();
    final restoredBeautifiedPage = tester
        .widget<DrawingCanvas>(find.byType(DrawingCanvas))
        .page;
    expect(
      restoredBeautifiedPage.strokes.map((stroke) => stroke.toJson()).toList(),
      beautifiedPage.strokes.map((stroke) => stroke.toJson()).toList(),
    );

    await tester.tap(find.byTooltip('Eraser'));
    await tester.pump();
    final eraseStart = visibleCanvasPoint(tester);
    final eraserGesture = await tester.startGesture(eraseStart);
    await eraserGesture.moveBy(const Offset(28, 12));
    await eraserGesture.up();
    await tester.pump();
    final partiallyErasedPage = tester
        .widget<DrawingCanvas>(find.byType(DrawingCanvas))
        .page;
    expect(
      partiallyErasedPage.strokes.map((stroke) => stroke.toJson()).toList(),
      isNot(
        restoredBeautifiedPage.strokes
            .map((stroke) => stroke.toJson())
            .toList(),
      ),
    );

    await tester.tap(undoButton);
    await tester.pump();
    final restoredAfterErase = tester
        .widget<DrawingCanvas>(find.byType(DrawingCanvas))
        .page;
    expect(
      restoredAfterErase.strokes.map((stroke) => stroke.toJson()).toList(),
      restoredBeautifiedPage.strokes.map((stroke) => stroke.toJson()).toList(),
    );
  });

  testWidgets('prefills Beautify with an on-device recognition suggestion', (
    WidgetTester tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      digitalInkChannel,
      (call) async => switch (call.method) {
        'vision#manageInkModels' => true,
        'vision#startDigitalInkRecognizer' => <Object?>[
          <String, Object?>{'text': 'Recognized note', 'score': -0.9},
        ],
        'vision#closeDigitalInkRecognizer' => null,
        _ => throw PlatformException(code: 'unexpected_method'),
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(digitalInkChannel, null),
    );
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);
    await drawVisibleStroke(tester);
    await selectVisibleStrokeWithLasso(tester);
    await tester.tap(find.byKey(const ValueKey('lasso-smart-ink')));
    await tester.pumpAndSettle();

    expect(find.text('Recognized note'), findsWidgets);
    expect(
      find.text('Choose a style to redraw the selected ink.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('beautify-edit-text')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('beautify-confirm')));
    await tester.pump();
    for (var i = 0; i < 80; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Redrawing as ink...').evaluate().isEmpty &&
          find.byType(AlertDialog).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byKey(const ValueKey('lasso-selection-toolbar')),
      findsOneWidget,
    );
  });

  testWidgets('selects non-contiguous pages for PDF export', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);
    for (var index = 0; index < 3; index++) {
      await addPageAfterCurrent(tester);
    }

    await selectEditorMoreAction(tester, 'Export PDF');

    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('All 4 pages'), findsOneWidget);
    expect(find.text('Compact'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Best'), findsOneWidget);
    expect(
      find.text('Recommended balance of clarity and size.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(
      find.text('Smaller file for sharing and submission.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();

    expect(find.text('Choose individual pages or page ranges'), findsOneWidget);
    expect(find.text('Separate pages or ranges with commas.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1,3-4');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Export'))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(find.byType(TextField), '1,9');
    await tester.pumpAndSettle();

    expect(find.text('Pages must be between 1 and 4.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Export'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Export PDF'), findsNothing);
  });

  testWidgets('manages notebooks from the library spine menu', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notebook 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename notebook'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Project Notes',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Project Notes'), findsOneWidget);
    expect(find.text('Notebook 1'), findsNothing);

    await tester.tap(find.byTooltip('Project Notes actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate notebook'));
    await tester.pumpAndSettle();

    expect(find.text('Project Notes'), findsOneWidget);
    expect(find.text('Project Notes Copy'), findsOneWidget);

    await tester.tap(find.byTooltip('Project Notes actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive notebook'));
    await tester.pumpAndSettle();

    expect(find.text('Project Notes'), findsNothing);
    expect(find.text('Project Notes Copy'), findsOneWidget);

    await tester.tap(find.byTooltip('Show archived'));
    await tester.pumpAndSettle();

    expect(find.text('Project Notes'), findsOneWidget);
    expect(find.text('Project Notes Copy'), findsNothing);

    await tester.tap(find.byTooltip('Project Notes actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore notebook'));
    await tester.pumpAndSettle();

    expect(find.text('No archived notebooks'), findsOneWidget);

    await tester.tap(find.byTooltip('Show notebooks'));
    await tester.pumpAndSettle();

    expect(find.text('Project Notes'), findsOneWidget);
    expect(find.text('Project Notes Copy'), findsOneWidget);

    await tester.tap(find.byTooltip('Project Notes Copy actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete notebook'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Project Notes'), findsOneWidget);
    expect(find.text('Project Notes Copy'), findsNothing);
  });

  testWidgets('creates folders and moves notebooks into folders', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Class Notes',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Class Notes'), findsOneWidget);
    expect(find.text('Notebook 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Notebook 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move notebook'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Class Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Class Notes'), findsOneWidget);
    expect(find.text('Notebook 1'), findsNothing);

    await tester.tap(find.text('Class Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Class Notes'), findsOneWidget);
    expect(find.text('Notebook 1'), findsOneWidget);
    expect(find.byTooltip('Show library'), findsOneWidget);
  });

  testWidgets(
    'labels infinite canvas spines with an accessible infinity mark',
    (WidgetTester tester) async {
      final repository = InMemoryNotebookRepository();
      await repository.createNotebook(
        title: 'Spatial map',
        layoutMode: NotebookLayoutMode.infiniteCanvas,
      );

      await tester.pumpWidget(InkNestApp(notebookRepository: repository));
      await tester.pumpAndSettle();

      expect(find.text('∞'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      expect(
        find.bySemanticsLabel('Open infinite canvas notebook Spatial map'),
        findsOneWidget,
      );
    },
  );

  testWidgets('searches sorts and displays adjacent notebook spines', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await createPagedNotebook(tester, useTooltip: true);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Recent notebooks'), findsNothing);
    expect(find.text('My Library'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-command-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-search-field')), findsOneWidget);
    expect(find.bySemanticsLabel('Sort notebooks: Recent'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-bookshelf')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-bookshelf-row-0')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Open notebook Notebook 1'), findsOneWidget);
    final notebookSpines = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('notebook-spine-');
    });
    expect(notebookSpines, findsNWidgets(2));
    final firstSpineRect = tester.getRect(notebookSpines.at(0));
    final secondSpineRect = tester.getRect(notebookSpines.at(1));
    expect(secondSpineRect.left - firstSpineRect.right, closeTo(0, 0.01));
    expect(secondSpineRect.bottom, closeTo(firstSpineRect.bottom, 0.01));
    final spineLeanEntries = <double>[];
    for (var index = 0; index < 2; index++) {
      final spineLean = tester.widget<Transform>(
        find
            .descendant(
              of: notebookSpines.at(index),
              matching: find.byWidgetPredicate((widget) {
                final key = widget.key;
                return widget is Transform &&
                    key is ValueKey<String> &&
                    key.value.startsWith('spine-lean-');
              }),
            )
            .first,
      );
      final leanEntry = spineLean.transform.entry(1, 0);
      spineLeanEntries.add(leanEntry);
      expect(leanEntry, lessThan(-0.05));
    }
    expect(spineLeanEntries[1], closeTo(spineLeanEntries[0], 0.000001));

    await tester.enterText(
      find.byKey(const ValueKey('library-search-field')),
      '2',
    );
    await tester.pumpAndSettle();

    expect(find.text('Notebook 2'), findsOneWidget);
    expect(find.text('Notebook 1'), findsNothing);
    expect(find.text('Recent notebooks'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sort notebooks'));
    await tester.pumpAndSettle();
    final titleSortItem = find.ancestor(
      of: find.text('Title'),
      matching: find.byWidgetPredicate(
        (widget) => widget is CheckedPopupMenuItem,
      ),
    );
    await tester.tap(titleSortItem);
    await tester.pumpAndSettle();

    final firstNotebookPosition = tester.getTopLeft(find.text('Notebook 1'));
    final secondNotebookPosition = tester.getTopLeft(find.text('Notebook 2'));
    expect(firstNotebookPosition.dx, lessThan(secondNotebookPosition.dx));
  });

  testWidgets('pulls a notebook forward before opening without straightening', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    await repository.createNotebook(title: 'Animation notes');

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    final notebook = find.bySemanticsLabel('Open notebook Animation notes');
    final scale = find.byKey(
      const ValueKey('spine-scale-Open notebook Animation notes'),
    );
    final lean = find.byKey(
      const ValueKey('spine-lean-Open notebook Animation notes'),
    );

    expect(tester.widget<AnimatedScale>(scale).scale, 1);
    await tester.tap(notebook);
    await tester.pump();

    expect(tester.widget<AnimatedScale>(scale).scale, 1.04);
    expect(
      tester.widget<Transform>(lean).transform.entry(1, 0),
      lessThan(-0.05),
    );
    expect(find.byKey(const ValueKey('editor-more-actions')), findsNothing);

    await tester.pump(const Duration(milliseconds: 199));
    expect(find.byKey(const ValueKey('editor-more-actions')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-more-actions')), findsOneWidget);
  });

  testWidgets('inspects spines and tips only truncated notebook titles', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    const shortTitle = 'Short';
    const longTitle =
        'A very long notebook title that cannot fit on a single narrow spine';
    await repository.createNotebook(title: shortTitle);
    await repository.createNotebook(title: longTitle);

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    final longNotebook = find.bySemanticsLabel('Open notebook $longTitle');
    final longScale = find.byKey(
      const ValueKey(
        'spine-scale-Open notebook A very long notebook title that cannot fit on a single narrow spine',
      ),
    );

    expect(find.byTooltip(longTitle), findsNothing);
    await tester.longPress(longNotebook);
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedScale>(longScale).scale, 1.04);
    expect(find.byTooltip(longTitle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-command-bar')));
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedScale>(longScale).scale, 1);
    expect(find.byTooltip(longTitle), findsNothing);

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('library-command-bar')),
      ),
    );
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(tester.getCenter(longNotebook));
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedScale>(longScale).scale, 1.04);
    expect(find.byTooltip(longTitle), findsOneWidget);

    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('library-command-bar'))),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedScale>(longScale).scale, 1);
    expect(find.byTooltip(longTitle), findsNothing);

    final shortNotebook = find.bySemanticsLabel('Open notebook $shortTitle');
    final shortScale = find.byKey(
      const ValueKey('spine-scale-Open notebook Short'),
    );
    await tester.longPress(shortNotebook);
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedScale>(shortScale).scale, 1.04);
    expect(find.byTooltip(shortTitle), findsNothing);

    await tester.tap(shortNotebook);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-more-actions')), findsOneWidget);
  });

  testWidgets('opens immediately when reduced motion is enabled', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repository = InMemoryNotebookRepository();
    await repository.createNotebook(title: 'Reduced motion notes');

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    final notebook = find.bySemanticsLabel(
      'Open notebook Reduced motion notes',
    );
    final scale = find.byKey(
      const ValueKey('spine-scale-Open notebook Reduced motion notes'),
    );

    await tester.tap(notebook);
    expect(tester.widget<AnimatedScale>(scale).scale, 1);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-more-actions')), findsOneWidget);
  });

  testWidgets('widens notebook spines as page count grows', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final thinNotebook = await repository.createNotebook(title: 'Thin notes');
    var thickNotebook = await repository.createNotebook(title: 'Thick notes');
    for (var index = 1; index < 50; index++) {
      thickNotebook = await repository.addPage(thickNotebook);
    }

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    final thinSpine = find.byKey(ValueKey('notebook-spine-${thinNotebook.id}'));
    final thickSpine = find.byKey(
      ValueKey('notebook-spine-${thickNotebook.id}'),
    );

    expect(
      tester.getSize(thickSpine).width,
      greaterThan(tester.getSize(thinSpine).width),
    );
    expect(find.text('50p'), findsOneWidget);
  });

  testWidgets('refreshes shelf metadata after adding editor pages', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Growing notes');

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    final notebookSpine = find.byKey(ValueKey('notebook-spine-${notebook.id}'));
    final initialSpineWidth = tester.getSize(notebookSpine).width;
    expect(find.text('1p'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Open notebook Growing notes'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 5; index++) {
      await addPageAfterCurrent(tester);
    }
    await openEditorPages(tester);
    expect(find.byKey(const ValueKey('page-thumbnail-page-6')), findsOneWidget);
    await tester.tap(find.byTooltip('Page 6'));
    await tester.pumpAndSettle();

    await dismissEditorPages(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('6p'), findsOneWidget);
    expect(tester.getSize(notebookSpine).width, greaterThan(initialSpineWidth));

    await tester.tap(find.bySemanticsLabel('Open notebook Growing notes'));
    await tester.pumpAndSettle();
    await openEditorPages(tester);
    expect(find.byKey(const ValueKey('page-thumbnail-page-6')), findsOneWidget);
  });

  testWidgets('wraps bookshelf rows at iPad split-view width', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryNotebookRepository();
    for (var index = 1; index <= 10; index++) {
      await repository.createNotebook(title: 'Shelf book $index');
    }

    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('library-bookshelf')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-bookshelf-row-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('library-bookshelf-row-1')),
      findsOneWidget,
    );
    expect(find.text('Recent notebooks'), findsNothing);
  });

  testWidgets('draws a stroke and supports undo redo', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    final redoButton = find.widgetWithIcon(IconButton, Icons.redo);

    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
    expect(tester.widget<IconButton>(redoButton).onPressed, isNull);

    await drawVisibleStroke(tester);

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);

    await tester.tap(undoButton);
    await tester.pump();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
    expect(tester.widget<IconButton>(redoButton).onPressed, isNotNull);

    await tester.tap(redoButton);
    await tester.pump();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });

  testWidgets('zooms the page and still supports drawing', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    await tester.tap(find.byKey(const ValueKey('editor-zoom-chip')));
    await tester.pump();

    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Zoom and fit'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);

    final zoomOutButton = find.widgetWithIcon(IconButton, Icons.zoom_out);
    expect(tester.widget<IconButton>(zoomOutButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();

    expect(tester.widget<IconButton>(zoomOutButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Zoom and fit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fit width'));
    await tester.pump();

    await drawVisibleStroke(tester);

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });

  testWidgets('pinch zoom does not create a stroke', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    final center = visibleCanvasPoint(tester);
    final firstFinger = await tester.startGesture(
      center - const Offset(24, 0),
      pointer: 7,
    );
    final secondFinger = await tester.startGesture(
      center + const Offset(24, 0),
      pointer: 8,
    );

    await firstFinger.moveBy(const Offset(-24, 0));
    await secondFinger.moveBy(const Offset(24, 0));
    await tester.pump();
    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
  });

  testWidgets('switches editor tools and erases a stroke', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    await tester.pumpWidget(InkNestApp(notebookRepository: repository));
    await tester.pumpAndSettle();

    await createPagedNotebook(tester);

    expect(find.byTooltip('Pen'), findsOneWidget);
    expect(find.byTooltip('Highlighter'), findsOneWidget);
    expect(find.byTooltip('Eraser'), findsOneWidget);
    expect(find.byTooltip('Finger writes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-tool-properties')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('editor-finger-mode-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Writing assist'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    await tester.tap(find.text('Writing assist'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-finger-mode-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Writing assist'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    await tester.tapAt(const Offset(8, 180));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('editor-highlighter-tool')));
    await tester.pump();

    final start = visibleCanvasPoint(tester);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(48, 0));
    await gesture.up();
    await tester.pump();

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Eraser'));
    await tester.pump();

    final eraserGesture = await tester.startGesture(start);
    await eraserGesture.moveBy(const Offset(52, 0));
    await eraserGesture.up();
    await tester.pump();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
    expect(
      tester.widget<DrawingCanvas>(find.byType(DrawingCanvas)).page.strokes,
      isEmpty,
    );

    await tester.tap(undoButton);
    await tester.pump();
    expect(
      tester.widget<DrawingCanvas>(find.byType(DrawingCanvas)).page.strokes,
      hasLength(1),
    );

    final redoButton = find.widgetWithIcon(IconButton, Icons.redo);
    await tester.tap(redoButton);
    await tester.pump();
    expect(
      tester.widget<DrawingCanvas>(find.byType(DrawingCanvas)).page.strokes,
      isEmpty,
    );
  });

  testWidgets('finger pan mode ignores touch drawing but accepts stylus', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    await tester.tap(find.byKey(const ValueKey('editor-finger-mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finger moves'));
    await tester.pumpAndSettle();

    var start = visibleCanvasPoint(tester);
    final touchGesture = await tester.startGesture(start);
    await touchGesture.moveBy(const Offset(32, 24));
    await touchGesture.up();
    await tester.pump();

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);

    start = visibleCanvasPoint(tester);
    final stylusGesture = await tester.startGesture(
      start,
      kind: ui.PointerDeviceKind.stylus,
    );
    await stylusGesture.moveBy(const Offset(32, 24));
    await stylusGesture.up();
    await tester.pump();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });

  testWidgets('adds and switches notebook pages', (WidgetTester tester) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);

    await drawVisibleStroke(tester);

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);

    await addPageAfterCurrent(tester);

    await openEditorPages(tester);
    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-thumbnail-page-2')), findsOneWidget);
    expect(find.byTooltip('Page 1'), findsOneWidget);
    expect(find.byTooltip('Page 2'), findsOneWidget);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);

    await tester.tap(find.byTooltip('Page 1'));
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });

  testWidgets('bookmarks pages from the editor navigation panel', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    await tester.tap(find.byKey(const ValueKey('editor-bookmarks-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-bookmarks-panel')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('bookmarks-toggle-current-page')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.text('Page 1'), findsNWidgets(2));

    await tester.tap(find.text('Page 1').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('bookmarks-toggle-current-page')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No bookmarks'), findsOneWidget);
  });

  testWidgets('inserts blank pages before and after selected pages', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    await openEditorPages(tester);
    await tester.tap(find.byTooltip('Page 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert page after'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-template-blank')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-thumbnail-page-2')), findsOneWidget);

    await tester.tap(find.byTooltip('Page 2 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert page before'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-template-blank')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-thumbnail-page-3')), findsOneWidget);

    final page1Left = tester.getTopLeft(
      find.byKey(const ValueKey('page-thumbnail-page-1')),
    );
    final page2Left = tester.getTopLeft(
      find.byKey(const ValueKey('page-thumbnail-page-2')),
    );
    final page3Left = tester.getTopLeft(
      find.byKey(const ValueKey('page-thumbnail-page-3')),
    );

    expect(page1Left.dx, lessThan(page3Left.dx));
    expect(page3Left.dx, lessThan(page2Left.dx));
  });

  testWidgets('uses page thumbnail actions to duplicate delete and reorder', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await createPagedNotebook(tester);

    await openEditorPages(tester);
    await tester.tap(find.byTooltip('Page 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate page'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-thumbnail-page-2')), findsOneWidget);

    await tester.tap(find.byTooltip('Page 2 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move page left'));
    await tester.pumpAndSettle();

    final page1Left = tester.getTopLeft(
      find.byKey(const ValueKey('page-thumbnail-page-1')),
    );
    final page2Left = tester.getTopLeft(
      find.byKey(const ValueKey('page-thumbnail-page-2')),
    );
    expect(page2Left.dx, lessThan(page1Left.dx));

    await tester.tap(find.byTooltip('Page 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete page'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-thumbnail-page-2')), findsNothing);
  });
}

Stroke _testStroke({required String id, required List<Offset> offsets}) {
  return Stroke(
    id: id,
    tool: ToolType.pen,
    color: const Color(0xFF1E2526),
    width: 5,
    points: [
      for (final (index, offset) in offsets.indexed)
        StrokePoint(
          offset: offset,
          pressure: 1,
          time: DateTime.utc(2026, 7, 18, 0, 0, index),
        ),
    ],
  );
}

Future<int> _capturePixelAlpha(
  WidgetTester tester,
  GlobalKey boundaryKey,
  int x,
  int y,
) async {
  final alpha = await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = byteData!.buffer.asUint8List();
    final pixelAlpha = bytes[(y * image.width + x) * 4 + 3];
    image.dispose();
    return pixelAlpha;
  });
  return alpha!;
}
