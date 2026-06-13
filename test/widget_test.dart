import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/app/app.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';

void main() {
  testWidgets('shows the notebook library shell', (WidgetTester tester) async {
    await tester.pumpWidget(const InkNestApp());

    expect(find.text('InkNest Notes'), findsOneWidget);
    expect(find.text('No notebooks yet'), findsOneWidget);
    expect(find.text('New notebook'), findsWidgets);
  });

  testWidgets('creates and opens a notebook', (WidgetTester tester) async {
    await tester.pumpWidget(const InkNestApp());

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();

    expect(find.text('Notebook 1'), findsOneWidget);
    expect(find.text('No notebooks yet'), findsNothing);
  });

  testWidgets('draws a stroke and supports undo redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const InkNestApp());

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
}
