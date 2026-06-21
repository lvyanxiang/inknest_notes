import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/pdf_outline_entry.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:pdfrx/pdfrx.dart';

class FileNotebookRepository implements NotebookRepository {
  FileNotebookRepository({required Directory rootDirectory})
    : _notebooksDirectory = Directory('${rootDirectory.path}/notebooks');

  static const _pageWidth = 768.0;
  static const _pageHeight = 1024.0;

  final Directory _notebooksDirectory;
  Future<void> _storageWriteQueue = Future.value();
  int _temporaryFileCounter = 0;

  File get _indexFile => File('${_notebooksDirectory.path}/index.json');
  File get _foldersFile => File('${_notebooksDirectory.path}/folders.json');

  @override
  Future<List<Notebook>> listNotebooks({
    bool archived = false,
    String? folderId,
  }) async {
    final notebooks = await _readIndex();
    return notebooks.where((notebook) {
      if (notebook.isArchived != archived) {
        return false;
      }
      if (archived) {
        return folderId == null || notebook.folderId == folderId;
      }

      return notebook.folderId == folderId;
    }).toList();
  }

  @override
  Future<List<NotebookFolder>> listFolders() {
    return _readFolders();
  }

  @override
  Future<NotebookFolder> createFolder(String name) async {
    final folders = await _readFolders();
    final now = DateTime.now();
    final folder = NotebookFolder(
      id: 'folder-${now.microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Folder ${folders.length + 1}' : name.trim(),
      createdAt: now,
      updatedAt: now,
    );

    await _writeFolders([...folders, folder]);
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
    final folders = await _readFolders();
    await _writeFolders([
      for (final existingFolder in folders)
        if (existingFolder.id == folder.id) updatedFolder else existingFolder,
    ]);
    return updatedFolder;
  }

  @override
  Future<void> deleteFolder(NotebookFolder folder) async {
    final folders = await _readFolders();
    await _writeFolders([
      for (final existingFolder in folders)
        if (existingFolder.id != folder.id) existingFolder,
    ]);

    final notebooks = await _readIndex();
    await _writeIndex([
      for (final notebook in notebooks)
        if (notebook.folderId == folder.id)
          notebook.copyWith(folderId: null, updatedAt: DateTime.now())
        else
          notebook,
    ]);
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
    final pageIds = [
      for (var index = 0; index < pageCount; index++) 'page-${index + 1}',
    ];
    final pdfOutlines = await _loadPdfOutlineEntries(pdfDocument, pageIds);
    await pdfDocument.dispose();

    final notebook = Notebook(
      id: 'notebook-${now.microsecondsSinceEpoch}',
      title: _titleFromFile(sourceFile),
      createdAt: now,
      updatedAt: now,
      pageIds: pageIds,
      pdfOutlines: pdfOutlines,
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
  Future<NoteImage> importImage(
    Notebook notebook,
    File sourceFile, {
    required Offset position,
    required double width,
    required double height,
  }) async {
    final now = DateTime.now();
    final assetPath = _imageAssetPath(sourceFile, now);
    final assetFile = File('${_notebookDirectory(notebook).path}/$assetPath');

    await assetFile.parent.create(recursive: true);
    await sourceFile.copy(assetFile.path);

    return NoteImage(
      id: 'image-${now.microsecondsSinceEpoch}',
      position: position,
      width: width,
      height: height,
      assetPath: assetPath,
      resolvedFilePath: assetFile.path,
    );
  }

  @override
  Future<Notebook> renameNotebook(Notebook notebook, String title) async {
    final updatedNotebook = notebook.copyWith(
      title: title.trim().isEmpty ? notebook.title : title.trim(),
      updatedAt: DateTime.now(),
    );

    await _replaceNotebook(updatedNotebook);
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
      folderId: notebook.isArchived ? null : notebook.folderId,
      pdfOutlines: notebook.pdfOutlines,
      bookmarkedPageIds: notebook.bookmarkedPageIds,
    );
    final sourceDirectory = _notebookDirectory(notebook);
    final destinationDirectory = _notebookDirectory(duplicatedNotebook);

    if (await sourceDirectory.exists()) {
      await _copyDirectory(sourceDirectory, destinationDirectory);
    } else {
      await destinationDirectory.create(recursive: true);
      for (final pageId in notebook.pageIds) {
        final page = await loadPage(notebook, pageId);
        await savePage(duplicatedNotebook, page);
      }
    }

    final notebooks = await _readIndex();
    await _writeIndex([...notebooks, duplicatedNotebook]);
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

    await _replaceNotebook(updatedNotebook);
    return updatedNotebook;
  }

  @override
  Future<void> deleteNotebook(Notebook notebook) async {
    final notebooks = await _readIndex();
    await _writeIndex([
      for (final existingNotebook in notebooks)
        if (existingNotebook.id != notebook.id) existingNotebook,
    ]);

    final notebookDirectory = _notebookDirectory(notebook);
    if (await notebookDirectory.exists()) {
      await notebookDirectory.delete(recursive: true);
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

    await _replaceNotebook(updatedNotebook);
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

    await _replaceNotebook(updatedNotebook);
    return updatedNotebook;
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

    await _replaceNotebook(updatedNotebook);
    await savePage(
      updatedNotebook,
      NotePage(
        id: pageId,
        width: referencePage.width,
        height: referencePage.height,
      ),
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
    final duplicatedPage = NotePage(
      id: newPageId,
      width: sourcePage.width,
      height: sourcePage.height,
      pdfBackground: sourcePage.pdfBackground,
      strokes: sourcePage.strokes,
      textBoxes: sourcePage.textBoxes,
      images: sourcePage.images,
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
      bookmarkedPageIds: [
        for (final bookmarkedPageId in notebook.bookmarkedPageIds)
          if (bookmarkedPageId != pageId) bookmarkedPageId,
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
    await _runStorageWrite(() async {
      await _writeJsonFile(_pageFile(notebook, page.id), page.toJson());

      final notebooks = await _readIndex();
      final updatedNotebook = notebook.copyWith(updatedAt: DateTime.now());
      await _writeIndex([
        for (final existingNotebook in notebooks)
          if (existingNotebook.id == notebook.id)
            updatedNotebook
          else
            existingNotebook,
      ]);
    });
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
    await _writeJsonFile(
      _indexFile,
      notebooks.map((notebook) => notebook.toJson()).toList(),
    );
  }

  Future<List<NotebookFolder>> _readFolders() async {
    if (!await _foldersFile.exists()) {
      return [];
    }

    final json = jsonDecode(await _foldersFile.readAsString());
    return (json as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(NotebookFolder.fromJson)
        .toList();
  }

  Future<void> _writeFolders(List<NotebookFolder> folders) async {
    await _writeJsonFile(
      _foldersFile,
      folders.map((folder) => folder.toJson()).toList(),
    );
  }

  Future<T> _runStorageWrite<T>(Future<T> Function() write) {
    final previousWrite = _storageWriteQueue;
    final result = previousWrite.catchError((_) {}).then((_) => write());
    _storageWriteQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _writeJsonFile(File file, Object? value) async {
    await file.parent.create(recursive: true);
    final temporaryFile = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-'
      '${_temporaryFileCounter++}',
    );

    await temporaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );

    try {
      await temporaryFile.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temporaryFile.rename(file.path);
    }
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

  Directory _notebookDirectory(Notebook notebook) {
    return Directory('${_notebooksDirectory.path}/${notebook.id}');
  }

  File _pdfAssetFile(Notebook notebook) {
    return File(
      '${_notebooksDirectory.path}/${notebook.id}/assets/imported.pdf',
    );
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = entity.path.replaceFirst(source.path, destination.path);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await File(newPath).parent.create(recursive: true);
        await entity.copy(newPath);
      }
    }
  }

  NotePage _resolvePageAssets(Notebook notebook, NotePage page) {
    final background = page.pdfBackground;
    var resolvedPage = page;

    if (background != null) {
      final normalizedAssetPath = _normalizePdfAssetPath(background.assetPath);
      resolvedPage = resolvedPage.copyWith(
        pdfBackground: background.copyWith(
          assetPath: normalizedAssetPath,
          resolvedFilePath: _resolvePdfAssetPath(
            notebook,
            background.assetPath,
          ),
        ),
      );
    }

    if (page.images.isNotEmpty) {
      resolvedPage = resolvedPage.copyWith(
        images: [
          for (final image in page.images)
            image.copyWith(
              assetPath: _normalizeImageAssetPath(image.assetPath),
              resolvedFilePath: _resolveImageAssetPath(
                notebook,
                image.assetPath,
              ),
            ),
        ],
      );
    }

    return resolvedPage;
  }

  List<PdfOutlineEntry> _pdfOutlineEntries(
    List<PdfOutlineNode> nodes,
    List<String> pageIds,
  ) {
    return [for (final node in nodes) ?_pdfOutlineEntry(node, pageIds)];
  }

  Future<List<PdfOutlineEntry>> _loadPdfOutlineEntries(
    PdfDocument document,
    List<String> pageIds,
  ) async {
    try {
      return _pdfOutlineEntries(await document.loadOutline(), pageIds);
    } catch (_) {
      return const [];
    }
  }

  PdfOutlineEntry? _pdfOutlineEntry(PdfOutlineNode node, List<String> pageIds) {
    final title = node.title.trim().isEmpty ? 'Untitled' : node.title.trim();
    final pageNumber = node.dest?.pageNumber;
    final pageId =
        pageNumber == null || pageNumber < 1 || pageNumber > pageIds.length
        ? null
        : pageIds[pageNumber - 1];
    final children = _pdfOutlineEntries(node.children, pageIds);

    if (pageId == null && children.isEmpty) {
      return null;
    }

    return PdfOutlineEntry(title: title, pageId: pageId, children: children);
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

  String _imageAssetPath(File sourceFile, DateTime now) {
    final originalName = sourceFile.uri.pathSegments.isEmpty
        ? 'image'
        : sourceFile.uri.pathSegments.last;
    final sanitizedName = originalName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final name = sanitizedName.trim().isEmpty ? 'image' : sanitizedName;

    return 'assets/images/${now.microsecondsSinceEpoch}-$name';
  }

  String _normalizeImageAssetPath(String assetPath) {
    final file = File(assetPath);
    if (!file.isAbsolute) {
      return assetPath;
    }

    final fileName = file.uri.pathSegments.isEmpty
        ? 'image'
        : file.uri.pathSegments.last;
    return 'assets/images/$fileName';
  }

  String _resolveImageAssetPath(Notebook notebook, String assetPath) {
    final absoluteFile = File(assetPath);
    if (absoluteFile.isAbsolute && absoluteFile.existsSync()) {
      return absoluteFile.path;
    }

    final normalizedAssetPath = _normalizeImageAssetPath(assetPath);
    return File(
      '${_notebooksDirectory.path}/${notebook.id}/$normalizedAssetPath',
    ).path;
  }

  NotePage _emptyPage(String pageId) {
    return NotePage(id: pageId, width: _pageWidth, height: _pageHeight);
  }

  Future<NotePage> _pageForInsertedBlank(Notebook notebook, int index) {
    if (notebook.pageIds.isEmpty) {
      return Future.value(_emptyPage('blank-reference'));
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
