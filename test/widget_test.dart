import 'dart:async';
import 'dart:ui' show PointerDeviceKind, Rect, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';
import 'package:inknest_notes/features/editor/audio/notebook_audio_player.dart';
import 'package:inknest_notes/features/editor/audio/notebook_audio_recorder.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/features/editor/pdf_search/notebook_pdf_search_panel.dart';
import 'package:inknest_notes/features/editor/pdf_search/notebook_pdf_text_searcher.dart';
import 'package:inknest_notes/features/editor/pdf_search/pdf_text_search_highlight.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';

void main() {
  Future<void> pumpInkNestApp(WidgetTester tester) async {
    await tester.pumpWidget(
      InkNestApp(notebookRepository: InMemoryNotebookRepository()),
    );
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    expect(find.text('Notebook 1'), findsOneWidget);
    expect(find.byTooltip('Export PDF'), findsOneWidget);
    expect(find.byTooltip('Shape'), findsOneWidget);
    expect(find.byTooltip('Shape type'), findsOneWidget);
    expect(find.byTooltip('Favorite black pen'), findsOneWidget);
    expect(find.byTooltip('Favorite yellow highlighter'), findsOneWidget);
    expect(find.byTooltip('Insert image'), findsOneWidget);
    expect(find.byTooltip('Audio recordings'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsOneWidget);
    expect(find.text('No notebooks yet'), findsNothing);
  });

  testWidgets('records pauses resumes and saves notebook audio', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'Lecture');
    final audioPlayer = _FakeNotebookAudioPlayer();
    final audioRecorder = _FakeNotebookAudioRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(
          notebook: notebook,
          notebookRepository: repository,
          audioPlayer: audioPlayer,
          audioRecorder: audioRecorder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Audio recordings'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No recordings yet. Record a lecture, meeting, or voice note without leaving the notebook.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Start recording'));
    await tester.pumpAndSettle();

    expect(audioRecorder.startedPath, isNotNull);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.byTooltip('Pause recording'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause recording'));
    await tester.pumpAndSettle();
    expect(audioRecorder.pauseCount, 1);
    expect(find.text('Recording paused'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume recording'));
    await tester.pumpAndSettle();
    expect(audioRecorder.resumeCount, 1);
    expect(find.text('Recording'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop recording'));
    await tester.pumpAndSettle();

    final savedNotebook = (await repository.listNotebooks()).single;
    expect(audioRecorder.stopCount, 1);
    expect(savedNotebook.audioRecordings, hasLength(1));
    expect(savedNotebook.audioRecordings.single.title, 'Recording 1');

    await tester.tap(find.byTooltip('Audio recordings'));
    await tester.pumpAndSettle();
    expect(find.text('Recording 1'), findsOneWidget);

    await tester.tap(find.text('Recording 1'));
    await tester.pumpAndSettle();

    expect(
      audioPlayer.playedPath,
      savedNotebook.audioRecordings.single.filePath,
    );
    expect(find.byKey(const ValueKey('audio-playback-banner')), findsOneWidget);
    expect(find.text('0 linked strokes on this page'), findsOneWidget);

    audioPlayer.durationController.add(const Duration(seconds: 10));
    audioPlayer.positionController.add(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('00:02 / 00:10'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause playback'));
    await tester.pumpAndSettle();
    expect(audioPlayer.pauseCount, 1);
  });

  testWidgets('adds edits persists and deletes editor text boxes', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Text'));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(DrawingCanvas)));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Typed note');
    await tester.pumpAndSettle();

    expect(find.text('Typed note'), findsOneWidget);
    expect(find.byTooltip('Handwriting style'), findsOneWidget);

    await tester.tap(find.byTooltip('Handwriting style'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Plain text'), findsOneWidget);

    await tester.tap(find.byTooltip('Add page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Page 1'));
    await tester.pumpAndSettle();

    expect(find.text('Typed note'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete text box'));
    await tester.pumpAndSettle();

    expect(find.text('Typed note'), findsNothing);
  });

  testWidgets('beautifies selected handwriting with Smart Ink', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    final canvas = find.byType(DrawingCanvas);
    final center = tester.getCenter(canvas);
    final strokeGesture = await tester.startGesture(
      center - const Offset(32, 8),
    );
    await strokeGesture.moveBy(const Offset(64, 16));
    await strokeGesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Smart Ink'));
    await tester.pumpAndSettle();

    final selectionGesture = await tester.startGesture(
      center - const Offset(96, 64),
    );
    await selectionGesture.moveBy(const Offset(192, 128));
    await selectionGesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Smart Ink'), findsOneWidget);
    expect(find.text('Selected 1 strokes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Neat note');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Beautify'));
    await tester.pumpAndSettle();

    expect(find.text('Neat note'), findsOneWidget);
    expect(find.byTooltip('Plain text'), findsOneWidget);
  });

  testWidgets('shows export options and validates page ranges', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add page'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Range'), findsOneWidget);
    expect(find.text('All 2 pages'), findsOneWidget);

    await tester.tap(find.text('Range'));
    await tester.pumpAndSettle();

    expect(find.text('Pages 1-2'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).last, '9');
    await tester.pumpAndSettle();

    expect(find.text('Pages must be between 1 and 2.'), findsOneWidget);
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

  testWidgets('manages notebooks from the library card menu', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notebook 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename notebook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Project Notes');
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

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Class Notes');
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

  testWidgets('searches sorts and previews recent notebooks', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New notebook'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Recent notebooks'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('notebook-thumbnail-card-');
      }),
      findsNWidgets(2),
    );

    await tester.tap(find.byTooltip('Search notebooks'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');
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

  testWidgets('draws a stroke and supports undo redo', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    final redoButton = find.widgetWithIcon(IconButton, Icons.redo);

    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
    expect(tester.widget<IconButton>(redoButton).onPressed, isNull);

    final canvas = find.byType(DrawingCanvas);
    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(32, 24));
    await gesture.up();
    await tester.pump();

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

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Reset zoom'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);

    final zoomOutButton = find.widgetWithIcon(IconButton, Icons.zoom_out);
    expect(tester.widget<IconButton>(zoomOutButton).onPressed, isNull);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();

    expect(tester.widget<IconButton>(zoomOutButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();

    final canvas = find.byType(DrawingCanvas);
    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(32, 24));
    await gesture.up();
    await tester.pump();

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });

  testWidgets('pinch zoom does not create a stroke', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    final canvas = find.byType(DrawingCanvas);
    final center = tester.getCenter(canvas);
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
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pen'), findsOneWidget);
    expect(find.byTooltip('Highlighter'), findsOneWidget);
    expect(find.byTooltip('Eraser'), findsOneWidget);
    expect(find.byTooltip('Finger pan'), findsOneWidget);
    expect(find.byTooltip('Width 3'), findsOneWidget);
    expect(find.byTooltip('Width 5'), findsOneWidget);
    expect(find.byTooltip('Width 8'), findsOneWidget);

    await tester.tap(find.byTooltip('Highlighter'));
    await tester.pump();
    await tester.tap(find.byTooltip('Width 8'));
    await tester.pump();

    final canvas = find.byType(DrawingCanvas);
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump();

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Eraser'));
    await tester.pump();

    final eraserGesture = await tester.startGesture(center);
    await eraserGesture.moveBy(const Offset(8, 0));
    await eraserGesture.up();
    await tester.pump();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
  });

  testWidgets('finger pan mode ignores touch drawing but accepts stylus', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Finger pan'));
    await tester.pump();

    final canvas = find.byType(DrawingCanvas);
    var center = tester.getCenter(canvas);
    final touchGesture = await tester.startGesture(center);
    await touchGesture.moveBy(const Offset(32, 24));
    await touchGesture.up();
    await tester.pump();

    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);

    center = tester.getCenter(canvas);
    final stylusGesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await stylusGesture.moveBy(const Offset(32, 24));
    await stylusGesture.up();
    await tester.pump();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });

  testWidgets('adds and switches notebook pages', (WidgetTester tester) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    final canvas = find.byType(DrawingCanvas);
    final undoButton = find.widgetWithIcon(IconButton, Icons.undo);

    final gesture = await tester.startGesture(tester.getCenter(canvas));
    await gesture.moveBy(const Offset(32, 24));
    await gesture.up();
    await tester.pump();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Add page'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Bookmark page'), findsOneWidget);

    await tester.tap(find.byTooltip('Bookmark page'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Outline and bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);

    await tester.tap(find.text('Page 1'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsNothing);

    await tester.tap(find.byTooltip('Remove bookmark'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Bookmark page'), findsOneWidget);
  });

  testWidgets('searches PDF text and highlights a selected result', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotebookRepository();
    final notebook = await repository.createNotebook(title: 'PDF Study');
    const pages = [
      NotePage(
        id: 'page-1',
        width: 595,
        height: 842,
        pdfBackground: PdfBackground(
          assetPath: 'assets/searchable.pdf',
          pageNumber: 1,
        ),
      ),
    ];
    final textSearcher = _FakeNotebookPdfTextSearcher(
      const PdfTextSearchResult(
        pageId: 'page-1',
        pdfPageNumber: 1,
        matchText: 'important',
        snippet: 'An important result appears here.',
        normalizedBounds: Rect.fromLTWH(0.2, 0.3, 0.25, 0.04),
        pdfPageSize: Size(595, 842),
      ),
    );
    PdfTextSearchResult? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: NotebookPdfSearchPanel(
                      notebook: notebook,
                      pages: pages,
                      textSearcher: textSearcher,
                      onSelectResult: (result) {
                        setState(() {
                          selectedResult = result;
                        });
                      },
                    ),
                  ),
                  if (selectedResult case final result?)
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: PdfTextSearchHighlight(
                        result: result,
                        color: Colors.orange,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('pdf-search-field')),
      'important',
    );
    await tester.tap(find.byTooltip('Search PDF text'));
    await tester.pumpAndSettle();

    expect(textSearcher.lastQuery, 'important');
    expect(find.text('1 match'), findsOneWidget);
    expect(find.text('An important result appears here.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-search-result-0')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfTextSearchHighlight), findsOneWidget);
  });

  testWidgets('inserts blank pages before and after selected pages', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Page 1 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert page after'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-thumbnail-page-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-thumbnail-page-2')), findsOneWidget);

    await tester.tap(find.byTooltip('Page 2 actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert page before'));
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

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

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

class _FakeNotebookAudioRecorder implements NotebookAudioRecorder {
  String? startedPath;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {
    pauseCount += 1;
  }

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  @override
  Future<void> resume() async {
    resumeCount += 1;
  }

  @override
  Future<void> start(String path) async {
    startedPath = path;
  }

  @override
  Future<String?> stop() async {
    stopCount += 1;
    return startedPath;
  }
}

class _FakeNotebookAudioPlayer implements NotebookAudioPlayer {
  final StreamController<void> completionController =
      StreamController<void>.broadcast();
  final StreamController<Duration> durationController =
      StreamController<Duration>.broadcast();
  final StreamController<bool> playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> positionController =
      StreamController<Duration>.broadcast();

  String? playedPath;
  int pauseCount = 0;

  @override
  Stream<void> get completions => completionController.stream;

  @override
  Stream<Duration> get durationChanges => durationController.stream;

  @override
  Stream<bool> get playingChanges => playingController.stream;

  @override
  Stream<Duration> get positionChanges => positionController.stream;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {
    pauseCount += 1;
  }

  @override
  Future<void> playFile(String path) async {
    playedPath = path;
  }

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}
}

class _FakeNotebookPdfTextSearcher implements NotebookPdfTextSearcher {
  _FakeNotebookPdfTextSearcher(this.result);

  final PdfTextSearchResult result;
  String? lastQuery;

  @override
  Future<void> dispose() async {}

  @override
  Future<List<PdfTextSearchResult>> search({
    required Iterable<NotePage> pages,
    required String query,
  }) async {
    lastQuery = query;
    return [result];
  }
}
