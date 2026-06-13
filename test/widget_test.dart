import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
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
    expect(find.text('No notebooks yet'), findsNothing);
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

  testWidgets('switches editor tools and erases a stroke', (
    WidgetTester tester,
  ) async {
    await pumpInkNestApp(tester);

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pen'), findsOneWidget);
    expect(find.byTooltip('Highlighter'), findsOneWidget);
    expect(find.byTooltip('Eraser'), findsOneWidget);
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

    expect(find.byTooltip('Page 1'), findsOneWidget);
    expect(find.byTooltip('Page 2'), findsOneWidget);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);

    await tester.tap(find.byTooltip('Page 1'));
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
  });
}
