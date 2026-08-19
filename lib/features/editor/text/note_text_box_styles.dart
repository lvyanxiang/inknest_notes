import 'package:flutter/painting.dart';
import 'package:inknest_notes/features/editor/text/handwriting_font_presets.dart';
import 'package:inknest_notes/models/note_text_box.dart';

const noteTextBoxFontChoices = NoteTextBoxFont.values;

String noteTextBoxFontLabel(NoteTextBoxFont font) {
  return switch (font) {
    NoteTextBoxFont.system => 'Default',
    _ => noteTextBoxHandwritingFont(font)!.label,
  };
}

String? noteTextBoxFontFamily(NoteTextBoxFont font) {
  return noteTextBoxHandwritingFont(font)?.fontFamily;
}

HandwritingFontPreset? noteTextBoxHandwritingFont(NoteTextBoxFont font) {
  return switch (font) {
    NoteTextBoxFont.system => null,
    NoteTextBoxFont.liuJianMaoCao => HandwritingFontPresets.liuJianMaoCao,
    NoteTextBoxFont.longCang => HandwritingFontPresets.longCang,
    NoteTextBoxFont.zhiMangXing => HandwritingFontPresets.zhiMangXing,
  };
}

TextStyle noteTextBoxTextStyle(NoteTextBox textBox) {
  return TextStyle(
    color: textBox.color,
    fontSize: textBox.fontSize,
    fontFamily: noteTextBoxFontFamily(textBox.font),
    height: 1.2,
  );
}
