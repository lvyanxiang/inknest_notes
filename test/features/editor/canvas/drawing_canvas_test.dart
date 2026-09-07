import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  test('Finger Writing Assist changes only touch strokes when enabled', () {
    final stroke = Stroke(
      id: 'stroke-1',
      tool: ToolType.pen,
      color: const Color(0xFF1E2526),
      width: 5,
      points: [
        _point(0, 0),
        _point(10, 2),
        _point(20, -2),
        _point(30, 2),
        _point(40, 0),
      ],
    );

    final touchStroke = applyFingerWritingAssist(
      stroke: stroke,
      pointerKind: PointerDeviceKind.touch,
      enabled: true,
    );
    final stylusStroke = applyFingerWritingAssist(
      stroke: stroke,
      pointerKind: PointerDeviceKind.stylus,
      enabled: true,
    );
    final disabledTouchStroke = applyFingerWritingAssist(
      stroke: stroke,
      pointerKind: PointerDeviceKind.touch,
      enabled: false,
    );

    expect(identical(touchStroke, stroke), isFalse);
    expect(touchStroke.points[1].offset, isNot(stroke.points[1].offset));
    expect(identical(stylusStroke, stroke), isTrue);
    expect(identical(disabledTouchStroke, stroke), isTrue);
  });

  testWidgets('quick Pen gesture remains ink', (tester) async {
    Stroke? completedStroke;
    NoteShape? completedShape;
    await _pumpCanvas(
      tester,
      onStrokeComplete: (stroke) => completedStroke = stroke,
      onShapeComplete: (shape) => completedShape = shape,
    );

    final origin = tester.getTopLeft(find.byType(DrawingCanvas));
    final gesture = await tester.startGesture(
      origin + const Offset(30, 80),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(origin + const Offset(230, 82));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(completedStroke, isNotNull);
    expect(completedShape, isNull);
  });

  testWidgets('holding a Pen line previews and commits a clean shape', (
    tester,
  ) async {
    Stroke? completedStroke;
    NoteShape? completedShape;
    await _pumpCanvas(
      tester,
      onStrokeComplete: (stroke) => completedStroke = stroke,
      onShapeComplete: (shape) => completedShape = shape,
    );

    final origin = tester.getTopLeft(find.byType(DrawingCanvas));
    final gesture = await tester.startGesture(
      origin + const Offset(30, 80),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(origin + const Offset(230, 82));
    await tester.pump(const Duration(milliseconds: 520));
    await gesture.moveTo(origin + const Offset(250, 82));
    await gesture.up();
    await tester.pump();

    expect(completedStroke, isNull);
    expect(completedShape?.type, NoteShapeType.line);
    expect(completedShape!.end.dx, closeTo(250, 1));
  });

  testWidgets('disabling Draw and hold keeps a held line as ink', (
    tester,
  ) async {
    Stroke? completedStroke;
    NoteShape? completedShape;
    await _pumpCanvas(
      tester,
      tool: const DrawingTool(
        type: ToolType.pen,
        width: 3,
        drawAndHoldShapeEnabled: false,
      ),
      onStrokeComplete: (stroke) => completedStroke = stroke,
      onShapeComplete: (shape) => completedShape = shape,
    );

    final origin = tester.getTopLeft(find.byType(DrawingCanvas));
    final gesture = await tester.startGesture(
      origin + const Offset(30, 80),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(origin + const Offset(230, 82));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(completedStroke, isNotNull);
    expect(completedShape, isNull);
  });
}

Future<void> _pumpCanvas(
  WidgetTester tester, {
  DrawingTool tool = const DrawingTool(type: ToolType.pen, width: 3),
  required ValueChanged<Stroke> onStrokeComplete,
  required ValueChanged<NoteShape> onShapeComplete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: DrawingCanvas(
              page: const NotePage(id: 'page', width: 300, height: 300),
              tool: tool,
              fingerPanEnabled: false,
              fingerWritingAssistEnabled: true,
              onStrokeComplete: onStrokeComplete,
              onShapeComplete: onShapeComplete,
              onErase: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

StrokePoint _point(double x, double y) {
  return StrokePoint(
    offset: Offset(x, y),
    pressure: 1,
    time: DateTime.utc(2026, 7, 18),
  );
}
