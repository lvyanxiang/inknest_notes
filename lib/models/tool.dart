import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/note_shape.dart';

enum ToolType { pen, highlighter, eraser, text, smartInk, shape }

@immutable
class DrawingTool {
  const DrawingTool({
    this.type = ToolType.pen,
    this.color = const Color(0xFF1E2526),
    this.width = 4,
    this.shapeType = NoteShapeType.line,
  });

  final ToolType type;
  final Color color;
  final double width;
  final NoteShapeType shapeType;

  DrawingTool copyWith({
    ToolType? type,
    Color? color,
    double? width,
    NoteShapeType? shapeType,
  }) {
    return DrawingTool(
      type: type ?? this.type,
      color: color ?? this.color,
      width: width ?? this.width,
      shapeType: shapeType ?? this.shapeType,
    );
  }
}
