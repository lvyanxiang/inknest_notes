import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ToolType { pen, highlighter, eraser, text }

@immutable
class DrawingTool {
  const DrawingTool({
    this.type = ToolType.pen,
    this.color = const Color(0xFF1E2526),
    this.width = 4,
  });

  final ToolType type;
  final Color color;
  final double width;

  DrawingTool copyWith({ToolType? type, Color? color, double? width}) {
    return DrawingTool(
      type: type ?? this.type,
      color: color ?? this.color,
      width: width ?? this.width,
    );
  }
}
