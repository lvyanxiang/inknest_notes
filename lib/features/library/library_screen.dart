import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.notebookRepository});

  final NotebookRepository notebookRepository;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late List<Notebook> _notebooks;
  bool _isLoading = true;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _notebooks = [];
    _loadNotebooks();
  }

  Future<void> _loadNotebooks() async {
    final notebooks = await widget.notebookRepository.listNotebooks(
      archived: _showArchived,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _notebooks = notebooks;
      _isLoading = false;
    });
  }

  Future<void> _createNotebook() async {
    final notebook = await widget.notebookRepository.createNotebook();

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

    _showArchived = false;
    await _loadNotebooks();

    if (!mounted) {
      return;
    }

    _openNotebook(notebook);
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
      _isLoading = true;
    });
    _loadNotebooks();
  }

  Future<void> _renameNotebook(Notebook notebook) async {
    final title = await _promptNotebookTitle(notebook.title);
    if (title == null) {
      return;
    }

    await widget.notebookRepository.renameNotebook(notebook, title);
    await _loadNotebooks();
  }

  Future<String?> _promptNotebookTitle(String currentTitle) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _RenameNotebookDialog(initialTitle: currentTitle),
    );

    if (result == null || result.trim().isEmpty) {
      return null;
    }

    return result.trim();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('InkNest Notes'),
        actions: [
          IconButton(
            onPressed: () {},
            tooltip: 'Search notebooks',
            icon: const Icon(Icons.search),
          ),
          IconButton(
            onPressed: _toggleArchivedView,
            tooltip: _showArchived ? 'Show notebooks' : 'Show archived',
            icon: Icon(
              _showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
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
            : _notebooks.isEmpty
            ? _EmptyLibrary(
                showArchived: _showArchived,
                onCreateNotebook: _createNotebook,
                onImportPdf: _importPdf,
              )
            : _NotebookGrid(
                notebooks: _notebooks,
                showArchived: _showArchived,
                onOpenNotebook: _openNotebook,
                onRenameNotebook: (notebook) => _renameNotebook(notebook),
                onDuplicateNotebook: (notebook) => _duplicateNotebook(notebook),
                onArchiveNotebook: (notebook) =>
                    _setNotebookArchived(notebook, true),
                onRestoreNotebook: (notebook) =>
                    _setNotebookArchived(notebook, false),
                onDeleteNotebook: (notebook) => _deleteNotebook(notebook),
              ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.showArchived,
    required this.onCreateNotebook,
    required this.onImportPdf,
  });

  final bool showArchived;
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
                showArchived ? 'No archived notebooks' : 'No notebooks yet',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                showArchived
                    ? 'Archived notebooks will appear here until you restore or delete them.'
                    : 'Create your first notebook to start sketching ideas, class notes, and PDF annotations.',
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

class _RenameNotebookDialog extends StatefulWidget {
  const _RenameNotebookDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameNotebookDialog> createState() => _RenameNotebookDialogState();
}

class _RenameNotebookDialogState extends State<_RenameNotebookDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
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
      title: const Text('Rename notebook'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Notebook title'),
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

class _NotebookGrid extends StatelessWidget {
  const _NotebookGrid({
    required this.notebooks,
    required this.showArchived,
    required this.onOpenNotebook,
    required this.onRenameNotebook,
    required this.onDuplicateNotebook,
    required this.onArchiveNotebook,
    required this.onRestoreNotebook,
    required this.onDeleteNotebook,
  });

  final List<Notebook> notebooks;
  final bool showArchived;
  final ValueChanged<Notebook> onOpenNotebook;
  final ValueChanged<Notebook> onRenameNotebook;
  final ValueChanged<Notebook> onDuplicateNotebook;
  final ValueChanged<Notebook> onArchiveNotebook;
  final ValueChanged<Notebook> onRestoreNotebook;
  final ValueChanged<Notebook> onDeleteNotebook;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 232,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: notebooks.length,
      itemBuilder: (context, index) {
        final notebook = notebooks[index];

        return _NotebookCard(
          notebook: notebook,
          showArchived: showArchived,
          onTap: () => onOpenNotebook(notebook),
          onRename: () => onRenameNotebook(notebook),
          onDuplicate: () => onDuplicateNotebook(notebook),
          onArchive: () => onArchiveNotebook(notebook),
          onRestore: () => onRestoreNotebook(notebook),
          onDelete: () => onDeleteNotebook(notebook),
        );
      },
    );
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({
    required this.notebook,
    required this.showArchived,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
  });

  final Notebook notebook;
  final bool showArchived;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
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
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFFE4DED1)),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          showArchived
                              ? Icons.inventory_2_outlined
                              : Icons.article_outlined,
                          size: 56,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _NotebookActionMenu(
                      notebookTitle: notebook.title,
                      showArchived: showArchived,
                      onSelected: _handleAction,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notebook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${notebook.pageIds.length} page${notebook.pageIds.length == 1 ? '' : 's'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NotebookAction { rename, duplicate, archive, restore, delete }

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
          dimension: 32,
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
