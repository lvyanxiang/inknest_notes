import 'dart:ui';

import 'package:flutter/foundation.dart';

enum NoteShapeType { line, arrow, rectangle, ellipse }

@immutable
class NoteShape {
  const NoteShape({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    this.color = const Color(0xFF1E2526),
    this.width = 4,
  });

  final String id;
  final NoteShapeType type;
  final Offset start;
  final Offset end;
  final Color color;
  final double width;

  Rect get bounds => Rect.fromPoints(start, end);

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
    };
  }

  NoteShape copyWith({
    NoteShapeType? type,
    Offset? start,
    Offset? end,
    Color? color,
    double? width,
  }) {
    return NoteShape(
      id: id,
      type: type ?? this.type,
      start: start ?? this.start,
      end: end ?? this.end,
      color: color ?? this.color,
      width: width ?? this.width,
    );
  }
}
