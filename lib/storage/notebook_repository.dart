import 'dart:io';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page.dart';

abstract class NotebookRepository {
  Future<List<Notebook>> listNotebooks({bool archived = false});

  Future<Notebook> createNotebook({String? title});

  Future<Notebook> importPdf(File sourceFile);

  Future<Notebook> renameNotebook(Notebook notebook, String title);

  Future<Notebook> duplicateNotebook(Notebook notebook);

  Future<Notebook> setNotebookArchived(Notebook notebook, bool isArchived);

  Future<void> deleteNotebook(Notebook notebook);

  Future<Notebook> addPage(Notebook notebook);

  Future<Notebook> duplicatePage(Notebook notebook, String pageId);

  Future<Notebook> deletePage(Notebook notebook, String pageId);

  Future<Notebook> movePage(Notebook notebook, String pageId, int newIndex);

  Future<NotePage> loadPage(Notebook notebook, String pageId);

  Future<void> savePage(Notebook notebook, NotePage page);
}
