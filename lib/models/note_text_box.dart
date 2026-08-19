import 'dart:ui';

import 'package:flutter/foundation.dart';

enum NoteTextBoxFont { system, liuJianMaoCao, longCang, zhiMangXing }

enum NoteTextBoxAlignment { left, center, right }

@immutable
class NoteTextBox {
  const NoteTextBox({
    required this.id,
    required this.position,
    this.text = '',
    this.width = 240,
    this.color = const Color(0xFF1E2526),
    this.fontSize = 24,
    this.font = NoteTextBoxFont.system,
    this.alignment = NoteTextBoxAlignment.left,
  });

  final String id;
  final Offset position;
  final String text;
  final double width;
  final Color color;
  final double fontSize;
  final NoteTextBoxFont font;
  final NoteTextBoxAlignment alignment;

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
      font: _fontFromJson(json),
      alignment: NoteTextBoxAlignment.values.firstWhere(
        (alignment) => alignment.name == json['alignment'],
        orElse: () => NoteTextBoxAlignment.left,
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
      'font': font.name,
      'alignment': alignment.name,
    };
  }

  NoteTextBox copyWith({
    Offset? position,
    String? text,
    double? width,
    Color? color,
    double? fontSize,
    NoteTextBoxFont? font,
    NoteTextBoxAlignment? alignment,
  }) {
    return NoteTextBox(
      id: id,
      position: position ?? this.position,
      text: text ?? this.text,
      width: width ?? this.width,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      font: font ?? this.font,
      alignment: alignment ?? this.alignment,
    );
  }

  static NoteTextBoxFont _fontFromJson(Map<String, Object?> json) {
    final fontName = json['font'] as String?;
    if (fontName != null) {
      return NoteTextBoxFont.values.firstWhere(
        (font) => font.name == fontName,
        orElse: () => NoteTextBoxFont.system,
      );
    }

    // Migrate the removed binary style toggle without preserving its system
    // font fallback, italic, or synthetic weight simulation.
    return json['style'] == 'handwriting'
        ? NoteTextBoxFont.liuJianMaoCao
        : NoteTextBoxFont.system;
  }
}
