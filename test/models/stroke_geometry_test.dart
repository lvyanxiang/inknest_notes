import 'dart:math' as math;
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
    'smooths finger jitter while preserving endpoints and point metadata',
    () {
      final points = [
        _point(0, 0, pressure: 0.4, millisecond: 0),
        _point(10, 2, pressure: 0.5, millisecond: 10),
        _point(20, -2, pressure: 0.6, millisecond: 20),
        _point(30, 2, pressure: 0.7, millisecond: 30),
        _point(40, 0, pressure: 0.8, millisecond: 40),
      ];

      final smoothed = StrokeGeometry.smoothFingerPoints(points);

      expect(smoothed, hasLength(points.length));
      expect(smoothed.first.offset, points.first.offset);
      expect(smoothed.last.offset, points.last.offset);
      expect(
        smoothed
            .skip(1)
            .take(3)
            .map((point) => point.offset.dy.abs())
            .reduce(math.max),
        lessThan(2),
      );
      expect(
        smoothed.map((point) => point.pressure),
        points.map((point) => point.pressure),
      );
      expect(
        smoothed.map((point) => point.time),
        points.map((point) => point.time),
      );
    },
  );

  test('keeps intentional sharp finger corners stable', () {
    final points = [_point(0, 0), _point(20, 0), _point(20, 20)];

    final smoothed = StrokeGeometry.smoothFingerPoints(points);

    expect((smoothed[1].offset - points[1].offset).distance, lessThan(1.5));
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

  test('serializes and preserves an audio recording link', () {
    final stroke = Stroke(
      id: 'stroke-audio',
      tool: ToolType.pen,
      color: const Color(0xFF1E2526),
      width: 5,
      points: [_point(0, 0), _point(10, 0)],
      audioRecordingId: 'audio-1',
    );

    final reloadedStroke = Stroke.fromJson(stroke.toJson());
    final splitStroke = reloadedStroke.copyWith(
      points: [reloadedStroke.points.first],
    );

    expect(reloadedStroke.audioRecordingId, 'audio-1');
    expect(splitStroke.audioRecordingId, 'audio-1');
  });
}

StrokePoint _point(
  double x,
  double y, {
  double pressure = 1,
  int millisecond = 0,
}) {
  return StrokePoint(
    offset: Offset(x, y),
    pressure: pressure,
    time: DateTime.utc(2026, 6, 14).add(Duration(milliseconds: millisecond)),
  );
}
