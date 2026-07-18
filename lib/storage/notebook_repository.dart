import 'dart:io';
import 'dart:ui';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_audio_recording.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';

abstract class NotebookRepository {
  Future<List<Notebook>> listNotebooks({
    bool archived = false,
    String? folderId,
  });

  Future<List<NotebookFolder>> listFolders();

  Future<NotebookFolder> createFolder(String name);

  Future<NotebookFolder> renameFolder(NotebookFolder folder, String name);

  Future<void> deleteFolder(NotebookFolder folder);

  Future<Notebook> createNotebook({String? title});

  Future<Notebook> importPdf(File sourceFile);

  Future<Notebook> importPdfsIntoNotebook(
    Notebook notebook,
    List<File> sourceFiles,
  );

  Future<NoteImage> importImage(
    Notebook notebook,
    File sourceFile, {
    required Offset position,
    required double width,
    required double height,
  });

  Future<Notebook> renameNotebook(Notebook notebook, String title);

  Future<Notebook> duplicateNotebook(Notebook notebook);

  Future<Notebook> setNotebookArchived(Notebook notebook, bool isArchived);

  Future<void> deleteNotebook(Notebook notebook);

  Future<Notebook> moveNotebookToFolder(Notebook notebook, String? folderId);

  Future<Notebook> setPageBookmarked(
    Notebook notebook,
    String pageId,
    bool isBookmarked,
  );

  Future<NotebookAudioRecording> prepareAudioRecording(
    Notebook notebook, {
    String? pageId,
  });

  Future<Notebook> saveAudioRecording(
    Notebook notebook,
    NotebookAudioRecording recording,
  );

  Future<Notebook> addPage(Notebook notebook);

  Future<Notebook> insertPage(Notebook notebook, int index);

  Future<Notebook> duplicatePage(Notebook notebook, String pageId);

  Future<Notebook> deletePage(Notebook notebook, String pageId);

  Future<Notebook> movePage(Notebook notebook, String pageId, int newIndex);

  Future<NotePage> rotatePageClockwise(Notebook notebook, String pageId);

  Future<NotePage> loadPage(Notebook notebook, String pageId);

  Future<void> savePage(Notebook notebook, NotePage page);
}
