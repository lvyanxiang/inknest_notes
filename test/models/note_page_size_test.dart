import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page_size.dart';

void main() {
  test('uses exact standard portrait dimensions', () {
    expect(NotePageSizePreset.a4.portraitSize, defaultNotePageSize);
    expect(NotePageSizePreset.letter.portraitSize, const Size(612, 792));
    expect(NotePageSizePreset.digital.portraitSize, const Size(768, 1024));
  });

  test('landscape swaps width and height without rotating content', () {
    expect(
      NotePageSizePreset.a4.sizeFor(NotePageOrientation.landscape),
      const Size(defaultNotePageHeight, defaultNotePageWidth),
    );
  });
}
