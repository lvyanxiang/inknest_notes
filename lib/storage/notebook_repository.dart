import 'dart:io';
import 'dart:ui';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook_audio_recording.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';

enum PageCoordinateSpaceWriteBlockReason {
  unresolvedLegacyContent,
  unsupportedVersion,
}

class PageCoordinateSpaceWriteException extends StateError {
  PageCoordinateSpaceWriteException.forPage(NotePage page)
    : pageId = page.id,
      coordinateSpaceVersion = page.persistedCoordinateSpaceVersion,
      reason =
          page.coordinateSpaceStatus == NotePageCoordinateSpaceStatus.legacy
          ? PageCoordinateSpaceWriteBlockReason.unresolvedLegacyContent
          : PageCoordinateSpaceWriteBlockReason.unsupportedVersion,
      super(_messageFor(page));

  final String pageId;
  final Object? coordinateSpaceVersion;
  final PageCoordinateSpaceWriteBlockReason reason;

  static String _messageFor(NotePage page) {
    if (page.coordinateSpaceStatus == NotePageCoordinateSpaceStatus.legacy) {
      return 'Page "${page.id}" uses unresolved legacy coordinate space v0 '
          'and contains coordinate-bearing content. Create a verified backup '
          'and convert the page before saving.';
    }

    return 'Page "${page.id}" has unsupported coordinateSpaceVersion '
        '${page.persistedCoordinateSpaceVersion}. Normal saves are blocked '
        'to prevent data loss.';
  }
}

NotePage preparePageForNormalSave(NotePage page) {
  final preparedPage = page.upgradeEmptyLegacyCoordinateSpace();
  if (!preparedPage.usesCanonicalCoordinateSpace) {
    throw PageCoordinateSpaceWriteException.forPage(preparedPage);
  }
  return preparedPage;
}

abstract class NotebookRepository {
  Future<List<Notebook>> listNotebooks({
    bool archived = false,
    String? folderId,
  });

  Future<List<NotebookFolder>> listFolders();

  Future<NotebookFolder> createFolder(String name);

  Future<NotebookFolder> renameFolder(NotebookFolder folder, String name);

  Future<NotebookFolder> applySyncedFolder(NotebookFolder folder);

  Future<void> applySyncedFolderDeletion(NotebookFolder folder);

  Future<void> deleteFolder(NotebookFolder folder);

  Future<Notebook> createNotebook({
    String? title,
    NotebookLayoutMode layoutMode = NotebookLayoutMode.paged,
  });

  Future<InfiniteCanvasDocument> loadInfiniteCanvas(Notebook notebook);

  Future<void> saveInfiniteCanvas(
    Notebook notebook,
    InfiniteCanvasDocument document,
  );

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

  Future<Notebook> applySyncedNotebookContent(Notebook notebook);

  Future<Notebook> applySyncedPageAddition(
    Notebook notebook,
    NotePage page, {
    int? position,
  });

  Future<Notebook> addPage(Notebook notebook);

  Future<Notebook> insertPage(Notebook notebook, int index);

  Future<Notebook> duplicatePage(Notebook notebook, String pageId);

  Future<Notebook> deletePage(Notebook notebook, String pageId);

  Future<Notebook> movePage(Notebook notebook, String pageId, int newIndex);

  Future<NotePage> rotatePageClockwise(Notebook notebook, String pageId);

  Future<NotePage> loadPage(Notebook notebook, String pageId);

  Future<void> savePage(Notebook notebook, NotePage page);
}
