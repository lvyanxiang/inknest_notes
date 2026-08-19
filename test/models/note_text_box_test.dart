import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/text/note_text_box_styles.dart';
import 'package:inknest_notes/models/note_text_box.dart';

void main() {
  test('persists an explicit bundled text-box font', () {
    const textBox = NoteTextBox(
      id: 'text-1',
      position: Offset(12, 24),
      text: '真实字体',
      font: NoteTextBoxFont.zhiMangXing,
      alignment: NoteTextBoxAlignment.center,
    );

    final reloaded = NoteTextBox.fromJson(textBox.toJson());

    expect(reloaded.font, NoteTextBoxFont.zhiMangXing);
    expect(reloaded.alignment, NoteTextBoxAlignment.center);
    expect(noteTextBoxTextStyle(reloaded).fontFamily, 'ZhiMangXing');
    expect(noteTextBoxTextStyle(reloaded).fontFamilyFallback, isNull);
    expect(noteTextBoxTextStyle(reloaded).fontStyle, isNull);
    expect(noteTextBoxTextStyle(reloaded).fontWeight, isNull);
  });

  test('migrates legacy simulated handwriting to a bundled font', () {
    final textBox = NoteTextBox.fromJson({
      'id': 'legacy-text',
      'x': 10,
      'y': 20,
      'text': 'Legacy',
      'width': 240,
      'color': const Color(0xFF1E2526).toARGB32(),
      'fontSize': 24,
      'style': 'handwriting',
    });

    expect(textBox.font, NoteTextBoxFont.liuJianMaoCao);
    expect(textBox.alignment, NoteTextBoxAlignment.left);
    expect(noteTextBoxTextStyle(textBox).fontFamily, 'LiuJianMaoCao');
  });

  test('keeps legacy regular text as the platform default font', () {
    final textBox = NoteTextBox.fromJson({
      'id': 'legacy-text',
      'x': 10,
      'y': 20,
      'text': 'Legacy',
      'width': 240,
      'color': const Color(0xFF1E2526).toARGB32(),
      'fontSize': 24,
      'style': 'regular',
    });

    expect(textBox.font, NoteTextBoxFont.system);
    expect(noteTextBoxTextStyle(textBox).fontFamily, isNull);
  });
}
