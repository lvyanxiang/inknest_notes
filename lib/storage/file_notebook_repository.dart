import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class FileNotebookRepository implements NotebookRepository {
  FileNotebookRepository({required Directory rootDirectory})
    : _notebooksDirectory = Directory('${rootDirectory.path}/notebooks');

  static const _pageWidth = 768.0;
  static const _pageHeight = 1024.0;

  final Directory _notebooksDirectory;

  File get _indexFile => File('${_notebooksDirectory.path}/index.json');

  @override
  Future<List<Notebook>> listNotebooks() async {
    return _readIndex();
  }

  @override
  Future<Notebook> createNotebook({String? title}) async {
    final notebooks = await _readIndex();
    final now = DateTime.now();
    final notebook = Notebook(
      id: 'notebook-${now.microsecondsSinceEpoch}',
      title: title ?? 'Notebook ${notebooks.length + 1}',
      createdAt: now,
      updatedAt: now,
      pageIds: const ['page-1'],
    );

    await _writeIndex([...notebooks, notebook]);
    await savePage(notebook, _emptyPage('page-1'));
    return notebook;
  }

  @override
  Future<Notebook> addPage(Notebook notebook) async {
    final pageId = 'page-${notebook.pageIds.length + 1}';
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: [...notebook.pageIds, pageId],
    );

    final notebooks = await _readIndex();
    await _writeIndex([
      for (final existingNotebook in notebooks)
        if (existingNotebook.id == notebook.id)
          updatedNotebook
        else
          existingNotebook,
    ]);
    await savePage(updatedNotebook, _emptyPage(pageId));
    return updatedNotebook;
  }

  @override
  Future<NotePage> loadPage(Notebook notebook, String pageId) async {
    final pageFile = _pageFile(notebook, pageId);
    if (!await pageFile.exists()) {
      return _emptyPage(pageId);
    }

    final json = jsonDecode(await pageFile.readAsString());
    return NotePage.fromJson(json as Map<String, Object?>);
  }

  @override
  Future<void> savePage(Notebook notebook, NotePage page) async {
    final pageFile = _pageFile(notebook, page.id);
    await pageFile.parent.create(recursive: true);
    await pageFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(page.toJson()),
    );

    final notebooks = await _readIndex();
    final updatedNotebook = notebook.copyWith(updatedAt: DateTime.now());
    await _writeIndex([
      for (final existingNotebook in notebooks)
        if (existingNotebook.id == notebook.id)
          updatedNotebook
        else
          existingNotebook,
    ]);
  }

  Future<List<Notebook>> _readIndex() async {
    if (!await _indexFile.exists()) {
      return [];
    }

    final json = jsonDecode(await _indexFile.readAsString());
    return (json as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(Notebook.fromJson)
        .toList();
  }

  Future<void> _writeIndex(List<Notebook> notebooks) async {
    await _notebooksDirectory.create(recursive: true);
    await _indexFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(notebooks.map((notebook) => notebook.toJson()).toList()),
    );
  }

  File _pageFile(Notebook notebook, String pageId) {
    return File(
      '${_notebooksDirectory.path}/${notebook.id}/pages/$pageId.json',
    );
  }

  NotePage _emptyPage(String pageId) {
    return NotePage(id: pageId, width: _pageWidth, height: _pageHeight);
  }
}
