import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
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
}

StrokePoint _point(double x, double y) {
  return StrokePoint(
    offset: Offset(x, y),
    pressure: 1,
    time: DateTime.utc(2026, 7, 18),
  );
}
