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

  @override
  void initState() {
    super.initState();
    _notebooks = widget.notebookRepository.listNotebooks();
  }

  void _createNotebook() {
    final notebook = widget.notebookRepository.createNotebook();

    setState(() {
      _notebooks = widget.notebookRepository.listNotebooks();
    });

    _openNotebook(notebook);
  }

  void _openNotebook(Notebook notebook) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditorScreen(notebook: notebook),
      ),
    );
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
            onPressed: _createNotebook,
            tooltip: 'New notebook',
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: _notebooks.isEmpty
            ? _EmptyLibrary(onCreateNotebook: _createNotebook)
            : _NotebookGrid(
                notebooks: _notebooks,
                onOpenNotebook: _openNotebook,
              ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onCreateNotebook});

  final VoidCallback onCreateNotebook;

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
                'No notebooks yet',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Create your first notebook to start sketching ideas, class notes, and PDF annotations.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Align(
                child: FilledButton.icon(
                  onPressed: onCreateNotebook,
                  icon: const Icon(Icons.add),
                  label: const Text('New notebook'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotebookGrid extends StatelessWidget {
  const _NotebookGrid({required this.notebooks, required this.onOpenNotebook});

  final List<Notebook> notebooks;
  final ValueChanged<Notebook> onOpenNotebook;

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
          onTap: () => onOpenNotebook(notebook),
        );
      },
    );
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({required this.notebook, required this.onTap});

  final Notebook notebook;
  final VoidCallback onTap;

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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: const Border(
                    bottom: BorderSide(color: Color(0xFFE4DED1)),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.article_outlined,
                    size: 56,
                    color: colorScheme.primary,
                  ),
                ),
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
                    'Just now',
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
