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
