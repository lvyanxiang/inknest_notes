import 'dart:convert';
import 'dart:io';

import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:pdfrx/pdfrx.dart';

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
  Future<Notebook> importPdf(File sourceFile) async {
    final notebooks = await _readIndex();
    final now = DateTime.now();
    final pdfDocument = await PdfDocument.openFile(sourceFile.path);
    final pageCount = pdfDocument.pages.length;
    await pdfDocument.dispose();

    final notebook = Notebook(
      id: 'notebook-${now.microsecondsSinceEpoch}',
      title: _titleFromFile(sourceFile),
      createdAt: now,
      updatedAt: now,
      pageIds: [
        for (var index = 0; index < pageCount; index++) 'page-${index + 1}',
      ],
    );

    final assetFile = _pdfAssetFile(notebook);
    await assetFile.parent.create(recursive: true);
    await sourceFile.copy(assetFile.path);

    await _writeIndex([...notebooks, notebook]);
    for (var index = 0; index < pageCount; index++) {
      final pageId = notebook.pageIds[index];
      await savePage(
        notebook,
        NotePage(
          id: pageId,
          width: _pageWidth,
          height: _pageHeight,
          pdfBackground: PdfBackground(
            assetPath: 'assets/imported.pdf',
            pageNumber: index + 1,
            resolvedFilePath: assetFile.path,
          ),
        ),
      );
    }

    return notebook;
  }

  @override
  Future<Notebook> addPage(Notebook notebook) async {
    final pageId = _nextPageId(notebook.pageIds);
    final updatedNotebook = notebook.copyWith(
      updatedAt: DateTime.now(),
      pageIds: [...notebook.pageIds, pageId],
    );

    await _replaceNotebook(updatedNotebook);
    await savePage(updatedNotebook, _emptyPage(pageId));
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
    final duplicatedPage = NotePage(
      id: newPageId,
      width: sourcePage.width,
      height: sourcePage.height,
      pdfBackground: sourcePage.pdfBackground,
      strokes: sourcePage.strokes,
    );

    await _replaceNotebook(updatedNotebook);
    await savePage(updatedNotebook, duplicatedPage);
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

    await _replaceNotebook(updatedNotebook);
    final pageFile = _pageFile(notebook, pageId);
    if (await pageFile.exists()) {
      await pageFile.delete();
    }
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

    await _replaceNotebook(updatedNotebook);
    return updatedNotebook;
  }

  @override
  Future<NotePage> loadPage(Notebook notebook, String pageId) async {
    final pageFile = _pageFile(notebook, pageId);
    if (!await pageFile.exists()) {
      return _emptyPage(pageId);
    }

    final json = jsonDecode(await pageFile.readAsString());
    final page = NotePage.fromJson(json as Map<String, Object?>);
    return _resolvePageAssets(notebook, page);
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

  Future<void> _replaceNotebook(Notebook notebook) async {
    final notebooks = await _readIndex();
    await _writeIndex([
      for (final existingNotebook in notebooks)
        if (existingNotebook.id == notebook.id) notebook else existingNotebook,
    ]);
  }

  File _pageFile(Notebook notebook, String pageId) {
    return File(
      '${_notebooksDirectory.path}/${notebook.id}/pages/$pageId.json',
    );
  }

  File _pdfAssetFile(Notebook notebook) {
    return File(
      '${_notebooksDirectory.path}/${notebook.id}/assets/imported.pdf',
    );
  }

  NotePage _resolvePageAssets(Notebook notebook, NotePage page) {
    final background = page.pdfBackground;
    if (background == null) {
      return page;
    }

    final normalizedAssetPath = _normalizePdfAssetPath(background.assetPath);
    return page.copyWith(
      pdfBackground: background.copyWith(
        assetPath: normalizedAssetPath,
        resolvedFilePath: _resolvePdfAssetPath(notebook, background.assetPath),
      ),
    );
  }

  String _normalizePdfAssetPath(String assetPath) {
    if (File(assetPath).isAbsolute) {
      return 'assets/imported.pdf';
    }

    return assetPath;
  }

  String _resolvePdfAssetPath(Notebook notebook, String assetPath) {
    final absoluteFile = File(assetPath);
    if (absoluteFile.isAbsolute && absoluteFile.existsSync()) {
      return absoluteFile.path;
    }

    final normalizedAssetPath = _normalizePdfAssetPath(assetPath);
    return File(
      '${_notebooksDirectory.path}/${notebook.id}/$normalizedAssetPath',
    ).path;
  }

  NotePage _emptyPage(String pageId) {
    return NotePage(id: pageId, width: _pageWidth, height: _pageHeight);
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
