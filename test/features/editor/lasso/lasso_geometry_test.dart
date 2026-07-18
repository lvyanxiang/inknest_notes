import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_geometry.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  test('selects enclosed strokes and strokes crossing the lasso edge', () {
    final enclosed = _stroke(
      id: 'enclosed',
      offsets: const [Offset(20, 20), Offset(30, 30)],
    );
    final crossing = _stroke(
      id: 'crossing',
      offsets: const [Offset(0, 50), Offset(100, 50)],
    );
    final outside = _stroke(
      id: 'outside',
      offsets: const [Offset(120, 120), Offset(140, 140)],
    );

    final selectedIds = LassoGeometry.selectStrokeIds(
      [enclosed, crossing, outside],
      const [Offset(10, 10), Offset(60, 10), Offset(60, 60), Offset(10, 60)],
    );

    expect(selectedIds, {'enclosed', 'crossing'});
  });

  test('translates and scales points while preserving stroke metadata', () {
    final stroke = _stroke(
      id: 'stroke-1',
      offsets: const [Offset(10, 20), Offset(30, 40)],
      width: 5,
      audioRecordingId: 'audio-1',
    );

    final translated = LassoGeometry.translateStrokes([
      stroke,
    ], const Offset(8, -4)).single;
    final scaled = LassoGeometry.scaleStrokes(
      [translated],
      anchor: const Offset(18, 16),
      scale: 2,
    ).single;

    expect(translated.points.first.offset, const Offset(18, 16));
    expect(translated.points.last.offset, const Offset(38, 36));
    expect(scaled.points.first.offset, const Offset(18, 16));
    expect(scaled.points.last.offset, const Offset(58, 56));
    expect(scaled.width, 10);
    expect(scaled.id, stroke.id);
    expect(scaled.tool, stroke.tool);
    expect(scaled.color, stroke.color);
    expect(scaled.audioRecordingId, 'audio-1');
    expect(scaled.points.first.time, stroke.points.first.time);
    expect(scaled.points.first.pressure, stroke.points.first.pressure);
  });

  test('stroke copyWith supports recoloring without changing geometry', () {
    final stroke = _stroke(
      id: 'stroke-1',
      offsets: const [Offset(10, 20), Offset(30, 40)],
    );

    final recolored = stroke.copyWith(color: const Color(0xFFC24B3A));

    expect(recolored.color, const Color(0xFFC24B3A));
    expect(recolored.points, same(stroke.points));
  });
}

Stroke _stroke({
  required String id,
  required List<Offset> offsets,
  double width = 4,
  String? audioRecordingId,
}) {
  return Stroke(
    id: id,
    tool: ToolType.pen,
    color: const Color(0xFF1E2526),
    width: width,
    audioRecordingId: audioRecordingId,
    points: [
      for (final (index, offset) in offsets.indexed)
        StrokePoint(
          offset: offset,
          pressure: 0.8,
          time: DateTime.utc(2026, 7, 18, 0, 0, index),
        ),
    ],
  );
}
