import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class InMemoryNotebookRepository implements NotebookRepository {
  static const _pageWidth = 768.0;
  static const _pageHeight = 1024.0;

  final List<Notebook> _notebooks = [];
  final Map<String, NotePage> _pages = {};
  int _nextNotebookNumber = 1;

  @override
  Future<List<Notebook>> listNotebooks() async {
    return List.unmodifiable(_notebooks);
  }

  @override
  Future<Notebook> createNotebook({String? title}) async {
    final now = DateTime.now();
    final notebook = Notebook(
      id: 'notebook-${now.microsecondsSinceEpoch}',
      title: title ?? 'Notebook ${_nextNotebookNumber++}',
      createdAt: now,
      updatedAt: now,
    );

    _notebooks.add(notebook);
    _pages[notebook.id] = const NotePage(
      id: 'page-1',
      width: _pageWidth,
      height: _pageHeight,
    );
    return notebook;
  }

  @override
  Future<NotePage> loadPage(Notebook notebook) async {
    return _pages[notebook.id] ??
        const NotePage(id: 'page-1', width: _pageWidth, height: _pageHeight);
  }

  @override
  Future<void> savePage(Notebook notebook, NotePage page) async {
    _pages[notebook.id] = page;
  }
}
