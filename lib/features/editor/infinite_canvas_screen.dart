import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class InfiniteCanvasScreen extends StatefulWidget {
  const InfiniteCanvasScreen({
    super.key,
    required this.notebook,
    required this.notebookRepository,
  });

  final Notebook notebook;
  final NotebookRepository notebookRepository;

  @override
  State<InfiniteCanvasScreen> createState() => _InfiniteCanvasScreenState();
}

class _InfiniteCanvasScreenState extends State<InfiniteCanvasScreen> {
  final _viewportKey = GlobalKey<_InfiniteCanvasViewportState>();
  final List<List<Stroke>> _undoStates = [];
  final List<List<Stroke>> _redoStates = [];
  InfiniteCanvasDocument? _document;
  DrawingTool _tool = const DrawingTool(
    type: ToolType.pen,
    color: Color(0xFF1E2526),
    width: 3,
  );
  bool _fingerPanEnabled = false;
  bool _fingerWritingAssistEnabled = true;
  List<Stroke>? _eraseStartState;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final document = await widget.notebookRepository.loadInfiniteCanvas(
      widget.notebook,
    );
    if (!mounted) return;
    setState(() => _document = document);
  }

  Future<void> _save(InfiniteCanvasDocument document) {
    return widget.notebookRepository.saveInfiniteCanvas(
      widget.notebook,
      document,
    );
  }

  void _commitStroke(Stroke stroke) {
    final document = _document;
    if (document == null) return;
    _undoStates.add(document.strokes);
    _redoStates.clear();
    final updated = document.copyWith(strokes: [...document.strokes, stroke]);
    setState(() => _document = updated);
    _save(updated);
  }

  void _beginErase() {
    _eraseStartState ??= _document?.strokes;
  }

  void _eraseAt(Offset point) {
    final document = _document;
    if (document == null) return;
    final updatedStrokes = StrokeGeometry.eraseStrokes(
      strokes: document.strokes,
      eraserPoints: [
        StrokePoint(offset: point, pressure: 1, time: DateTime.now()),
      ],
      radius: math.max(8, _tool.width / 2),
    );
    if (identical(updatedStrokes, document.strokes)) return;
    setState(() => _document = document.copyWith(strokes: updatedStrokes));
  }

  void _endErase() {
    final before = _eraseStartState;
    final document = _document;
    _eraseStartState = null;
    if (before == null ||
        document == null ||
        identical(before, document.strokes)) {
      return;
    }
    _undoStates.add(before);
    _redoStates.clear();
    _save(document);
  }

  void _undo() {
    final document = _document;
    if (document == null || _undoStates.isEmpty) return;
    _redoStates.add(document.strokes);
    final updated = document.copyWith(strokes: _undoStates.removeLast());
    setState(() => _document = updated);
    _save(updated);
  }

  void _redo() {
    final document = _document;
    if (document == null || _redoStates.isEmpty) return;
    _undoStates.add(document.strokes);
    final updated = document.copyWith(strokes: _redoStates.removeLast());
    setState(() => _document = updated);
    _save(updated);
  }

  void _changeBackground(InfiniteCanvasBackground background) {
    final document = _document;
    if (document == null || document.background == background) return;
    final updated = document.copyWith(background: background);
    setState(() => _document = updated);
    _save(updated);
  }

  void _viewportChanged(Offset focus, double scale) {
    final document = _document;
    if (document == null) return;
    final updated = document.copyWith(
      viewportFocus: focus,
      viewportScale: scale,
    );
    _document = updated;
    _save(updated);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.notebook.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Infinite canvas',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('infinite-canvas-undo'),
            tooltip: 'Undo',
            onPressed: _undoStates.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const ValueKey('infinite-canvas-redo'),
            tooltip: 'Redo',
            onPressed: _redoStates.isEmpty ? null : _redo,
            icon: const Icon(Icons.redo),
          ),
          PopupMenuButton<InfiniteCanvasBackground>(
            key: const ValueKey('infinite-canvas-background'),
            tooltip: 'Canvas background',
            initialValue: document?.background,
            onSelected: _changeBackground,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: InfiniteCanvasBackground.blank,
                child: _BackgroundMenuItem(
                  icon: Icons.crop_square,
                  label: 'Blank',
                ),
              ),
              PopupMenuItem(
                value: InfiniteCanvasBackground.dotted,
                child: _BackgroundMenuItem(
                  icon: Icons.more_horiz,
                  label: 'Dotted',
                ),
              ),
              PopupMenuItem(
                value: InfiniteCanvasBackground.grid,
                child: _BackgroundMenuItem(icon: Icons.grid_4x4, label: 'Grid'),
              ),
            ],
            icon: const Icon(Icons.texture),
          ),
          IconButton(
            key: const ValueKey('infinite-canvas-recenter'),
            tooltip: 'Fit content',
            onPressed: document == null
                ? null
                : () => _viewportKey.currentState?.fitContent(document.strokes),
            icon: const Icon(Icons.center_focus_strong),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: document == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _InfiniteCanvasViewport(
                    key: _viewportKey,
                    document: document,
                    tool: _tool,
                    fingerPanEnabled: _fingerPanEnabled,
                    fingerWritingAssistEnabled: _fingerWritingAssistEnabled,
                    onStrokeComplete: _commitStroke,
                    onEraseStart: _beginErase,
                    onEraseAt: _eraseAt,
                    onEraseEnd: _endErase,
                    onViewportChanged: _viewportChanged,
                  ),
                ),
                EditorToolbar(
                  tool: _tool,
                  fingerPanEnabled: _fingerPanEnabled,
                  fingerWritingAssistEnabled: _fingerWritingAssistEnabled,
                  onToolChanged: (tool) => setState(() => _tool = tool),
                  onFingerPanChanged: (enabled) =>
                      setState(() => _fingerPanEnabled = enabled),
                  onFingerWritingAssistChanged: (enabled) =>
                      setState(() => _fingerWritingAssistEnabled = enabled),
                  onInsertImage: () {},
                  showLasso: false,
                  showInsert: false,
                ),
              ],
            ),
    );
  }
}

class _BackgroundMenuItem extends StatelessWidget {
  const _BackgroundMenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]);
  }
}

class _InfiniteCanvasViewport extends StatefulWidget {
  const _InfiniteCanvasViewport({
    super.key,
    required this.document,
    required this.tool,
    required this.fingerPanEnabled,
    required this.fingerWritingAssistEnabled,
    required this.onStrokeComplete,
    required this.onEraseStart,
    required this.onEraseAt,
    required this.onEraseEnd,
    required this.onViewportChanged,
  });

  final InfiniteCanvasDocument document;
  final DrawingTool tool;
  final bool fingerPanEnabled;
  final bool fingerWritingAssistEnabled;
  final ValueChanged<Stroke> onStrokeComplete;
  final VoidCallback onEraseStart;
  final ValueChanged<Offset> onEraseAt;
  final VoidCallback onEraseEnd;
  final void Function(Offset focus, double scale) onViewportChanged;

  @override
  State<_InfiniteCanvasViewport> createState() =>
      _InfiniteCanvasViewportState();
}

class _InfiniteCanvasViewportState extends State<_InfiniteCanvasViewport> {
  final Map<int, Offset> _touches = {};
  late Offset _focus = widget.document.viewportFocus;
  late double _scale = widget.document.viewportScale;
  Stroke? _activeStroke;
  int? _drawingPointer;
  PointerDeviceKind? _drawingKind;
  int? _panPointer;
  Offset? _lastPanPosition;
  Offset? _gestureFocal;
  double? _gestureDistance;
  bool _erasing = false;

  Offset _screenToWorld(Offset point, Size size) {
    return (point - size.center(Offset.zero)) / _scale + _focus;
  }

  Size get _size => (context.findRenderObject()! as RenderBox).size;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length >= 2) {
        _cancelActiveStroke();
        _startTransformGesture();
        return;
      }
      if (widget.fingerPanEnabled) {
        _panPointer = event.pointer;
        _lastPanPosition = event.localPosition;
        return;
      }
    }
    _startDrawing(
      event.pointer,
      event.kind,
      event.localPosition,
      event.pressure,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length >= 2) {
        _updateTransformGesture();
        return;
      }
      if (event.pointer == _panPointer) {
        final previous = _lastPanPosition;
        _lastPanPosition = event.localPosition;
        if (previous != null) {
          setState(() => _focus -= (event.localPosition - previous) / _scale);
        }
        return;
      }
    }
    if (event.pointer != _drawingPointer) return;
    _appendDrawing(event.localPosition, event.pressure);
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches.remove(event.pointer);
      if (_touches.length < 2) {
        _gestureFocal = null;
        _gestureDistance = null;
      }
    }
    if (event.pointer == _panPointer) {
      _panPointer = null;
      _lastPanPosition = null;
      widget.onViewportChanged(_focus, _scale);
    }
    if (event.pointer == _drawingPointer) {
      _finishDrawing();
    }
    if (_touches.isEmpty && _gestureFocal != null) {
      widget.onViewportChanged(_focus, _scale);
    } else if (_touches.isEmpty) {
      widget.onViewportChanged(_focus, _scale);
    }
  }

  void _startDrawing(
    int pointer,
    PointerDeviceKind kind,
    Offset screenPoint,
    double pressure,
  ) {
    if (_drawingPointer != null) return;
    _drawingPointer = pointer;
    _drawingKind = kind;
    final point = _point(screenPoint, pressure);
    if (widget.tool.type == ToolType.eraser) {
      _erasing = true;
      widget.onEraseStart();
      widget.onEraseAt(point.offset);
      return;
    }
    if (widget.tool.type != ToolType.pen &&
        widget.tool.type != ToolType.highlighter) {
      _drawingPointer = null;
      return;
    }
    setState(() {
      _activeStroke = Stroke(
        id: 'stroke-${DateTime.now().microsecondsSinceEpoch}',
        tool: widget.tool.type,
        color: widget.tool.color,
        width: widget.tool.width,
        points: [point],
      );
    });
  }

  void _appendDrawing(Offset screenPoint, double pressure) {
    final point = _point(screenPoint, pressure);
    if (_erasing) {
      widget.onEraseAt(point.offset);
      return;
    }
    final stroke = _activeStroke;
    if (stroke == null ||
        !StrokeGeometry.shouldAppendPoint(
          stroke.points,
          point,
          minimumDistance: StrokeGeometry.defaultMinimumPointDistance / _scale,
        )) {
      return;
    }
    setState(
      () => _activeStroke = stroke.copyWith(points: [...stroke.points, point]),
    );
  }

  void _finishDrawing() {
    final stroke = _activeStroke;
    final kind = _drawingKind;
    _drawingPointer = null;
    _drawingKind = null;
    if (_erasing) {
      _erasing = false;
      widget.onEraseEnd();
      return;
    }
    if (stroke == null) return;
    setState(() => _activeStroke = null);
    widget.onStrokeComplete(
      applyFingerWritingAssist(
        stroke: stroke,
        pointerKind: kind,
        enabled: widget.fingerWritingAssistEnabled,
      ),
    );
  }

  void _cancelActiveStroke() {
    if (_drawingKind != PointerDeviceKind.touch) return;
    _drawingPointer = null;
    _drawingKind = null;
    if (_erasing) {
      _erasing = false;
      widget.onEraseEnd();
    }
    if (_activeStroke != null) setState(() => _activeStroke = null);
  }

  StrokePoint _point(Offset screenPoint, double pressure) {
    return StrokePoint(
      offset: _screenToWorld(screenPoint, _size),
      pressure: pressure == 0 ? 1 : pressure,
      time: DateTime.now(),
    );
  }

  void _startTransformGesture() {
    final points = _touches.values.take(2).toList();
    _gestureFocal = (points[0] + points[1]) / 2;
    _gestureDistance = (points[0] - points[1]).distance;
  }

  void _updateTransformGesture() {
    final points = _touches.values.take(2).toList();
    final focal = (points[0] + points[1]) / 2;
    final distance = (points[0] - points[1]).distance;
    final oldFocal = _gestureFocal;
    final oldDistance = _gestureDistance;
    if (oldFocal == null || oldDistance == null || oldDistance == 0) {
      _gestureFocal = focal;
      _gestureDistance = distance;
      return;
    }
    final size = _size;
    final anchor = _screenToWorld(oldFocal, size);
    final nextScale = (_scale * distance / oldDistance)
        .clamp(0.2, 6)
        .toDouble();
    setState(() {
      _scale = nextScale;
      _focus = anchor - (focal - size.center(Offset.zero)) / nextScale;
    });
    _gestureFocal = focal;
    _gestureDistance = distance;
  }

  void fitContent(List<Stroke> strokes) {
    if (strokes.isEmpty) {
      setState(() {
        _focus = Offset.zero;
        _scale = 1;
      });
      widget.onViewportChanged(_focus, _scale);
      return;
    }
    final points = strokes.expand((stroke) => stroke.points);
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final point in points) {
      left = math.min(left, point.offset.dx);
      top = math.min(top, point.offset.dy);
      right = math.max(right, point.offset.dx);
      bottom = math.max(bottom, point.offset.dy);
    }
    final bounds = Rect.fromLTRB(left, top, right, bottom).inflate(48);
    final size = _size;
    final nextScale = math
        .min(
          size.width / math.max(bounds.width, 1),
          size.height / math.max(bounds.height, 1),
        )
        .clamp(0.2, 2)
        .toDouble();
    setState(() {
      _focus = bounds.center;
      _scale = nextScale;
    });
    widget.onViewportChanged(_focus, _scale);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const ValueKey('infinite-canvas-viewport'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: CustomPaint(
        painter: _InfiniteCanvasPainter(
          strokes: [...widget.document.strokes, ?_activeStroke],
          background: widget.document.background,
          focus: _focus,
          scale: _scale,
          gridColor: Theme.of(context).colorScheme.outlineVariant,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _InfiniteCanvasPainter extends CustomPainter {
  const _InfiniteCanvasPainter({
    required this.strokes,
    required this.background,
    required this.focus,
    required this.scale,
    required this.gridColor,
  });

  final List<Stroke> strokes;
  final InfiniteCanvasBackground background;
  final Offset focus;
  final double scale;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF8F6F0),
    );
    _drawBackground(canvas, size);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size size) {
    if (background == InfiniteCanvasBackground.blank) return;
    var spacing = 32.0;
    while (spacing * scale < 16) {
      spacing *= 2;
    }
    final halfWorld = Offset(
      size.width / (2 * scale),
      size.height / (2 * scale),
    );
    final left = focus.dx - halfWorld.dx;
    final right = focus.dx + halfWorld.dx;
    final top = focus.dy - halfWorld.dy;
    final bottom = focus.dy + halfWorld.dy;
    final startX = (left / spacing).floor() * spacing;
    final startY = (top / spacing).floor() * spacing;
    final paint = Paint()..color = gridColor.withValues(alpha: 0.55);
    Offset screen(Offset world) =>
        (world - focus) * scale + size.center(Offset.zero);
    if (background == InfiniteCanvasBackground.grid) {
      paint.strokeWidth = 1;
      for (var x = startX; x <= right; x += spacing) {
        final screenX = screen(Offset(x, 0)).dx;
        canvas.drawLine(
          Offset(screenX, 0),
          Offset(screenX, size.height),
          paint,
        );
      }
      for (var y = startY; y <= bottom; y += spacing) {
        final screenY = screen(Offset(0, y)).dy;
        canvas.drawLine(Offset(0, screenY), Offset(size.width, screenY), paint);
      }
      return;
    }
    for (var x = startX; x <= right; x += spacing) {
      for (var y = startY; y <= bottom; y += spacing) {
        canvas.drawCircle(screen(Offset(x, y)), 1.25, paint);
      }
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = stroke.isHighlighter
          ? BlendMode.multiply
          : BlendMode.srcOver;
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first.offset,
        stroke.width * _pressure(stroke.points.first.pressure) / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    for (var index = 1; index < stroke.points.length; index++) {
      final previous = stroke.points[index - 1];
      final current = stroke.points[index];
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            stroke.width *
            (_pressure(previous.pressure) + _pressure(current.pressure)) /
            2;
      canvas.drawLine(previous.offset, current.offset, paint);
    }
  }

  double _pressure(double value) =>
      value <= 0 ? 1 : value.clamp(0.18, 1.35).toDouble();

  @override
  bool shouldRepaint(covariant _InfiniteCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.background != background ||
        oldDelegate.focus != focus ||
        oldDelegate.scale != scale ||
        oldDelegate.gridColor != gridColor;
  }
}
