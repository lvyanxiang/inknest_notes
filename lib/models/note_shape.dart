import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum NoteShapeType {
  line,
  arrow,
  rectangle,
  ellipse,
  triangle,
  diamond,
  polygon,
}

@immutable
class NoteShape {
  const NoteShape({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    this.color = const Color(0xFF1E2526),
    this.width = 4,
    this.vertices = const [],
  });

  final String id;
  final NoteShapeType type;
  final Offset start;
  final Offset end;
  final Color color;
  final double width;
  final List<Offset> vertices;

  Rect get bounds {
    if (vertices.isEmpty) {
      return Rect.fromPoints(start, end);
    }
    var result = Rect.fromCircle(center: vertices.first, radius: 0);
    for (final vertex in vertices.skip(1)) {
      result = result.expandToInclude(
        Rect.fromCircle(center: vertex, radius: 0),
      );
    }
    return result;
  }

  factory NoteShape.fromJson(Map<String, Object?> json) {
    return NoteShape(
      id: json['id']! as String,
      type: NoteShapeType.values.byName(json['type']! as String),
      start: Offset(
        (json['startX']! as num).toDouble(),
        (json['startY']! as num).toDouble(),
      ),
      end: Offset(
        (json['endX']! as num).toDouble(),
        (json['endY']! as num).toDouble(),
      ),
      color: Color(json['color']! as int),
      width: (json['width']! as num).toDouble(),
      vertices: ((json['vertices'] as List<Object?>?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(
            (vertex) => Offset(
              (vertex['x']! as num).toDouble(),
              (vertex['y']! as num).toDouble(),
            ),
          )
          .toList(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'startX': start.dx,
      'startY': start.dy,
      'endX': end.dx,
      'endY': end.dy,
      'color': color.toARGB32(),
      'width': width,
      if (vertices.isNotEmpty)
        'vertices': [
          for (final vertex in vertices) {'x': vertex.dx, 'y': vertex.dy},
        ],
    };
  }

  NoteShape copyWith({
    NoteShapeType? type,
    Offset? start,
    Offset? end,
    Color? color,
    double? width,
    List<Offset>? vertices,
  }) {
    return NoteShape(
      id: id,
      type: type ?? this.type,
      start: start ?? this.start,
      end: end ?? this.end,
      color: color ?? this.color,
      width: width ?? this.width,
      vertices: vertices ?? this.vertices,
    );
  }
}

/// Returns whether [point] touches a shape's painted bounds.
///
/// Object erasing treats a touched shape as atomic: the shape is removed in
/// one operation instead of being split into invalid partial geometry.
bool noteShapeHitTest(NoteShape shape, Offset point, {double tolerance = 0}) {
  final radius = math.max(0, tolerance) + shape.width / 2;
  switch (shape.type) {
    case NoteShapeType.line:
    case NoteShapeType.arrow:
      return _distanceToSegment(point, shape.start, shape.end) <= radius;
    case NoteShapeType.rectangle:
    case NoteShapeType.ellipse:
    case NoteShapeType.triangle:
    case NoteShapeType.diamond:
    case NoteShapeType.polygon:
      return shape.bounds.inflate(radius).contains(point);
  }
}

double _distanceToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared == 0) {
    return (point - start).distance;
  }

  final t =
      ((point.dx - start.dx) * segment.dx +
          (point.dy - start.dy) * segment.dy) /
      lengthSquared;
  final clampedT = t.clamp(0.0, 1.0).toDouble();
  final projection = Offset(
    start.dx + segment.dx * clampedT,
    start.dy + segment.dy * clampedT,
  );
  return (point - projection).distance;
}
