import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/pdf_search/notebook_pdf_text_searcher.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';

class NotebookPdfSearchPanel extends StatefulWidget {
  const NotebookPdfSearchPanel({
    super.key,
    required this.notebook,
    required this.pages,
    required this.textSearcher,
    required this.onSelectResult,
  });

  final Notebook notebook;
  final List<NotePage> pages;
  final NotebookPdfTextSearcher textSearcher;
  final ValueChanged<PdfTextSearchResult> onSelectResult;

  @override
  State<NotebookPdfSearchPanel> createState() => _NotebookPdfSearchPanelState();
}

class _NotebookPdfSearchPanelState extends State<NotebookPdfSearchPanel> {
  final TextEditingController _queryController = TextEditingController();
  List<PdfTextSearchResult> _results = const [];
  Object? _searchError;
  int _searchGeneration = 0;
  bool _hasSearched = false;
  bool _isSearching = false;

  bool get _hasPdfPages {
    return widget.pages.any((page) => page.pdfBackground != null);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    final generation = ++_searchGeneration;
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searchError = null;
        _hasSearched = false;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _searchError = null;
      _hasSearched = true;
      _isSearching = true;
    });
    try {
      final results = await widget.textSearcher.search(
        pages: widget.pages,
        query: query,
      );
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      setState(() {
        _results = const [];
        _searchError = error;
      });
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const ValueKey('pdf-search-field'),
            controller: _queryController,
            enabled: _hasPdfPages && !_isSearching,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_search()),
            decoration: InputDecoration(
              hintText: _hasPdfPages
                  ? 'Search PDF text'
                  : 'This notebook has no PDF pages',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _hasPdfPages && !_isSearching
                    ? () => unawaited(_search())
                    : null,
                tooltip: 'Search PDF text',
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_isSearching) const LinearProgressIndicator(),
        Expanded(child: _buildSearchBody(context)),
      ],
    );
  }

  Widget _buildSearchBody(BuildContext context) {
    if (!_hasPdfPages) {
      return const _PdfSearchEmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: 'No PDF pages to search',
      );
    }
    if (_isSearching && _results.isEmpty) {
      return const _PdfSearchEmptyState(
        icon: Icons.manage_search,
        title: 'Searching PDF…',
      );
    }
    if (_searchError != null) {
      return const _PdfSearchEmptyState(
        icon: Icons.error_outline,
        title: 'Could not search this PDF',
      );
    }
    if (!_hasSearched) {
      return const _PdfSearchEmptyState(
        icon: Icons.text_snippet_outlined,
        title: 'Search text embedded in the PDF',
      );
    }
    if (_results.isEmpty) {
      return const _PdfSearchEmptyState(
        icon: Icons.search_off,
        title: 'No matches; scanned PDFs may need OCR',
      );
    }

    return ListView.builder(
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final label = _results.length == 1
              ? '1 match'
              : '${_results.length} matches';
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          );
        }

        final result = _results[index - 1];
        return ListTile(
          key: ValueKey('pdf-search-result-${index - 1}'),
          leading: const Icon(Icons.find_in_page_outlined),
          title: Text(
            result.snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_pageLabel(result.pageId)} · '
            'PDF page ${result.pdfPageNumber}',
          ),
          onTap: () => widget.onSelectResult(result),
        );
      },
    );
  }

  String _pageLabel(String pageId) {
    final index = widget.notebook.pageIds.indexOf(pageId);
    return index == -1 ? 'Page' : 'Page ${index + 1}';
  }
}

class _PdfSearchEmptyState extends StatelessWidget {
  const _PdfSearchEmptyState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
