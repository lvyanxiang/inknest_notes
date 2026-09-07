import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/note_shape.dart';

enum ToolType { pen, highlighter, eraser, text, lasso, shape }

enum ShapeCreationMode { preset, auto }

@immutable
class DrawingTool {
  const DrawingTool({
    this.type = ToolType.pen,
    this.color = const Color(0xFF1E2526),
    this.width = 4,
    this.shapeType = NoteShapeType.line,
    this.shapeCreationMode = ShapeCreationMode.preset,
    this.drawAndHoldShapeEnabled = true,
  });

  final ToolType type;
  final Color color;
  final double width;
  final NoteShapeType shapeType;
  final ShapeCreationMode shapeCreationMode;
  final bool drawAndHoldShapeEnabled;

  DrawingTool copyWith({
    ToolType? type,
    Color? color,
    double? width,
    NoteShapeType? shapeType,
    ShapeCreationMode? shapeCreationMode,
    bool? drawAndHoldShapeEnabled,
  }) {
    return DrawingTool(
      type: type ?? this.type,
      color: color ?? this.color,
      width: width ?? this.width,
      shapeType: shapeType ?? this.shapeType,
      shapeCreationMode: shapeCreationMode ?? this.shapeCreationMode,
      drawAndHoldShapeEnabled:
          drawAndHoldShapeEnabled ?? this.drawAndHoldShapeEnabled,
    );
  }
}
