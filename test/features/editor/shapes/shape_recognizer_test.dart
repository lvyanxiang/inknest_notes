import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/shapes/shape_recognizer.dart';
import 'package:inknest_notes/models/note_shape.dart';

void main() {
  const color = Color(0xFF1E2526);

  test('recognizes a mostly straight freehand line', () {
    final shape = recognizeHandDrawnShape(
      points: const [
        Offset(10, 10),
        Offset(30, 12),
        Offset(55, 9),
        Offset(80, 11),
      ],
      id: 'line',
      color: color,
      width: 3,
    );

    expect(shape?.type, NoteShapeType.line);
  });

  test('recognizes a closed rectangle', () {
    final shape = recognizeHandDrawnShape(
      points: _closed([
        const Offset(10, 10),
        const Offset(110, 12),
        const Offset(108, 80),
        const Offset(12, 78),
      ]),
      id: 'rectangle',
      color: color,
      width: 3,
    );

    expect(shape?.type, NoteShapeType.rectangle);
  });

  test('recognizes a closed triangle', () {
    final shape = recognizeHandDrawnShape(
      points: _closed([
        const Offset(60, 10),
        const Offset(110, 90),
        const Offset(10, 90),
      ]),
      id: 'triangle',
      color: color,
      width: 3,
    );

    expect(shape?.type, NoteShapeType.triangle);
  });

  test('recognizes a closed ellipse', () {
    final shape = recognizeHandDrawnShape(
      points: [
        for (var index = 0; index <= 32; index++)
          Offset(
            60 + 50 * math.cos(index * math.pi * 2 / 32),
            50 + 30 * math.sin(index * math.pi * 2 / 32),
          ),
      ],
      id: 'ellipse',
      color: color,
      width: 3,
    );

    expect(shape?.type, NoteShapeType.ellipse);
  });

  test('recognizes a one-stroke arrow', () {
    final shape = recognizeHandDrawnShape(
      points: const [
        Offset(10, 50),
        Offset(100, 50),
        Offset(78, 34),
        Offset(100, 50),
        Offset(78, 66),
      ],
      id: 'arrow',
      color: color,
      width: 3,
    );

    expect(shape?.type, NoteShapeType.arrow);
  });

  test('recognizes a diamond', () {
    final shape = recognizeHandDrawnShape(
      points: _closed([
        const Offset(60, 10),
        const Offset(110, 50),
        const Offset(60, 90),
        const Offset(10, 50),
      ]),
      id: 'diamond',
      color: color,
      width: 3,
    );

    expect(shape?.type, NoteShapeType.diamond);
  });

  test('recognizes and preserves polygon vertices', () {
    final vertices = [
      for (var index = 0; index < 5; index++)
        Offset(
          60 + 50 * math.cos(-math.pi / 2 + math.pi * 2 * index / 5),
          60 + 50 * math.sin(-math.pi / 2 + math.pi * 2 * index / 5),
        ),
    ];
    final shape = recognizeHandDrawnShape(
      points: _closed(vertices),
      id: 'polygon',
      color: color,
      width: 3,
    );

    expect(shape?.type, NoteShapeType.polygon);
    expect(shape?.vertices, hasLength(5));

    final restored = NoteShape.fromJson(shape!.toJson());
    expect(restored.type, NoteShapeType.polygon);
    expect(restored.vertices, hasLength(5));
    expect(restored.bounds, shape.bounds);
  });

  test('returns null for an inconclusive open curve', () {
    final shape = recognizeHandDrawnShape(
      points: const [
        Offset(10, 10),
        Offset(30, 30),
        Offset(55, 12),
        Offset(75, 35),
      ],
      id: 'curve',
      color: color,
      width: 3,
    );

    expect(shape, isNull);
  });
}

List<Offset> _closed(List<Offset> points) => [...points, points.first];
