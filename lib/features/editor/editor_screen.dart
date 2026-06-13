import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.notebook});

  final Notebook notebook;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const _pageWidth = 768.0;
  static const _pageHeight = 1024.0;

  final List<Stroke> _redoStack = [];
  DrawingTool _tool = const DrawingTool();
  late NotePage _page;

  @override
  void initState() {
    super.initState();
    _page = const NotePage(
      id: 'page-1',
      width: _pageWidth,
      height: _pageHeight,
    );
  }

  void _addStroke(Stroke stroke) {
    setState(() {
      _page = _page.copyWith(strokes: [..._page.strokes, stroke]);
      _redoStack.clear();
    });
  }

  void _undo() {
    if (_page.strokes.isEmpty) {
      return;
    }

    setState(() {
      final updatedStrokes = _page.strokes.toList();
      _redoStack.add(updatedStrokes.removeLast());
      _page = _page.copyWith(strokes: updatedStrokes);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }

    setState(() {
      final stroke = _redoStack.removeLast();
      _page = _page.copyWith(strokes: [..._page.strokes, stroke]);
    });
  }

  void _setTool(DrawingTool tool) {
    setState(() {
      _tool = tool;
    });
  }

  void _eraseAt(List<StrokePoint> points) {
    final remainingStrokes = _page.strokes
        .where((stroke) => !_strokeIntersectsEraser(stroke, points))
        .toList();

    if (remainingStrokes.length == _page.strokes.length) {
      return;
    }

    setState(() {
      _page = _page.copyWith(strokes: remainingStrokes);
      _redoStack.clear();
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.notebook.title),
        actions: [
          IconButton(
            onPressed: _page.strokes.isEmpty ? null : _undo,
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
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AspectRatio(
                  aspectRatio: _page.width / _page.height,
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
                      child: DrawingCanvas(
                        page: _page,
                        tool: _tool,
                        onStrokeComplete: _addStroke,
                        onErase: _eraseAt,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
