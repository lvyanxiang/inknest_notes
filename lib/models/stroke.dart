import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

@immutable
class Stroke {
  const Stroke({
    required this.id,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  final String id;
  final ToolType tool;
  final Color color;
  final double width;
  final List<StrokePoint> points;

  bool get isHighlighter => tool == ToolType.highlighter;

  factory Stroke.fromJson(Map<String, Object?> json) {
    return Stroke(
      id: json['id']! as String,
      tool: ToolType.values.byName(json['tool']! as String),
      color: Color(json['color']! as int),
      width: (json['width']! as num).toDouble(),
      points: (json['points']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(StrokePoint.fromJson)
          .toList(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'tool': tool.name,
      'color': color.toARGB32(),
      'width': width,
      'points': points.map((point) => point.toJson()).toList(),
    };
  }

  Stroke copyWith({List<StrokePoint>? points}) {
    return Stroke(
      id: id,
      tool: tool,
      color: color,
      width: width,
      points: points ?? this.points,
    );
  }
}
