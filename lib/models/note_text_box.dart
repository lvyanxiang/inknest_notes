import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
class NoteTextBox {
  const NoteTextBox({
    required this.id,
    required this.position,
    this.text = 'Text',
    this.width = 240,
    this.color = const Color(0xFF1E2526),
    this.fontSize = 24,
  });

  final String id;
  final Offset position;
  final String text;
  final double width;
  final Color color;
  final double fontSize;

  factory NoteTextBox.fromJson(Map<String, Object?> json) {
    return NoteTextBox(
      id: json['id']! as String,
      position: Offset(
        (json['x']! as num).toDouble(),
        (json['y']! as num).toDouble(),
      ),
      text: json['text']! as String,
      width: (json['width']! as num).toDouble(),
      color: Color(json['color']! as int),
      fontSize: (json['fontSize']! as num).toDouble(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'x': position.dx,
      'y': position.dy,
      'text': text,
      'width': width,
      'color': color.toARGB32(),
      'fontSize': fontSize,
    };
  }

  NoteTextBox copyWith({
    Offset? position,
    String? text,
    double? width,
    Color? color,
    double? fontSize,
  }) {
    return NoteTextBox(
      id: id,
      position: position ?? this.position,
      text: text ?? this.text,
      width: width ?? this.width,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}
