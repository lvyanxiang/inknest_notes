import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  test('builds smoothed quadratic segments for multi-point strokes', () {
    final segments = StrokeGeometry.buildSmoothSegments(const [
      Offset(0, 0),
      Offset(10, 10),
      Offset(20, 0),
    ]);

    expect(segments, hasLength(2));
    expect(segments.first.control, const Offset(10, 10));
    expect(segments.first.end, const Offset(15, 5));
    expect(segments.last.control, isNull);
    expect(segments.last.end, const Offset(20, 0));
  });

  test(
    'partial erasing splits a stroke instead of deleting the whole stroke',
    () {
      final stroke = Stroke(
        id: 'stroke-1',
        tool: ToolType.pen,
        color: const Color(0xFF1E2526),
        width: 5,
        points: [
          _point(0, 0),
          _point(10, 0),
          _point(20, 0),
          _point(30, 0),
          _point(40, 0),
        ],
      );

      final updatedStrokes = StrokeGeometry.eraseStrokes(
        strokes: [stroke],
        eraserPoints: [_point(20, 0)],
        radius: 4,
      );

      expect(updatedStrokes, hasLength(2));
      expect(updatedStrokes.first.points.map((point) => point.offset), [
        const Offset(0, 0),
        const Offset(10, 0),
      ]);
      expect(updatedStrokes.last.points.map((point) => point.offset), [
        const Offset(30, 0),
        const Offset(40, 0),
      ]);
    },
  );

  test('returns original stroke list when eraser misses', () {
    final stroke = Stroke(
      id: 'stroke-1',
      tool: ToolType.pen,
      color: const Color(0xFF1E2526),
      width: 5,
      points: [_point(0, 0), _point(10, 0)],
    );
    final strokes = [stroke];

    final updatedStrokes = StrokeGeometry.eraseStrokes(
      strokes: strokes,
      eraserPoints: [_point(100, 100)],
      radius: 4,
    );

    expect(identical(updatedStrokes, strokes), isTrue);
  });
}

StrokePoint _point(double x, double y) {
  return StrokePoint(
    offset: Offset(x, y),
    pressure: 1,
    time: DateTime.utc(2026, 6, 14),
  );
}
