import 'dart:io';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class InMemoryNotebookRepository implements NotebookRepository {
  static const _pageWidth = 768.0;
  static const _pageHeight = 1024.0;

  final List<Notebook> _notebooks = [];
  final List<NotebookFolder> _folders = [];
  final Map<String, NotePage> _pages = {};
  int _nextNotebookNumber = 1;
  int _nextFolderNumber = 1;

  @override
  Future<List<Notebook>> listNotebooks({
    bool archived = false,
    String? folderId,
  }) async {
    return List.unmodifiable(
      _notebooks.where((notebook) {
        if (notebook.isArchived != archived) {
          return false;
        }
        if (archived) {
          return folderId == null || notebook.folderId == folderId;
        }

        return notebook.folderId == folderId;
      }),
    );
  }

  @override
  Future<List<NotebookFolder>> listFolders() async {
    return List.unmodifiable(_folders);
  }

  @override
  Future<NotebookFolder> createFolder(String name) async {
    final now = DateTime.now();
    final folder = NotebookFolder(
      id: 'folder-${now.microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Folder ${_nextFolderNumber++}' : name.trim(),
      createdAt: now,
      updatedAt: now,
    );

    _folders.add(folder);
    return folder;
  }

  @override
  Future<NotebookFolder> renameFolder(
    NotebookFolder folder,
    String name,
  ) async {
    final updatedFolder = folder.copyWith(
      name: name.trim().isEmpty ? folder.name : name.trim(),
      updatedAt: DateTime.now(),
    );
    _replaceFolder(updatedFolder);
    return updatedFolder;
  }

  @override
  Future<void> deleteFolder(NotebookFolder folder) async {
    _folders.removeWhere((existing) => existing.id == folder.id);
    for (final notebook in _notebooks.toList()) {
      if (notebook.folderId == folder.id) {
        _replaceNotebook(notebook.copyWith(folderId: null));
      }
    }
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
  Future<Notebook> renameNotebook(Notebook notebook, String title) async {
    final updatedNotebook = notebook.copyWith(
      title: title.trim().isEmpty ? notebook.title : title.trim(),
      updatedAt: DateTime.now(),
    );
    _replaceNotebook(updatedNotebook);
    return updatedNotebook;
  }

  @override
  Future<Notebook> duplicateNotebook(Notebook notebook) async {
    final now = DateTime.now();
    final duplicatedNotebook = Notebook(
      id: 'notebook-${now.microsecondsSinceEpoch}',
      title: '${notebook.title} Copy',
      createdAt: now,
      updatedAt: now,
      pageIds: notebook.pageIds,
      isArchived: false,
      folderId: notebook.isArchived ? null : notebook.folderId,
      pdfOutlines: notebook.pdfOutlines,
      bookmarkedPageIds: notebook.bookmarkedPageIds,
    );

    _notebooks.add(duplicatedNotebook);
    for (final pageId in notebook.pageIds) {
      final sourcePage = await loadPage(notebook, pageId);
      _pages[_pageKey(duplicatedNotebook, pageId)] = sourcePage;
    }

    return duplicatedNotebook;
  }

  @override
  Future<Notebook> setNotebookArchived(
    Notebook notebook,
    bool isArchived,
  ) async {
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      isArchived: isArchived,
    );
    _replaceNotebook(updatedNotebook);
    return updatedNotebook;
  }

  @override
  Future<void> deleteNotebook(Notebook notebook) async {
    _notebooks.removeWhere((existing) => existing.id == notebook.id);
    for (final pageId in notebook.pageIds) {
      _pages.remove(_pageKey(notebook, pageId));
    }
  }

  @override
  Future<Notebook> moveNotebookToFolder(
    Notebook notebook,
    String? folderId,
  ) async {
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      folderId: folderId,
    );
    _replaceNotebook(updatedNotebook);
    return updatedNotebook;
  }

  @override
  Future<Notebook> setPageBookmarked(
    Notebook notebook,
    String pageId,
    bool isBookmarked,
  ) async {
    final bookmarkedPageIds = [
      for (final bookmarkedPageId in notebook.bookmarkedPageIds)
        if (bookmarkedPageId != pageId) bookmarkedPageId,
      if (isBookmarked && notebook.pageIds.contains(pageId)) pageId,
    ];
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      bookmarkedPageIds: bookmarkedPageIds,
    );

    _replaceNotebook(updatedNotebook);
    return updatedNotebook;
  }

  @override
  Future<Notebook> addPage(Notebook notebook) async {
    final pageId = _nextPageId(notebook.pageIds);
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: [...notebook.pageIds, pageId],
    );
    _replaceNotebook(updatedNotebook);
    _pages[_pageKey(notebook, pageId)] = NotePage(
      id: pageId,
      width: _pageWidth,
      height: _pageHeight,
    );
    return updatedNotebook;
  }

  @override
  Future<Notebook> insertPage(Notebook notebook, int index) async {
    final pageId = _nextPageId(notebook.pageIds);
    final clampedIndex = index.clamp(0, notebook.pageIds.length).toInt();
    final referencePage = await _pageForInsertedBlank(notebook, clampedIndex);
    final updatedPageIds = notebook.pageIds.toList()
      ..insert(clampedIndex, pageId);
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: updatedPageIds,
    );

    _replaceNotebook(updatedNotebook);
    _pages[_pageKey(notebook, pageId)] = NotePage(
      id: pageId,
      width: referencePage.width,
      height: referencePage.height,
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
    _pages[_pageKey(notebook, newPageId)] = NotePage(
      id: newPageId,
      width: sourcePage.width,
      height: sourcePage.height,
      pdfBackground: sourcePage.pdfBackground,
      strokes: sourcePage.strokes,
      textBoxes: sourcePage.textBoxes,
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
      bookmarkedPageIds: [
        for (final bookmarkedPageId in notebook.bookmarkedPageIds)
          if (bookmarkedPageId != pageId) bookmarkedPageId,
      ],
    );

    _replaceNotebook(updatedNotebook);
    _pages.remove(_pageKey(notebook, pageId));
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
    return _pages[_pageKey(notebook, pageId)] ??
        NotePage(id: pageId, width: _pageWidth, height: _pageHeight);
  }

  @override
  Future<void> savePage(Notebook notebook, NotePage page) async {
    _pages[_pageKey(notebook, page.id)] = page;
  }

  void _replaceNotebook(Notebook notebook) {
    final index = _notebooks.indexWhere(
      (existing) => existing.id == notebook.id,
    );
    if (index != -1) {
      _notebooks[index] = notebook;
    }
  }

  void _replaceFolder(NotebookFolder folder) {
    final index = _folders.indexWhere((existing) => existing.id == folder.id);
    if (index != -1) {
      _folders[index] = folder;
    }
  }

  String _pageKey(Notebook notebook, String pageId) {
    return '${notebook.id}/$pageId';
  }

  Future<NotePage> _pageForInsertedBlank(Notebook notebook, int index) {
    if (notebook.pageIds.isEmpty) {
      return Future.value(
        const NotePage(
          id: 'blank-reference',
          width: _pageWidth,
          height: _pageHeight,
        ),
      );
    }

    final referenceIndex = index == 0 ? 0 : index - 1;
    return loadPage(notebook, notebook.pageIds[referenceIndex]);
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
