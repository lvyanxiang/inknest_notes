import 'dart:ui';

import 'package:flutter/foundation.dart';

enum NoteTextBoxStyle { regular, handwriting }

@immutable
class NoteTextBox {
  const NoteTextBox({
    required this.id,
    required this.position,
    this.text = 'Text',
    this.width = 240,
    this.color = const Color(0xFF1E2526),
    this.fontSize = 24,
    this.style = NoteTextBoxStyle.regular,
  });

  final String id;
  final Offset position;
  final String text;
  final double width;
  final Color color;
  final double fontSize;
  final NoteTextBoxStyle style;

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
      style: NoteTextBoxStyle.values.byName(
        json['style'] as String? ?? NoteTextBoxStyle.regular.name,
      ),
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
      'style': style.name,
    };
  }

  NoteTextBox copyWith({
    Offset? position,
    String? text,
    double? width,
    Color? color,
    double? fontSize,
    NoteTextBoxStyle? style,
  }) {
    return NoteTextBox(
      id: id,
      position: position ?? this.position,
      text: text ?? this.text,
      width: width ?? this.width,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      style: style ?? this.style,
    );
  }
}
