import 'dart:io';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page.dart';

abstract class NotebookRepository {
  Future<List<Notebook>> listNotebooks();

  Future<Notebook> createNotebook({String? title});

  Future<Notebook> importPdf(File sourceFile);

  Future<Notebook> addPage(Notebook notebook);

  Future<NotePage> loadPage(Notebook notebook, String pageId);

  Future<void> savePage(Notebook notebook, NotePage page);
}
