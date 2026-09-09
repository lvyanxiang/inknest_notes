import 'dart:ui';

const defaultNotePageWidth = 595.2755905511812;
const defaultNotePageHeight = 841.8897637795277;
const defaultNotePageSize = Size(defaultNotePageWidth, defaultNotePageHeight);

enum NotePageOrientation {
  portrait('Portrait'),
  landscape('Landscape');

  const NotePageOrientation(this.label);

  final String label;
}

enum NotePageSizePreset {
  a4(label: 'A4', detail: '210 × 297 mm', portraitSize: defaultNotePageSize),
  letter(label: 'Letter', detail: '8.5 × 11 in', portraitSize: Size(612, 792)),
  digital(
    label: 'Digital 3:4',
    detail: '768 × 1024',
    portraitSize: Size(768, 1024),
  );

  const NotePageSizePreset({
    required this.label,
    required this.detail,
    required this.portraitSize,
  });

  final String label;
  final String detail;
  final Size portraitSize;

  Size sizeFor(NotePageOrientation orientation) {
    return orientation == NotePageOrientation.portrait
        ? portraitSize
        : Size(portraitSize.height, portraitSize.width);
  }
}
