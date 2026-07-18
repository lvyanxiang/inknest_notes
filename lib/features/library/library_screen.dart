import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/features/editor/shapes/shape_layer.dart';
import 'package:inknest_notes/features/editor/templates/page_template_layer.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.notebookRepository});

  final NotebookRepository notebookRepository;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _LibrarySortMode { recent, title, created, updated }

extension _LibrarySortModeLabel on _LibrarySortMode {
  String get label {
    switch (this) {
      case _LibrarySortMode.recent:
        return 'Recent';
      case _LibrarySortMode.title:
        return 'Title';
      case _LibrarySortMode.created:
        return 'Created date';
      case _LibrarySortMode.updated:
        return 'Updated date';
    }
  }
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  late List<Notebook> _notebooks;
  late List<NotebookFolder> _folders;
  bool _isLoading = true;
  bool _showArchived = false;
  bool _isSearchVisible = false;
  String _searchQuery = '';
  _LibrarySortMode _sortMode = _LibrarySortMode.recent;
  String? _currentFolderId;
  NotebookFolder? _currentFolder;

  @override
  void initState() {
    super.initState();
    _notebooks = [];
    _folders = [];
    _loadNotebooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotebooks() async {
    final notebooks = await widget.notebookRepository.listNotebooks(
      archived: _showArchived,
      folderId: _showArchived ? null : _currentFolderId,
    );
    final folders = !_showArchived && _currentFolderId == null
        ? await widget.notebookRepository.listFolders()
        : <NotebookFolder>[];

    if (!mounted) {
      return;
    }

    setState(() {
      _notebooks = notebooks;
      _folders = folders;
      _isLoading = false;
    });
  }

  List<Notebook> get _visibleNotebooks {
    final notebooks = _notebooks.where((notebook) {
      return _matchesSearch(notebook.title);
    }).toList();

    notebooks.sort(_compareNotebooks);
    return notebooks;
  }

  List<NotebookFolder> get _visibleFolders {
    final folders = _folders.where((folder) {
      return _matchesSearch(folder.name);
    }).toList();

    folders.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    return folders;
  }

  bool _matchesSearch(String value) {
    final query = _searchQuery.trim().toLowerCase();
    return query.isEmpty || value.toLowerCase().contains(query);
  }

  int _compareNotebooks(Notebook first, Notebook second) {
    switch (_sortMode) {
      case _LibrarySortMode.recent:
      case _LibrarySortMode.updated:
        return second.updatedAt.compareTo(first.updatedAt);
      case _LibrarySortMode.created:
        return second.createdAt.compareTo(first.createdAt);
      case _LibrarySortMode.title:
        return first.title.toLowerCase().compareTo(second.title.toLowerCase());
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
      if (!_isSearchVisible) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearchQuery('');
  }

  void _setSortMode(_LibrarySortMode mode) {
    setState(() {
      _sortMode = mode;
    });
  }

  Future<void> _createNotebook() async {
    var notebook = await widget.notebookRepository.createNotebook();
    final folderId = _showArchived ? null : _currentFolderId;
    if (folderId != null) {
      notebook = await widget.notebookRepository.moveNotebookToFolder(
        notebook,
        folderId,
      );
    }

    _showArchived = false;
    await _loadNotebooks();

    if (!mounted) {
      return;
    }

    _openNotebook(notebook);
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }

    final notebook = await widget.notebookRepository.importPdf(File(path));
    final folderId = _showArchived ? null : _currentFolderId;
    final importedNotebook = folderId == null
        ? notebook
        : await widget.notebookRepository.moveNotebookToFolder(
            notebook,
            folderId,
          );

    _showArchived = false;
    await _loadNotebooks();

    if (!mounted) {
      return;
    }

    _openNotebook(importedNotebook);
  }

  void _openNotebook(Notebook notebook) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditorScreen(
          notebook: notebook,
          notebookRepository: widget.notebookRepository,
        ),
      ),
    );
  }

  void _toggleArchivedView() {
    setState(() {
      _showArchived = !_showArchived;
      if (_showArchived) {
        _currentFolderId = null;
        _currentFolder = null;
      }
      _isLoading = true;
    });
    _loadNotebooks();
  }

  void _showRootLibrary() {
    setState(() {
      _showArchived = false;
      _currentFolderId = null;
      _currentFolder = null;
      _isLoading = true;
    });
    _loadNotebooks();
  }

  void _openFolder(NotebookFolder folder) {
    setState(() {
      _showArchived = false;
      _currentFolderId = folder.id;
      _currentFolder = folder;
      _isLoading = true;
    });
    _loadNotebooks();
  }

  Future<void> _createFolder() async {
    final name = await _promptName(
      dialogTitle: 'New folder',
      labelText: 'Folder name',
      initialValue: '',
    );
    if (name == null) {
      return;
    }

    await widget.notebookRepository.createFolder(name);
    await _loadNotebooks();
  }

  Future<void> _renameFolder(NotebookFolder folder) async {
    final name = await _promptName(
      dialogTitle: 'Rename folder',
      labelText: 'Folder name',
      initialValue: folder.name,
    );
    if (name == null) {
      return;
    }

    await widget.notebookRepository.renameFolder(folder, name);
    if (_currentFolderId == folder.id) {
      _currentFolder = folder.copyWith(name: name);
    }
    await _loadNotebooks();
  }

  Future<void> _deleteFolder(NotebookFolder folder) async {
    final shouldDelete = await _confirmDeleteFolder(folder);
    if (!shouldDelete) {
      return;
    }

    await widget.notebookRepository.deleteFolder(folder);
    if (_currentFolderId == folder.id) {
      _currentFolderId = null;
      _currentFolder = null;
    }
    await _loadNotebooks();
  }

  Future<bool> _confirmDeleteFolder(NotebookFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete folder?'),
          content: Text(
            '${folder.name} will be removed. Notebooks inside it will move back to the library.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _renameNotebook(Notebook notebook) async {
    final title = await _promptName(
      dialogTitle: 'Rename notebook',
      labelText: 'Notebook title',
      initialValue: notebook.title,
    );
    if (title == null) {
      return;
    }

    await widget.notebookRepository.renameNotebook(notebook, title);
    await _loadNotebooks();
  }

  Future<String?> _promptName({
    required String dialogTitle,
    required String labelText,
    required String initialValue,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NamePromptDialog(
        title: dialogTitle,
        labelText: labelText,
        initialValue: initialValue,
      ),
    );

    if (result == null || result.trim().isEmpty) {
      return null;
    }

    return result.trim();
  }

  Future<void> _moveNotebook(Notebook notebook) async {
    final folders = await widget.notebookRepository.listFolders();
    if (!mounted) {
      return;
    }

    final destination = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Move notebook'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: const ListTile(
                leading: Icon(Icons.home_outlined),
                title: Text('Library'),
              ),
            ),
            for (final folder in folders)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(folder.id),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                ),
              ),
          ],
        );
      },
    );

    if (destination == null) {
      return;
    }

    final folderId = destination.isEmpty ? null : destination;
    await widget.notebookRepository.moveNotebookToFolder(notebook, folderId);
    await _loadNotebooks();
  }

  Future<void> _duplicateNotebook(Notebook notebook) async {
    await widget.notebookRepository.duplicateNotebook(notebook);
    if (_showArchived) {
      setState(() {
        _showArchived = false;
        _isLoading = true;
      });
    }
    await _loadNotebooks();
  }

  Future<void> _setNotebookArchived(Notebook notebook, bool isArchived) async {
    await widget.notebookRepository.setNotebookArchived(notebook, isArchived);
    await _loadNotebooks();
  }

  Future<void> _deleteNotebook(Notebook notebook) async {
    final shouldDelete = await _confirmDeleteNotebook(notebook);
    if (!shouldDelete) {
      return;
    }

    await widget.notebookRepository.deleteNotebook(notebook);
    await _loadNotebooks();
  }

  Future<bool> _confirmDeleteNotebook(Notebook notebook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete notebook?'),
          content: Text(
            '${notebook.title} will be permanently removed from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final visibleFolders = _visibleFolders;
    final visibleNotebooks = _visibleNotebooks;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        leading: _showArchived || _currentFolderId != null
            ? IconButton(
                onPressed: _showRootLibrary,
                tooltip: 'Show library',
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Text(
          _showArchived ? 'Archived' : _currentFolder?.name ?? 'InkNest Notes',
        ),
        actions: [
          IconButton(
            onPressed: _toggleSearch,
            tooltip: _isSearchVisible ? 'Close search' : 'Search notebooks',
            icon: Icon(_isSearchVisible ? Icons.search_off : Icons.search),
          ),
          PopupMenuButton<_LibrarySortMode>(
            tooltip: 'Sort notebooks',
            icon: const Icon(Icons.sort),
            initialValue: _sortMode,
            onSelected: _setSortMode,
            itemBuilder: (context) {
              return [
                for (final mode in _LibrarySortMode.values)
                  CheckedPopupMenuItem<_LibrarySortMode>(
                    value: mode,
                    checked: mode == _sortMode,
                    child: Text(mode.label),
                  ),
              ];
            },
          ),
          IconButton(
            onPressed: _toggleArchivedView,
            tooltip: _showArchived ? 'Show notebooks' : 'Show archived',
            icon: Icon(
              _showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
          ),
          if (!_showArchived && _currentFolderId == null)
            IconButton(
              onPressed: _createFolder,
              tooltip: 'New folder',
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          IconButton(
            onPressed: _importPdf,
            tooltip: 'Import PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            onPressed: _createNotebook,
            tooltip: 'New notebook',
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_isSearchVisible || _searchQuery.isNotEmpty)
                    _LibrarySearchBar(
                      controller: _searchController,
                      onChanged: _updateSearchQuery,
                      onClear: _clearSearch,
                    ),
                  Expanded(
                    child: visibleNotebooks.isEmpty && visibleFolders.isEmpty
                        ? _searchQuery.isEmpty
                              ? _EmptyLibrary(
                                  showArchived: _showArchived,
                                  folderName: _currentFolder?.name,
                                  onCreateNotebook: _createNotebook,
                                  onImportPdf: _importPdf,
                                )
                              : _NoSearchResults(query: _searchQuery)
                        : _LibraryBookshelf(
                            folders: visibleFolders,
                            notebooks: visibleNotebooks,
                            showArchived: _showArchived,
                            notebookRepository: widget.notebookRepository,
                            onOpenFolder: _openFolder,
                            onRenameFolder: (folder) => _renameFolder(folder),
                            onDeleteFolder: (folder) => _deleteFolder(folder),
                            onOpenNotebook: _openNotebook,
                            onRenameNotebook: (notebook) =>
                                _renameNotebook(notebook),
                            onDuplicateNotebook: (notebook) =>
                                _duplicateNotebook(notebook),
                            onMoveNotebook: (notebook) =>
                                _moveNotebook(notebook),
                            onArchiveNotebook: (notebook) =>
                                _setNotebookArchived(notebook, true),
                            onRestoreNotebook: (notebook) =>
                                _setNotebookArchived(notebook, false),
                            onDeleteNotebook: (notebook) =>
                                _deleteNotebook(notebook),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LibrarySearchBar extends StatelessWidget {
  const _LibrarySearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search notebooks',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                ),
          border: const OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              'No matching notebooks',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.showArchived,
    required this.folderName,
    required this.onCreateNotebook,
    required this.onImportPdf,
  });

  final bool showArchived;
  final String? folderName;
  final VoidCallback onCreateNotebook;
  final VoidCallback onImportPdf;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.edit_note,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                showArchived
                    ? 'No archived notebooks'
                    : folderName == null
                    ? 'No notebooks yet'
                    : 'No notebooks in $folderName',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                showArchived
                    ? 'Archived notebooks will appear here until you restore or delete them.'
                    : folderName == null
                    ? 'Create your first notebook to start sketching ideas, class notes, and PDF annotations.'
                    : 'Move notebooks into this folder or create a new notebook here.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!showArchived) ...[
                const SizedBox(height: 28),
                Align(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: onCreateNotebook,
                        icon: const Icon(Icons.add),
                        label: const Text('New notebook'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onImportPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Import PDF'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.labelText,
    required this.initialValue,
  });

  final String title;
  final String labelText;
  final String initialValue;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.labelText),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _LibraryBookshelf extends StatelessWidget {
  const _LibraryBookshelf({
    required this.folders,
    required this.notebooks,
    required this.showArchived,
    required this.notebookRepository,
    required this.onOpenFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onOpenNotebook,
    required this.onRenameNotebook,
    required this.onDuplicateNotebook,
    required this.onMoveNotebook,
    required this.onArchiveNotebook,
    required this.onRestoreNotebook,
    required this.onDeleteNotebook,
  });

  final List<NotebookFolder> folders;
  final List<Notebook> notebooks;
  final bool showArchived;
  final NotebookRepository notebookRepository;
  final ValueChanged<NotebookFolder> onOpenFolder;
  final ValueChanged<NotebookFolder> onRenameFolder;
  final ValueChanged<NotebookFolder> onDeleteFolder;
  final ValueChanged<Notebook> onOpenNotebook;
  final ValueChanged<Notebook> onRenameNotebook;
  final ValueChanged<Notebook> onDuplicateNotebook;
  final ValueChanged<Notebook> onMoveNotebook;
  final ValueChanged<Notebook> onArchiveNotebook;
  final ValueChanged<Notebook> onRestoreNotebook;
  final ValueChanged<Notebook> onDeleteNotebook;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        final boundedWidth = math.min(constraints.maxWidth, 1280.0).toDouble();
        final contentWidth = boundedWidth - horizontalPadding * 2;
        final columnCount = _columnCountForWidth(contentWidth);
        final itemCount = folders.length + notebooks.length;
        final rowCount = (itemCount / columnCount).ceil();

        return ListView.builder(
          key: const ValueKey('library-bookshelf'),
          padding: EdgeInsets.fromLTRB(
            math
                .max(
                  horizontalPadding,
                  (constraints.maxWidth - boundedWidth) / 2 + horizontalPadding,
                )
                .toDouble(),
            20,
            math
                .max(
                  horizontalPadding,
                  (constraints.maxWidth - boundedWidth) / 2 + horizontalPadding,
                )
                .toDouble(),
            32,
          ),
          itemCount: rowCount,
          itemBuilder: (context, rowIndex) {
            final firstItemIndex = rowIndex * columnCount;
            final rowItemCount = math
                .min(columnCount, itemCount - firstItemIndex)
                .toInt();

            return Padding(
              padding: EdgeInsets.only(
                bottom: rowIndex == rowCount - 1 ? 0 : 24,
              ),
              child: _BookshelfRow(
                rowIndex: rowIndex,
                columnCount: columnCount,
                itemCount: rowItemCount,
                itemBuilder: (columnIndex) {
                  return _buildItem(firstItemIndex + columnIndex);
                },
              ),
            );
          },
        );
      },
    );
  }

  int _columnCountForWidth(double width) {
    if (width < 328) {
      return 1;
    }
    if (width < 520) {
      return 2;
    }
    if (width < 760) {
      return 3;
    }
    if (width < 1000) {
      return 4;
    }
    return 5;
  }

  Widget _buildItem(int index) {
    if (index < folders.length) {
      final folder = folders[index];
      return _FolderCard(
        folder: folder,
        onTap: () => onOpenFolder(folder),
        onRename: () => onRenameFolder(folder),
        onDelete: () => onDeleteFolder(folder),
      );
    }

    final notebook = notebooks[index - folders.length];
    return _NotebookCard(
      notebook: notebook,
      showArchived: showArchived,
      notebookRepository: notebookRepository,
      onTap: () => onOpenNotebook(notebook),
      onRename: () => onRenameNotebook(notebook),
      onDuplicate: () => onDuplicateNotebook(notebook),
      onMove: () => onMoveNotebook(notebook),
      onArchive: () => onArchiveNotebook(notebook),
      onRestore: () => onRestoreNotebook(notebook),
      onDelete: () => onDeleteNotebook(notebook),
    );
  }
}

class _BookshelfRow extends StatelessWidget {
  const _BookshelfRow({
    required this.rowIndex,
    required this.columnCount,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int rowIndex;
  final int columnCount;
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    const gap = 16.0;

    return SizedBox(
      key: ValueKey('library-bookshelf-row-$rowIndex'),
      height: 274,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 24,
            child: _ShelfRail(),
          ),
          Positioned.fill(
            bottom: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var columnIndex = 0;
                  columnIndex < columnCount;
                  columnIndex++
                ) ...[
                  if (columnIndex > 0) const SizedBox(width: gap),
                  Expanded(
                    child: columnIndex < itemCount
                        ? Align(
                            alignment: Alignment.bottomCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: SizedBox(
                                width: double.infinity,
                                height: 254,
                                child: itemBuilder(columnIndex),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfRail extends StatelessWidget {
  const _ShelfRail();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shelfColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.14),
      colorScheme.surfaceContainerHigh,
    );

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shelfColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(5),
            bottom: Radius.circular(3),
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final NotebookFolder folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  void _handleAction(_FolderAction action) {
    switch (action) {
      case _FolderAction.rename:
        onRename();
        break;
      case _FolderAction.delete:
        onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _LibraryBookCover(
      semanticsLabel: 'Open folder ${folder.name}',
      onTap: onTap,
      accentColor: colorScheme.tertiary,
      title: folder.name,
      metadata: 'Collection',
      preview: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colorScheme.tertiary.withValues(alpha: 0.08),
            colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Center(
          child: Icon(
            Icons.folder_copy_outlined,
            size: 66,
            color: colorScheme.tertiary,
          ),
        ),
      ),
      action: _FolderActionMenu(
        folderName: folder.name,
        onSelected: _handleAction,
      ),
    );
  }
}

class _NotebookThumbnail extends StatelessWidget {
  const _NotebookThumbnail({
    required this.notebook,
    required this.notebookRepository,
    required this.keyPrefix,
    this.showArchived = false,
  });

  final Notebook notebook;
  final NotebookRepository notebookRepository;
  final String keyPrefix;
  final bool showArchived;

  @override
  Widget build(BuildContext context) {
    final pageId = notebook.pageIds.isEmpty ? null : notebook.pageIds.first;

    return SizedBox(
      key: ValueKey('$keyPrefix-${notebook.id}'),
      width: 92,
      height: 124,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE4DED1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: pageId == null
              ? _NotebookThumbnailPlaceholder(showArchived: showArchived)
              : FutureBuilder<NotePage>(
                  future: notebookRepository.loadPage(notebook, pageId),
                  builder: (context, snapshot) {
                    final page = snapshot.data;
                    if (page == null) {
                      return _NotebookThumbnailPlaceholder(
                        showArchived: showArchived,
                      );
                    }

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _NotebookThumbnailPainter(page: page),
                          ),
                        ),
                        if (page.pdfBackground != null)
                          const Positioned(
                            left: 5,
                            bottom: 5,
                            child: _ThumbnailBadge(
                              icon: Icons.picture_as_pdf_outlined,
                            ),
                          ),
                        if (showArchived)
                          const Positioned(
                            right: 5,
                            bottom: 5,
                            child: _ThumbnailBadge(
                              icon: Icons.inventory_2_outlined,
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _NotebookThumbnailPlaceholder extends StatelessWidget {
  const _NotebookThumbnailPlaceholder({required this.showArchived});

  final bool showArchived;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: Center(
        child: Icon(
          showArchived ? Icons.inventory_2_outlined : Icons.article_outlined,
          color: colorScheme.primary,
          size: 32,
        ),
      ),
    );
  }
}

class _ThumbnailBadge extends StatelessWidget {
  const _ThumbnailBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SizedBox.square(
        dimension: 22,
        child: Icon(icon, size: 14, color: colorScheme.primary),
      ),
    );
  }
}

class _NotebookThumbnailPainter extends CustomPainter {
  const _NotebookThumbnailPainter({required this.page});

  final NotePage page;

  @override
  void paint(Canvas canvas, Size size) {
    final pageWidth = page.width <= 0 ? size.width : page.width;
    final pageHeight = page.height <= 0 ? size.height : page.height;
    final displayWidth = page.isSideways ? pageHeight : pageWidth;
    final displayHeight = page.isSideways ? pageWidth : pageHeight;
    final scale = math.min(
      size.width / displayWidth,
      size.height / displayHeight,
    );
    final previewSize = Size(displayWidth * scale, displayHeight * scale);
    final previewOffset = Offset(
      (size.width - previewSize.width) / 2,
      (size.height - previewSize.height) / 2,
    );
    final previewRect = previewOffset & previewSize;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    canvas.save();
    canvas.clipRect(previewRect);
    canvas.translate(previewOffset.dx, previewOffset.dy);
    canvas.scale(scale);
    _applyPageRotation(canvas, page, pageWidth, pageHeight);

    if (page.pdfBackground != null) {
      final pdfPaint = Paint()..color = const Color(0xFFFFF6E2);
      canvas.drawRect(Offset.zero & Size(pageWidth, pageHeight), pdfPaint);

      final linePaint = Paint()
        ..color = const Color(0xFFE7DCC4)
        ..strokeWidth = 1 / scale;
      for (var y = 14.0; y < pageHeight; y += 14) {
        canvas.drawLine(Offset(8, y), Offset(pageWidth - 8, y), linePaint);
      }
    } else {
      paintPageTemplate(
        canvas,
        Size(pageWidth, pageHeight),
        page.template,
        minimumStrokeWidth: 1 / scale,
      );
    }

    for (final stroke in page.strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final paint = Paint()
        ..color = stroke.isHighlighter
            ? stroke.color.withValues(alpha: 0.36)
            : stroke.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.single.offset,
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(StrokeGeometry.buildSmoothPath(stroke.points), paint);
      }
    }

    for (final shape in page.shapes) {
      paintNoteShape(canvas, shape, minimumStrokeWidth: 1.4 / scale);
    }

    canvas.restore();
  }

  void _applyPageRotation(
    Canvas canvas,
    NotePage page,
    double pageWidth,
    double pageHeight,
  ) {
    switch (page.rotationQuarterTurns) {
      case 1:
        canvas
          ..translate(pageHeight, 0)
          ..rotate(math.pi / 2);
        break;
      case 2:
        canvas
          ..translate(pageWidth, pageHeight)
          ..rotate(math.pi);
        break;
      case 3:
        canvas
          ..translate(0, pageWidth)
          ..rotate(math.pi * 3 / 2);
        break;
    }
  }

  @override
  bool shouldRepaint(_NotebookThumbnailPainter oldDelegate) {
    return oldDelegate.page != page;
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({
    required this.notebook,
    required this.showArchived,
    required this.notebookRepository,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onMove,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
  });

  final Notebook notebook;
  final bool showArchived;
  final NotebookRepository notebookRepository;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  void _handleAction(_NotebookAction action) {
    switch (action) {
      case _NotebookAction.rename:
        onRename();
        break;
      case _NotebookAction.duplicate:
        onDuplicate();
        break;
      case _NotebookAction.move:
        onMove();
        break;
      case _NotebookAction.archive:
        onArchive();
        break;
      case _NotebookAction.restore:
        onRestore();
        break;
      case _NotebookAction.delete:
        onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _LibraryBookCover(
      semanticsLabel: 'Open notebook ${notebook.title}',
      onTap: onTap,
      accentColor: colorScheme.primary,
      title: notebook.title,
      metadata:
          '${notebook.pageIds.length} page${notebook.pageIds.length == 1 ? '' : 's'}',
      preview: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Center(
          child: _NotebookThumbnail(
            notebook: notebook,
            notebookRepository: notebookRepository,
            keyPrefix: 'notebook-thumbnail-card',
            showArchived: showArchived,
          ),
        ),
      ),
      action: _NotebookActionMenu(
        notebookTitle: notebook.title,
        showArchived: showArchived,
        onSelected: _handleAction,
      ),
    );
  }
}

class _LibraryBookCover extends StatelessWidget {
  const _LibraryBookCover({
    required this.semanticsLabel,
    required this.onTap,
    required this.accentColor,
    required this.title,
    required this.metadata,
    required this.preview,
    required this.action,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final Color accentColor;
  final String title;
  final String metadata;
  final Widget preview;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = BorderRadius.circular(12);
    final coverColor = Color.alphaBlend(
      accentColor.withValues(alpha: 0.07),
      colorScheme.surface,
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: coverColor,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                          child: preview,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.72),
                          border: Border(
                            top: BorderSide(color: colorScheme.outlineVariant),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      metadata,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              action,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          accentColor.withValues(alpha: 0.92),
                          accentColor.withValues(alpha: 0.58),
                        ],
                      ),
                      border: Border(
                        right: BorderSide(
                          color: colorScheme.shadow.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _FolderAction { rename, delete }

class _FolderActionMenu extends StatelessWidget {
  const _FolderActionMenu({required this.folderName, required this.onSelected});

  final String folderName;
  final ValueChanged<_FolderAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_FolderAction>(
      tooltip: '$folderName actions',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          _folderActionItem(
            value: _FolderAction.rename,
            icon: Icons.edit_outlined,
            label: 'Rename folder',
          ),
          _folderActionItem(
            value: _FolderAction.delete,
            icon: Icons.delete_outline,
            label: 'Delete folder',
          ),
        ];
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: const SizedBox.square(
          dimension: 44,
          child: Icon(Icons.more_horiz, size: 20),
        ),
      ),
    );
  }
}

PopupMenuItem<_FolderAction> _folderActionItem({
  required _FolderAction value,
  required IconData icon,
  required String label,
}) {
  return PopupMenuItem<_FolderAction>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

enum _NotebookAction { rename, duplicate, move, archive, restore, delete }

class _NotebookActionMenu extends StatelessWidget {
  const _NotebookActionMenu({
    required this.notebookTitle,
    required this.showArchived,
    required this.onSelected,
  });

  final String notebookTitle;
  final bool showArchived;
  final ValueChanged<_NotebookAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_NotebookAction>(
      tooltip: '$notebookTitle actions',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          _notebookActionItem(
            value: _NotebookAction.rename,
            icon: Icons.edit_outlined,
            label: 'Rename notebook',
          ),
          _notebookActionItem(
            value: _NotebookAction.duplicate,
            icon: Icons.copy,
            label: 'Duplicate notebook',
          ),
          if (!showArchived)
            _notebookActionItem(
              value: _NotebookAction.move,
              icon: Icons.drive_file_move_outline,
              label: 'Move notebook',
            ),
          if (showArchived)
            _notebookActionItem(
              value: _NotebookAction.restore,
              icon: Icons.unarchive_outlined,
              label: 'Restore notebook',
            )
          else
            _notebookActionItem(
              value: _NotebookAction.archive,
              icon: Icons.archive_outlined,
              label: 'Archive notebook',
            ),
          _notebookActionItem(
            value: _NotebookAction.delete,
            icon: Icons.delete_outline,
            label: 'Delete notebook',
          ),
        ];
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: const SizedBox.square(
          dimension: 44,
          child: Icon(Icons.more_horiz, size: 20),
        ),
      ),
    );
  }
}

PopupMenuItem<_NotebookAction> _notebookActionItem({
  required _NotebookAction value,
  required IconData icon,
  required String label,
}) {
  return PopupMenuItem<_NotebookAction>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
