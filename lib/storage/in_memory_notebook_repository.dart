import 'dart:io';

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
      pageIds: const ['page-1'],
    );

    _notebooks.add(notebook);
    _pages['${notebook.id}/page-1'] = const NotePage(
      id: 'page-1',
      width: _pageWidth,
      height: _pageHeight,
    );
    return notebook;
  }

  @override
  Future<Notebook> importPdf(File sourceFile) {
    return createNotebook(title: _titleFromFile(sourceFile));
  }

  @override
  Future<Notebook> addPage(Notebook notebook) async {
    final pageId = 'page-${notebook.pageIds.length + 1}';
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: [...notebook.pageIds, pageId],
    );
    final index = _notebooks.indexWhere(
      (existing) => existing.id == notebook.id,
    );
    if (index != -1) {
      _notebooks[index] = updatedNotebook;
    }
    _pages['${notebook.id}/$pageId'] = NotePage(
      id: pageId,
      width: _pageWidth,
      height: _pageHeight,
    );
    return updatedNotebook;
  }

  @override
  Future<NotePage> loadPage(Notebook notebook, String pageId) async {
    return _pages['${notebook.id}/$pageId'] ??
        NotePage(id: pageId, width: _pageWidth, height: _pageHeight);
  }

  @override
  Future<void> savePage(Notebook notebook, NotePage page) async {
    _pages['${notebook.id}/${page.id}'] = page;
  }

  String _titleFromFile(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? 'Imported PDF'
        : file.uri.pathSegments.last;
    return name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
  }
}
