import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_audio_recording.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/pdf_outline_entry.dart';

void main() {
  test('serializes PDF outlines and page bookmarks', () {
    final notebook = Notebook(
      id: 'notebook-1',
      title: 'PDF Study',
      createdAt: DateTime.utc(2026, 6, 20),
      updatedAt: DateTime.utc(2026, 6, 20, 1),
      pageIds: const ['page-1', 'page-2'],
      pdfOutlines: const [
        PdfOutlineEntry(
          title: 'Chapter 1',
          pageId: 'page-1',
          children: [PdfOutlineEntry(title: 'Section 1.1', pageId: 'page-2')],
        ),
      ],
      bookmarkedPageIds: const ['page-2'],
      audioRecordings: [
        NoteAudioRecording(
          id: 'audio-1',
          title: 'Lecture',
          assetPath: 'assets/audio/audio-1.m4a',
          createdAt: DateTime.utc(2026, 6, 20, 2),
          durationMilliseconds: 65000,
        ),
      ],
    );

    final reloadedNotebook = Notebook.fromJson(notebook.toJson());

    expect(reloadedNotebook.pdfOutlines.single.title, 'Chapter 1');
    expect(reloadedNotebook.pdfOutlines.single.pageId, 'page-1');
    expect(
      reloadedNotebook.pdfOutlines.single.children.single.title,
      'Section 1.1',
    );
    expect(reloadedNotebook.bookmarkedPageIds, ['page-2']);
    expect(reloadedNotebook.audioRecordings.single.title, 'Lecture');
    expect(
      reloadedNotebook.audioRecordings.single.assetPath,
      'assets/audio/audio-1.m4a',
    );
    expect(
      reloadedNotebook.audioRecordings.single.duration,
      const Duration(minutes: 1, seconds: 5),
    );
  });
}
