import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class InMemoryNotebookRepository implements NotebookRepository {
  final List<Notebook> _notebooks = [];
  int _nextNotebookNumber = 1;

  @override
  List<Notebook> listNotebooks() {
    return List.unmodifiable(_notebooks);
  }

  @override
  Notebook createNotebook({String? title}) {
    final now = DateTime.now();
    final notebook = Notebook(
      id: 'notebook-${now.microsecondsSinceEpoch}',
      title: title ?? 'Notebook ${_nextNotebookNumber++}',
      createdAt: now,
      updatedAt: now,
    );

    _notebooks.add(notebook);
    return notebook;
  }
}
