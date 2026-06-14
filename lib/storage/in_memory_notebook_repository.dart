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
    final pageId = _nextPageId(notebook.pageIds);
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: [...notebook.pageIds, pageId],
    );
    _replaceNotebook(updatedNotebook);
    _pages['${notebook.id}/$pageId'] = NotePage(
      id: pageId,
      width: _pageWidth,
      height: _pageHeight,
    );
    return updatedNotebook;
  }

  @override
  Future<Notebook> duplicatePage(Notebook notebook, String pageId) async {
    final sourceIndex = notebook.pageIds.indexOf(pageId);
    if (sourceIndex == -1) {
      return notebook;
    }

    final sourcePage = await loadPage(notebook, pageId);
    final newPageId = _nextPageId(notebook.pageIds);
    final updatedPageIds = notebook.pageIds.toList()
      ..insert(sourceIndex + 1, newPageId);
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: updatedPageIds,
    );

    _replaceNotebook(updatedNotebook);
    _pages['${notebook.id}/$newPageId'] = NotePage(
      id: newPageId,
      width: sourcePage.width,
      height: sourcePage.height,
      pdfBackground: sourcePage.pdfBackground,
      strokes: sourcePage.strokes,
    );

    return updatedNotebook;
  }

  @override
  Future<Notebook> deletePage(Notebook notebook, String pageId) async {
    if (notebook.pageIds.length <= 1 || !notebook.pageIds.contains(pageId)) {
      return notebook;
    }

    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: [
        for (final existingPageId in notebook.pageIds)
          if (existingPageId != pageId) existingPageId,
      ],
    );

    _replaceNotebook(updatedNotebook);
    _pages.remove('${notebook.id}/$pageId');
    return updatedNotebook;
  }

  @override
  Future<Notebook> movePage(
    Notebook notebook,
    String pageId,
    int newIndex,
  ) async {
    final currentIndex = notebook.pageIds.indexOf(pageId);
    if (currentIndex == -1) {
      return notebook;
    }

    final clampedIndex = newIndex.clamp(0, notebook.pageIds.length - 1).toInt();
    if (currentIndex == clampedIndex) {
      return notebook;
    }

    final updatedPageIds = notebook.pageIds.toList()
      ..removeAt(currentIndex)
      ..insert(clampedIndex, pageId);
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: updatedPageIds,
    );

    _replaceNotebook(updatedNotebook);
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

  void _replaceNotebook(Notebook notebook) {
    final index = _notebooks.indexWhere(
      (existing) => existing.id == notebook.id,
    );
    if (index != -1) {
      _notebooks[index] = notebook;
    }
  }

  String _nextPageId(List<String> pageIds) {
    var maxPageNumber = 0;
    for (final pageId in pageIds) {
      final pageNumber = int.tryParse(pageId.replaceFirst('page-', ''));
      if (pageNumber != null && pageNumber > maxPageNumber) {
        maxPageNumber = pageNumber;
      }
    }

    return 'page-${maxPageNumber + 1}';
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
