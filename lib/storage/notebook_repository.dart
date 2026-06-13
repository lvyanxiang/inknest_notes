import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page.dart';

abstract class NotebookRepository {
  Future<List<Notebook>> listNotebooks();

  Future<Notebook> createNotebook({String? title});

  Future<NotePage> loadPage(Notebook notebook);

  Future<void> savePage(Notebook notebook, NotePage page);
}
