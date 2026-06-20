import 'package:flutter/painting.dart';
import 'package:inknest_notes/models/note_text_box.dart';

const _handwritingFontFallback = [
  'Snell Roundhand',
  'Bradley Hand',
  'Noteworthy',
  'Chalkboard SE',
  'Savoye LET',
];

TextStyle noteTextBoxTextStyle(NoteTextBox textBox) {
  final isHandwriting = textBox.style == NoteTextBoxStyle.handwriting;

  return TextStyle(
    color: textBox.color,
    fontSize: textBox.fontSize,
    fontFamily: isHandwriting ? _handwritingFontFallback.first : null,
    fontFamilyFallback: isHandwriting
        ? _handwritingFontFallback.skip(1).toList()
        : null,
    fontStyle: isHandwriting ? FontStyle.italic : FontStyle.normal,
    fontWeight: isHandwriting ? FontWeight.w500 : FontWeight.w400,
    height: isHandwriting ? 1.15 : 1.2,
  );
}
