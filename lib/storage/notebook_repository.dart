import 'package:inknest_notes/models/notebook.dart';

abstract class NotebookRepository {
  List<Notebook> listNotebooks();

  Notebook createNotebook({String? title});
}
