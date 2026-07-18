import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
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

    await _openNotebook(notebook);
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

    await _openNotebook(importedNotebook);
  }

  Future<void> _openNotebook(Notebook notebook) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => EditorScreen(
          notebook: notebook,
          notebookRepository: widget.notebookRepository,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadNotebooks();
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
    final libraryTitle = _showArchived
        ? 'Archived'
        : _currentFolder?.name ?? 'My Library';
    final itemCount = visibleFolders.length + visibleNotebooks.length;
    final librarySummary = _isLoading
        ? 'Loading library…'
        : _searchQuery.isNotEmpty
        ? '$itemCount match${itemCount == 1 ? '' : 'es'}'
        : _showArchived
        ? '${visibleNotebooks.length} archived notebook${visibleNotebooks.length == 1 ? '' : 's'}'
        : _currentFolderId != null
        ? '${visibleNotebooks.length} notebook${visibleNotebooks.length == 1 ? '' : 's'}'
        : '${visibleFolders.length} folder${visibleFolders.length == 1 ? '' : 's'} · ${visibleNotebooks.length} notebook${visibleNotebooks.length == 1 ? '' : 's'}';

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            _LibraryHeader(
              title: libraryTitle,
              summary: librarySummary,
              showBack: _showArchived || _currentFolderId != null,
              showNewFolder: !_showArchived && _currentFolderId == null,
              showArchived: _showArchived,
              searchController: _searchController,
              sortMode: _sortMode,
              onShowLibrary: _showRootLibrary,
              onSearchChanged: _updateSearchQuery,
              onClearSearch: _clearSearch,
              onSortChanged: _setSortMode,
              onToggleArchived: _toggleArchivedView,
              onCreateFolder: _createFolder,
              onImportPdf: _importPdf,
              onCreateNotebook: _createNotebook,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : visibleNotebooks.isEmpty && visibleFolders.isEmpty
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
                      onOpenFolder: _openFolder,
                      onRenameFolder: (folder) => _renameFolder(folder),
                      onDeleteFolder: (folder) => _deleteFolder(folder),
                      onOpenNotebook: _openNotebook,
                      onRenameNotebook: (notebook) => _renameNotebook(notebook),
                      onDuplicateNotebook: (notebook) =>
                          _duplicateNotebook(notebook),
                      onMoveNotebook: (notebook) => _moveNotebook(notebook),
                      onArchiveNotebook: (notebook) =>
                          _setNotebookArchived(notebook, true),
                      onRestoreNotebook: (notebook) =>
                          _setNotebookArchived(notebook, false),
                      onDeleteNotebook: (notebook) => _deleteNotebook(notebook),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _libraryFurnitureColor(ColorScheme colorScheme) {
  return Color.alphaBlend(
    colorScheme.primary.withValues(alpha: 0.14),
    colorScheme.surfaceContainerHigh,
  );
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.title,
    required this.summary,
    required this.showBack,
    required this.showNewFolder,
    required this.showArchived,
    required this.searchController,
    required this.sortMode,
    required this.onShowLibrary,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onToggleArchived,
    required this.onCreateFolder,
    required this.onImportPdf,
    required this.onCreateNotebook,
  });

  final String title;
  final String summary;
  final bool showBack;
  final bool showNewFolder;
  final bool showArchived;
  final TextEditingController searchController;
  final _LibrarySortMode sortMode;
  final VoidCallback onShowLibrary;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_LibrarySortMode> onSortChanged;
  final VoidCallback onToggleArchived;
  final VoidCallback onCreateFolder;
  final VoidCallback onImportPdf;
  final VoidCallback onCreateNotebook;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
            final compactControls = constraints.maxWidth < 700;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                14,
                horizontalPadding,
                16,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (showBack) ...[
                        IconButton(
                          onPressed: onShowLibrary,
                          tooltip: 'Show library',
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                      ],
                      ExcludeSemantics(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _libraryFurnitureColor(colorScheme),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Icon(
                            Icons.local_library_outlined,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'InkNest Notes',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: onImportPdf,
                        tooltip: 'Import PDF',
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: onCreateNotebook,
                        tooltip: 'New notebook',
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _LibraryCommandBar(
                    compact: compactControls,
                    searchController: searchController,
                    sortMode: sortMode,
                    showNewFolder: showNewFolder,
                    showArchived: showArchived,
                    onSearchChanged: onSearchChanged,
                    onClearSearch: onClearSearch,
                    onSortChanged: onSortChanged,
                    onToggleArchived: onToggleArchived,
                    onCreateFolder: onCreateFolder,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LibraryCommandBar extends StatelessWidget {
  const _LibraryCommandBar({
    required this.compact,
    required this.searchController,
    required this.sortMode,
    required this.showNewFolder,
    required this.showArchived,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onToggleArchived,
    required this.onCreateFolder,
  });

  final bool compact;
  final TextEditingController searchController;
  final _LibrarySortMode sortMode;
  final bool showNewFolder;
  final bool showArchived;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_LibrarySortMode> onSortChanged;
  final VoidCallback onToggleArchived;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final search = _LibrarySearchBar(
      controller: searchController,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
    );
    final controls = <Widget>[
      _LibrarySortControl(mode: sortMode, onSelected: onSortChanged),
      if (showNewFolder) ...[
        const SizedBox(width: 6),
        IconButton(
          onPressed: onCreateFolder,
          tooltip: 'New folder',
          style: IconButton.styleFrom(backgroundColor: colorScheme.surface),
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
      ],
      const SizedBox(width: 6),
      IconButton(
        onPressed: onToggleArchived,
        tooltip: showArchived ? 'Show notebooks' : 'Show archived',
        style: IconButton.styleFrom(backgroundColor: colorScheme.surface),
        icon: Icon(
          showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
        ),
      ),
    ];

    return Container(
      key: const ValueKey('library-command-bar'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _libraryFurnitureColor(colorScheme),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 8),
                Row(children: controls),
              ],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 8),
                ...controls,
              ],
            ),
    );
  }
}

class _LibrarySortControl extends StatelessWidget {
  const _LibrarySortControl({required this.mode, required this.onSelected});

  final _LibrarySortMode mode;
  final ValueChanged<_LibrarySortMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'Sort notebooks: ${mode.label}',
      child: PopupMenuButton<_LibrarySortMode>(
        tooltip: 'Sort notebooks',
        initialValue: mode,
        onSelected: onSelected,
        itemBuilder: (context) {
          return [
            for (final option in _LibrarySortMode.values)
              CheckedPopupMenuItem<_LibrarySortMode>(
                value: option,
                checked: option == mode,
                child: Text(option.label),
              ),
          ];
        },
        child: ExcludeSemantics(
          child: Container(
            height: 48,
            constraints: const BoxConstraints(minWidth: 116),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort_rounded, size: 20),
                const SizedBox(width: 8),
                Text(mode.label),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 48,
      child: TextField(
        key: const ValueKey('library-search-field'),
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search notebooks',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
        final contentWidth = math
            .max(1.0, boundedWidth - horizontalPadding * 2)
            .toDouble();
        final itemCount = folders.length + notebooks.length;
        final itemWidths = [
          for (var index = 0; index < itemCount; index++)
            _itemWidth(index, contentWidth),
        ];
        final rows = _packRows(itemWidths, contentWidth);

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
          itemCount: rows.length,
          itemBuilder: (context, rowIndex) {
            final rowItems = rows[rowIndex];

            return Padding(
              padding: EdgeInsets.only(
                bottom: rowIndex == rows.length - 1 ? 0 : 24,
              ),
              child: _BookshelfRow(
                rowIndex: rowIndex,
                itemWidths: [for (final item in rowItems) itemWidths[item]],
                itemBuilder: (rowItemIndex) {
                  return _buildItem(rowItems[rowItemIndex]);
                },
              ),
            );
          },
        );
      },
    );
  }

  double _itemWidth(int index, double contentWidth) {
    final minimumWidth = contentWidth < 420
        ? 52.0
        : contentWidth < 720
        ? 54.0
        : 56.0;
    final maximumWidth = contentWidth < 420
        ? 74.0
        : contentWidth < 720
        ? 82.0
        : 88.0;

    if (index < folders.length) {
      return math.min(maximumWidth, minimumWidth + 14).toDouble();
    }

    final notebook = notebooks[index - folders.length];
    final pageCount = math.max(1, notebook.pageIds.length);
    final width = minimumWidth + math.log(pageCount + 1) / math.ln10 * 10;
    return width.clamp(minimumWidth, maximumWidth).toDouble();
  }

  List<List<int>> _packRows(List<double> itemWidths, double contentWidth) {
    final rows = <List<int>>[];
    var currentRow = <int>[];
    var currentWidth = 0.0;

    for (var index = 0; index < itemWidths.length; index++) {
      final itemWidth = itemWidths[index];
      if (currentRow.isNotEmpty && currentWidth + itemWidth > contentWidth) {
        rows.add(currentRow);
        currentRow = <int>[];
        currentWidth = 0;
      }

      currentRow.add(index);
      currentWidth += itemWidth;
    }

    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }

    return rows;
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
    required this.itemWidths,
    required this.itemBuilder,
  });

  final int rowIndex;
  final List<double> itemWidths;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('library-bookshelf-row-$rowIndex'),
      height: 270,
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
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (
                    var columnIndex = 0;
                    columnIndex < itemWidths.length;
                    columnIndex++
                  )
                    SizedBox(
                      width: itemWidths[columnIndex],
                      child: itemBuilder(columnIndex),
                    ),
                ],
              ),
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
    final shelfColor = _libraryFurnitureColor(colorScheme);

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
    return _LibrarySpine(
      key: ValueKey('folder-spine-${folder.id}'),
      semanticsLabel: 'Open folder ${folder.name}',
      onTap: onTap,
      backgroundColor: const Color(0xFF6D5845),
      height: 246,
      leanAngle: _spineLeanAngle,
      leadingIcon: Icons.folder_copy_outlined,
      title: folder.name,
      metadata: 'Folder',
      action: _FolderActionMenu(
        folderName: folder.name,
        foregroundColor: Colors.white,
        onSelected: _handleAction,
      ),
    );
  }
}

class _NotebookCard extends StatefulWidget {
  const _NotebookCard({
    required this.notebook,
    required this.showArchived,
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
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  State<_NotebookCard> createState() => _NotebookCardState();
}

class _NotebookCardState extends State<_NotebookCard> {
  bool _isOpening = false;
  bool _isPinnedForInspection = false;
  bool _isHovered = false;
  bool _isFocused = false;

  bool get _isInspecting => _isPinnedForInspection || _isHovered || _isFocused;

  bool get _isPulledOut => _isOpening || _isInspecting;

  Future<void> _handleTap() async {
    if (_isOpening) {
      return;
    }

    final opensImmediately =
        _isInspecting || MediaQuery.of(context).disableAnimations;
    if (!opensImmediately) {
      setState(() {
        _isOpening = true;
      });
      await Future<void>.delayed(_spinePullDuration);
      if (!mounted || !_isOpening) {
        return;
      }
    }

    widget.onTap();
    if (!mounted) {
      return;
    }

    setState(() {
      _isOpening = false;
      _isPinnedForInspection = false;
      _isHovered = false;
      _isFocused = false;
    });
  }

  void _inspect() {
    if (_isOpening || _isPinnedForInspection) {
      return;
    }
    setState(() {
      _isPinnedForInspection = true;
    });
  }

  void _handleHover(bool isHovered) {
    if (_isHovered == isHovered) {
      return;
    }
    setState(() {
      _isHovered = isHovered;
    });
  }

  void _handleFocusChange(bool isFocused) {
    if (_isFocused == isFocused) {
      return;
    }
    setState(() {
      _isFocused = isFocused;
    });
  }

  void _clearInspection() {
    if (!_isInspecting) {
      return;
    }
    setState(() {
      _isPinnedForInspection = false;
      _isHovered = false;
      _isFocused = false;
    });
  }

  void _handleAction(_NotebookAction action) {
    _clearInspection();
    switch (action) {
      case _NotebookAction.rename:
        widget.onRename();
        break;
      case _NotebookAction.duplicate:
        widget.onDuplicate();
        break;
      case _NotebookAction.move:
        widget.onMove();
        break;
      case _NotebookAction.archive:
        widget.onArchive();
        break;
      case _NotebookAction.restore:
        widget.onRestore();
        break;
      case _NotebookAction.delete:
        widget.onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final visualSeed = _stableVisualSeed(notebook.id);
    final backgroundColor =
        _notebookSpinePalette[visualSeed % _notebookSpinePalette.length];
    const heights = [224.0, 232.0, 240.0, 246.0, 236.0];

    return TapRegion(
      onTapOutside: (_) => _clearInspection(),
      child: _LibrarySpine(
        key: ValueKey('notebook-spine-${notebook.id}'),
        semanticsLabel: 'Open notebook ${notebook.title}',
        onTap: () => unawaited(_handleTap()),
        onLongPress: _inspect,
        onHover: _handleHover,
        onFocusChange: _handleFocusChange,
        isPulledOut: _isPulledOut,
        showTitleTip: _isInspecting,
        backgroundColor: backgroundColor,
        height: heights[visualSeed % heights.length],
        leanAngle: _spineLeanAngle,
        leadingIcon: widget.showArchived
            ? Icons.inventory_2_outlined
            : Icons.auto_stories_outlined,
        title: notebook.title,
        metadata: '${notebook.pageIds.length}p',
        action: _NotebookActionMenu(
          notebookTitle: notebook.title,
          showArchived: widget.showArchived,
          foregroundColor: Colors.white,
          onSelected: _handleAction,
        ),
      ),
    );
  }
}

const _notebookSpinePalette = <Color>[
  Color(0xFF2F6F73),
  Color(0xFF8A5D4A),
  Color(0xFF58688E),
  Color(0xFF5E7354),
  Color(0xFF795D76),
  Color(0xFF946A47),
];

const _spineLeanAngle = -math.pi / 60;
const _spinePullDuration = Duration(milliseconds: 200);

int _stableVisualSeed(String value) {
  var result = 0;
  for (final codeUnit in value.codeUnits) {
    result = (result * 31 + codeUnit) & 0x7fffffff;
  }
  return result;
}

class _LibrarySpine extends StatefulWidget {
  const _LibrarySpine({
    super.key,
    required this.semanticsLabel,
    required this.onTap,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.isPulledOut = false,
    this.showTitleTip = false,
    required this.backgroundColor,
    required this.height,
    required this.leanAngle,
    required this.leadingIcon,
    required this.title,
    required this.metadata,
    required this.action,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final bool isPulledOut;
  final bool showTitleTip;
  final Color backgroundColor;
  final double height;
  final double leanAngle;
  final IconData leadingIcon;
  final String title;
  final String metadata;
  final Widget action;

  @override
  State<_LibrarySpine> createState() => _LibrarySpineState();
}

class _LibrarySpineState extends State<_LibrarySpine> {
  final _tooltipKey = GlobalKey<TooltipState>();
  bool _tooltipScheduled = false;

  void _scheduleTooltip() {
    if (_tooltipScheduled) {
      return;
    }
    _tooltipScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tooltipScheduled = false;
      if (mounted && widget.showTitleTip) {
        _tooltipKey.currentState?.ensureTooltipVisible();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final isVisuallyPulledOut = widget.isPulledOut && !reduceMotion;
    final motionDuration = reduceMotion ? Duration.zero : _spinePullDuration;
    const foregroundColor = Colors.white;
    const borderRadius = BorderRadius.vertical(
      top: Radius.circular(6),
      bottom: Radius.circular(2),
    );
    final titleStyle =
        textTheme.labelLarge?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ) ??
        const TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        );
    final titlePainter = TextPainter(
      text: TextSpan(text: widget.title, style: titleStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(0, widget.height - 95));
    final titleIsTruncated = titlePainter.didExceedMaxLines;
    titlePainter.dispose();

    Widget spine = Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: widget.isPulledOut,
      label: widget.semanticsLabel,
      child: AnimatedSlide(
        key: ValueKey('spine-slide-${widget.semanticsLabel}'),
        offset: isVisuallyPulledOut ? const Offset(0, -0.05) : Offset.zero,
        duration: motionDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          key: ValueKey('spine-scale-${widget.semanticsLabel}'),
          scale: isVisuallyPulledOut ? 1.04 : 1,
          alignment: Alignment.bottomCenter,
          duration: motionDuration,
          curve: Curves.easeOutCubic,
          child: Transform.rotate(
            key: ValueKey('spine-lean-${widget.semanticsLabel}'),
            angle: widget.leanAngle,
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: motionDuration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(
                      alpha: isVisuallyPulledOut ? 0.28 : 0.18,
                    ),
                    blurRadius: isVisuallyPulledOut ? 13 : 7,
                    offset: isVisuallyPulledOut
                        ? const Offset(4, 8)
                        : const Offset(2, 4),
                  ),
                ],
              ),
              child: Material(
                color: widget.backgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: borderRadius,
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.16)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  excludeFromSemantics: true,
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  onHover: widget.onHover,
                  onFocusChange: widget.onFocusChange,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 4,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: ColoredBox(
                          color: foregroundColor.withValues(alpha: 0.18),
                        ),
                      ),
                      Column(
                        children: [
                          SizedBox(
                            height: 27,
                            child: Center(
                              child: Icon(
                                widget.leadingIcon,
                                size: 16,
                                color: foregroundColor.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            color: foregroundColor.withValues(alpha: 0.28),
                          ),
                          Expanded(
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            height: 23,
                            alignment: Alignment.center,
                            color: Colors.black.withValues(alpha: 0.08),
                            child: Text(
                              widget.metadata,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: foregroundColor.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          widget.action,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.showTitleTip && titleIsTruncated) {
      _scheduleTooltip();
      spine = Tooltip(
        key: _tooltipKey,
        message: widget.title,
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.manual,
        showDuration: const Duration(hours: 1),
        preferBelow: false,
        child: spine,
      );
    }

    return SizedBox(height: widget.height, child: spine);
  }
}

enum _FolderAction { rename, delete }

class _FolderActionMenu extends StatelessWidget {
  const _FolderActionMenu({
    required this.folderName,
    required this.foregroundColor,
    required this.onSelected,
  });

  final String folderName;
  final Color foregroundColor;
  final ValueChanged<_FolderAction> onSelected;

  @override
  Widget build(BuildContext context) {
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
      child: SizedBox.square(
        dimension: 44,
        child: Icon(Icons.more_horiz_rounded, size: 20, color: foregroundColor),
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
    required this.foregroundColor,
    required this.onSelected,
  });

  final String notebookTitle;
  final bool showArchived;
  final Color foregroundColor;
  final ValueChanged<_NotebookAction> onSelected;

  @override
  Widget build(BuildContext context) {
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
      child: SizedBox.square(
        dimension: 44,
        child: Icon(Icons.more_horiz_rounded, size: 20, color: foregroundColor),
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
