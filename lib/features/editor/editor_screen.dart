import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/canvas/pdf_page_background.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.notebook,
    required this.notebookRepository,
  });

  final Notebook notebook;
  final NotebookRepository notebookRepository;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final List<Stroke> _redoStack = [];
  DrawingTool _tool = const DrawingTool();
  late Notebook _notebook;
  late String _currentPageId;
  NotePage? _page;

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
    _currentPageId = _notebook.pageIds.first;
    _loadPage();
  }

  Future<void> _loadPage() async {
    final page = await widget.notebookRepository.loadPage(
      _notebook,
      _currentPageId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _page = page;
      _redoStack.clear();
    });
  }

  void _addStroke(Stroke stroke) {
    final page = _page;
    if (page == null) {
      return;
    }

    setState(() {
      _page = page.copyWith(strokes: [...page.strokes, stroke]);
      _redoStack.clear();
    });

    _savePage();
  }

  void _undo() {
    final page = _page;
    if (page == null || page.strokes.isEmpty) {
      return;
    }

    setState(() {
      final updatedStrokes = page.strokes.toList();
      _redoStack.add(updatedStrokes.removeLast());
      _page = page.copyWith(strokes: updatedStrokes);
    });

    _savePage();
  }

  void _redo() {
    final page = _page;
    if (page == null || _redoStack.isEmpty) {
      return;
    }

    setState(() {
      final stroke = _redoStack.removeLast();
      _page = page.copyWith(strokes: [...page.strokes, stroke]);
    });

    _savePage();
  }

  void _setTool(DrawingTool tool) {
    setState(() {
      _tool = tool;
    });
  }

  void _eraseAt(List<StrokePoint> points) {
    final page = _page;
    if (page == null) {
      return;
    }

    final remainingStrokes = page.strokes
        .where((stroke) => !_strokeIntersectsEraser(stroke, points))
        .toList();

    if (remainingStrokes.length == page.strokes.length) {
      return;
    }

    setState(() {
      _page = page.copyWith(strokes: remainingStrokes);
      _redoStack.clear();
    });

    _savePage();
  }

  bool _strokeIntersectsEraser(Stroke stroke, List<StrokePoint> eraserPoints) {
    final radius = _tool.width / 2;

    for (final strokePoint in stroke.points) {
      for (final eraserPoint in eraserPoints) {
        if ((strokePoint.offset - eraserPoint.offset).distance <= radius) {
          return true;
        }
      }
    }

    return false;
  }

  void _savePage() {
    final page = _page;
    if (page == null) {
      return;
    }

    unawaited(widget.notebookRepository.savePage(_notebook, page));
  }

  Future<void> _addPage() async {
    final updatedNotebook = await widget.notebookRepository.addPage(_notebook);

    if (!mounted) {
      return;
    }

    setState(() {
      _notebook = updatedNotebook;
      _currentPageId = updatedNotebook.pageIds.last;
      _page = null;
      _redoStack.clear();
    });

    await _loadPage();
  }

  Future<void> _selectPage(String pageId) async {
    if (pageId == _currentPageId) {
      return;
    }

    setState(() {
      _currentPageId = pageId;
      _page = null;
      _redoStack.clear();
    });

    await _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;

    return Scaffold(
      appBar: AppBar(
        title: Text(_notebook.title),
        actions: [
          IconButton(
            onPressed: page == null || page.strokes.isEmpty ? null : _undo,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: _redoStack.isEmpty ? null : _redo,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      body: Column(
        children: [
          EditorToolbar(tool: _tool, onToolChanged: _setTool),
          Expanded(
            child: page == null
                ? const Center(child: CircularProgressIndicator())
                : _buildPageCanvas(page),
          ),
          _PageNavigator(
            pageIds: _notebook.pageIds,
            currentPageId: _currentPageId,
            onSelectPage: (pageId) => unawaited(_selectPage(pageId)),
            onAddPage: () => unawaited(_addPage()),
          ),
        ],
      ),
    );
  }

  Widget _buildPageCanvas(NotePage page) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AspectRatio(
          aspectRatio: page.width / page.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4DED1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A1E2526),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (page.pdfBackground case final background?)
                    PdfPageBackgroundView(
                      key: ValueKey(
                        '${background.filePath}-${background.pageNumber}',
                      ),
                      background: background,
                    ),
                  DrawingCanvas(
                    page: page,
                    tool: _tool,
                    onStrokeComplete: _addStroke,
                    onErase: _eraseAt,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageNavigator extends StatelessWidget {
  const _PageNavigator({
    required this.pageIds,
    required this.currentPageId,
    required this.onSelectPage,
    required this.onAddPage,
  });

  final List<String> pageIds;
  final String currentPageId;
  final ValueChanged<String> onSelectPage;
  final VoidCallback onAddPage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 1,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              for (final (index, pageId) in pageIds.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: 'Page ${index + 1}',
                    child: ChoiceChip(
                      selected: pageId == currentPageId,
                      label: Text('${index + 1}'),
                      onSelected: (_) => onSelectPage(pageId),
                    ),
                  ),
                ),
              IconButton.filledTonal(
                onPressed: onAddPage,
                tooltip: 'Add page',
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
