import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_geometry.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_selection_layer.dart';
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

  test('hit-tests the nearest stroke for tap selection', () {
    final near = _stroke(
      id: 'near',
      offsets: const [Offset(20, 20), Offset(40, 20)],
    );
    final far = _stroke(
      id: 'far',
      offsets: const [Offset(200, 200), Offset(220, 200)],
    );

    expect(
      LassoGeometry.hitTestNearestStroke([near, far], const Offset(30, 22)),
      'near',
    );
    expect(
      LassoGeometry.hitTestNearestStroke([near, far], const Offset(120, 120)),
      isNull,
    );
  });

  test('tap selects a connected handwriting block without the next line', () {
    final firstCharacterLeft = _stroke(
      id: 'first-left',
      offsets: const [Offset(20, 20), Offset(20, 52)],
    );
    final firstCharacterRight = _stroke(
      id: 'first-right',
      offsets: const [Offset(34, 20), Offset(34, 52)],
    );
    final nextCharacter = _stroke(
      id: 'next-character',
      offsets: const [Offset(58, 20), Offset(76, 52)],
    );
    final separatedWord = _stroke(
      id: 'separated-word',
      offsets: const [Offset(160, 20), Offset(180, 52)],
    );
    final nextLine = _stroke(
      id: 'next-line',
      offsets: const [Offset(20, 92), Offset(76, 92)],
    );

    final selectedIds = LassoGeometry.selectConnectedStrokeIdsForTap([
      firstCharacterLeft,
      firstCharacterRight,
      nextCharacter,
      separatedWord,
      nextLine,
    ], const Offset(22, 30));

    expect(selectedIds, {'first-left', 'first-right', 'next-character'});
  });

  test('tap away from handwriting selects nothing', () {
    final stroke = _stroke(
      id: 'ink',
      offsets: const [Offset(20, 20), Offset(40, 40)],
    );

    expect(
      LassoGeometry.selectConnectedStrokeIdsForTap([
        stroke,
      ], const Offset(200, 200)),
      isEmpty,
    );
  });

  testWidgets('a true tap selects the connected handwriting block', (
    tester,
  ) async {
    final first = _stroke(
      id: 'first',
      offsets: const [Offset(20, 20), Offset(20, 52)],
    );
    final adjacent = _stroke(
      id: 'adjacent',
      offsets: const [Offset(44, 20), Offset(62, 52)],
    );
    final distant = _stroke(
      id: 'distant',
      offsets: const [Offset(180, 20), Offset(200, 52)],
    );
    Set<String>? selectedIds;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 200,
            child: Stack(
              children: [
                LassoSelectionLayer(
                  pageStrokes: [first, adjacent, distant],
                  selectedStrokes: const [],
                  onSelectionComplete: (_) {},
                  onTapSelectionComplete: (ids) => selectedIds = ids,
                  onStrokesPreviewChanged: (_) {},
                  onStrokesChanged: (_) {},
                  onClearSelection: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final layerOrigin = tester.getTopLeft(
      find.byKey(const ValueKey('lasso-drawing-region')),
    );
    await tester.tapAt(layerOrigin + const Offset(22, 30));
    await tester.pump();

    expect(selectedIds, {'first', 'adjacent'});
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
