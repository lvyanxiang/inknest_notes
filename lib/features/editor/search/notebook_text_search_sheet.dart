import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/search/notebook_text_search_service.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_text_box.dart';

Future<NotebookTextSearchResult?> showNotebookTextSearchSheet({
  required BuildContext context,
  required NotebookTextSearchService searchService,
  required List<NotePage> pages,
  required String initialQuery,
  required ValueChanged<String> onQueryChanged,
}) {
  return showModalBottomSheet<NotebookTextSearchResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: NotebookTextSearchSheet(
            searchService: searchService,
            pages: pages,
            initialQuery: initialQuery,
            onQueryChanged: onQueryChanged,
          ),
        ),
      );
    },
  );
}

class NotebookTextSearchSheet extends StatefulWidget {
  const NotebookTextSearchSheet({
    super.key,
    required this.searchService,
    required this.pages,
    required this.initialQuery,
    required this.onQueryChanged,
  });

  final NotebookTextSearchService searchService;
  final List<NotePage> pages;
  final String initialQuery;
  final ValueChanged<String> onQueryChanged;

  @override
  State<NotebookTextSearchSheet> createState() =>
      _NotebookTextSearchSheetState();
}

class _NotebookTextSearchSheetState extends State<NotebookTextSearchSheet> {
  late final TextEditingController _queryController;
  Timer? _debounce;
  NotebookTextSearchResponse? _response;
  bool _isSearching = false;
  int _completedPages = 0;
  int _totalPages = 0;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_search(widget.initialQuery));
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _handleQueryChanged(String value) {
    widget.onQueryChanged(value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _searchGeneration += 1;
      setState(() {
        _response = null;
        _isSearching = false;
        _completedPages = 0;
        _totalPages = 0;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_search(value));
    });
  }

  Future<void> _search(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _isSearching = true;
      _response = null;
      _completedPages = 0;
      _totalPages = 0;
    });

    final response = await widget.searchService.search(
      pages: widget.pages,
      query: query,
      onProgress: (completed, total) {
        if (!mounted || generation != _searchGeneration) {
          return;
        }
        setState(() {
          _completedPages = completed;
          _totalPages = total;
        });
      },
    );

    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      _response = response;
      _isSearching = false;
      _completedPages = _totalPages;
    });
  }

  void _clearQuery() {
    _queryController.clear();
    _handleQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Search notebook',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close notebook search',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _queryController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _handleQueryChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              if (value.trim().isNotEmpty) {
                unawaited(_search(value));
              }
            },
            decoration: InputDecoration(
              hintText: 'Search PDF and editable text',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _queryController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clearQuery,
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isSearching)
          LinearProgressIndicator(
            value: _totalPages == 0 ? null : _completedPages / _totalPages,
          )
        else
          const Divider(height: 1),
        Expanded(child: _buildResults(context, colorScheme)),
      ],
    );
  }

  Widget _buildResults(BuildContext context, ColorScheme colorScheme) {
    if (_queryController.text.trim().isEmpty) {
      return const _SearchMessage(
        icon: Icons.manage_search,
        message:
            'Search PDF text and editable text boxes, including Smart Ink results.',
      );
    }
    if (_isSearching && _response == null) {
      final progressLabel = _totalPages == 0
          ? 'Searching notebook...'
          : 'Reading PDF page $_completedPages of $_totalPages...';
      return _SearchMessage(
        icon: Icons.find_in_page_outlined,
        message: progressLabel,
      );
    }

    final response = _response;
    if (response == null) {
      return const SizedBox.shrink();
    }
    if (!response.hasSearchableText) {
      final message = response.pdfPageCount > 0
          ? 'No searchable text found. Scanned PDF pages still need OCR.'
          : 'No searchable text found in this notebook.';
      return _SearchMessage(
        icon: Icons.text_snippet_outlined,
        message: message,
      );
    }
    if (response.results.isEmpty) {
      return _SearchMessage(
        icon: Icons.search_off,
        message: 'No matches for "${_queryController.text.trim()}".',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Text(
            response.isTruncated
                ? '${response.results.length}+ matches'
                : '${response.results.length} matches',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (response.unavailablePdfPageCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              '${response.unavailablePdfPageCount} PDF pages could not be read.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: response.results.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final result = response.results[index];
              final isPdf = result.source == NotebookTextSearchSource.pdf;
              final sourceLabel = switch (result.textBoxStyle) {
                NoteTextBoxStyle.handwriting => 'Handwriting text',
                NoteTextBoxStyle.regular => 'Text box',
                null => 'PDF page ${result.sourcePageNumber}',
              };
              return ListTile(
                key: ValueKey('notebook-search-result-$index'),
                leading: Icon(
                  isPdf ? Icons.picture_as_pdf_outlined : Icons.text_fields,
                ),
                title: Text(
                  result.snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Notebook page ${result.notebookPageNumber}  |  $sourceLabel',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, result),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
