import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inknest_notes/features/editor/shapes/shape_layer.dart';
import 'package:inknest_notes/features/editor/shapes/shape_recognizer.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    required this.page,
    required this.tool,
    required this.fingerPanEnabled,
    required this.fingerWritingAssistEnabled,
    required this.onStrokeComplete,
    required this.onErase,
    this.onShapeComplete,
    this.onEraseStart,
    this.onEraseEnd,
    this.replayRecordingId,
    this.replayStartedAt,
    this.replayPosition,
  });

  final NotePage page;
  final DrawingTool tool;
  final bool fingerPanEnabled;
  final bool fingerWritingAssistEnabled;
  final ValueChanged<Stroke> onStrokeComplete;
  final ValueChanged<List<StrokePoint>> onErase;
  final ValueChanged<NoteShape>? onShapeComplete;
  final VoidCallback? onEraseStart;
  final VoidCallback? onEraseEnd;
  final String? replayRecordingId;
  final DateTime? replayStartedAt;
  final Duration? replayPosition;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  static const _drawAndHoldDelay = Duration(milliseconds: 500);

  final Set<int> _activePointers = {};
  int? _drawingPointer;
  PointerDeviceKind? _drawingPointerKind;
  Stroke? _activeStroke;
  Timer? _drawAndHoldTimer;
  NoteShape? _heldShapePreview;
  Offset? _heldShapePointer;
  bool _isMultitouch = false;

  bool get _drawAndHoldEnabled =>
      widget.tool.type == ToolType.pen &&
      widget.tool.drawAndHoldShapeEnabled &&
      widget.onShapeComplete != null;

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tool.type != widget.tool.type ||
        oldWidget.tool.drawAndHoldShapeEnabled !=
            widget.tool.drawAndHoldShapeEnabled) {
      _cancelDrawAndHoldPreview();
    }
  }

  @override
  void dispose() {
    _drawAndHoldTimer?.cancel();
    super.dispose();
  }

  void _startStroke(PointerDownEvent event) {
    if (_shouldIgnorePointer(event)) {
      return;
    }

    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _cancelActiveStroke();
      return;
    }

    if (_isMultitouch) {
      return;
    }

    final point = _pointFromEvent(event.localPosition, event.pressure);
    _drawingPointer = event.pointer;
    _drawingPointerKind = event.kind;

    if (widget.tool.type == ToolType.eraser) {
      widget.onEraseStart?.call();
      widget.onErase([point]);
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
    _scheduleDrawAndHold();
  }

  void _appendPoint(PointerMoveEvent event) {
    if (_shouldIgnorePointer(event)) {
      return;
    }

    if (_isMultitouch || event.pointer != _drawingPointer) {
      return;
    }

    if (widget.tool.type == ToolType.eraser) {
      final point = _pointFromEvent(event.localPosition, event.pressure);
      widget.onErase([point]);
      return;
    }

    final activeStroke = _activeStroke;
    if (activeStroke == null) {
      return;
    }

    final point = _pointFromEvent(event.localPosition, event.pressure);
    final heldShape = _heldShapePreview;
    final heldPointer = _heldShapePointer;
    if (heldShape != null && heldPointer != null) {
      setState(() {
        _heldShapePreview = _resizeHeldShape(
          heldShape,
          point.offset - heldPointer,
        );
        _heldShapePointer = point.offset;
      });
      return;
    }
    if (!StrokeGeometry.shouldAppendPoint(activeStroke.points, point)) {
      return;
    }

    setState(() {
      _activeStroke = activeStroke.copyWith(
        points: [...activeStroke.points, point],
      );
    });
    _scheduleDrawAndHold();
  }

  void _endStroke(PointerEvent event) {
    if (_shouldIgnorePointer(event)) {
      return;
    }

    _activePointers.remove(event.pointer);

    if (_isMultitouch) {
      if (_activePointers.isEmpty) {
        _isMultitouch = false;
      }
      return;
    }

    if (event.pointer != _drawingPointer) {
      return;
    }

    final activeStroke = _activeStroke;
    final heldShape = _heldShapePreview;
    final pointerKind = _drawingPointerKind;
    _drawAndHoldTimer?.cancel();
    _drawingPointer = null;
    _drawingPointerKind = null;
    if (widget.tool.type == ToolType.eraser) {
      widget.onEraseEnd?.call();
      return;
    }
    if (activeStroke == null) {
      return;
    }

    setState(() {
      _activeStroke = null;
      _heldShapePreview = null;
      _heldShapePointer = null;
    });

    if (heldShape != null) {
      widget.onShapeComplete?.call(heldShape);
      return;
    }

    if (activeStroke.points.isNotEmpty) {
      widget.onStrokeComplete(
        applyFingerWritingAssist(
          stroke: activeStroke,
          pointerKind: pointerKind,
          enabled: widget.fingerWritingAssistEnabled,
        ),
      );
    }
  }

  bool _shouldIgnorePointer(PointerEvent event) {
    if (widget.tool.type == ToolType.text ||
        widget.tool.type == ToolType.lasso ||
        widget.tool.type == ToolType.shape) {
      return true;
    }

    return widget.fingerPanEnabled && event.kind == PointerDeviceKind.touch;
  }

  void _cancelActiveStroke() {
    if (widget.tool.type == ToolType.eraser && _drawingPointer != null) {
      widget.onEraseEnd?.call();
    }
    _drawingPointer = null;
    _drawingPointerKind = null;
    _isMultitouch = true;
    _drawAndHoldTimer?.cancel();
    _heldShapePreview = null;
    _heldShapePointer = null;

    if (_activeStroke == null) {
      return;
    }

    setState(() {
      _activeStroke = null;
    });
  }

  void _scheduleDrawAndHold() {
    _drawAndHoldTimer?.cancel();
    if (!_drawAndHoldEnabled || _activeStroke == null) {
      return;
    }
    _drawAndHoldTimer = Timer(_drawAndHoldDelay, _recognizeHeldStroke);
  }

  void _recognizeHeldStroke() {
    final stroke = _activeStroke;
    if (!mounted || stroke == null || _drawingPointer == null) {
      return;
    }
    final shape = recognizeHandDrawnShape(
      points: [for (final point in stroke.points) point.offset],
      id: 'shape-${DateTime.now().microsecondsSinceEpoch}',
      color: stroke.color,
      width: stroke.width,
    );
    if (shape == null) {
      return;
    }
    setState(() {
      _heldShapePreview = shape;
      _heldShapePointer = stroke.points.last.offset;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  NoteShape _resizeHeldShape(NoteShape shape, Offset delta) {
    if (shape.type == NoteShapeType.line || shape.type == NoteShapeType.arrow) {
      return shape.copyWith(end: shape.end + delta);
    }
    final oldBounds = shape.bounds;
    final nextEnd = shape.end + delta;
    final nextBounds = Rect.fromPoints(shape.start, nextEnd);
    final nextVertices = shape.vertices.isEmpty || oldBounds.isEmpty
        ? shape.vertices
        : [
            for (final vertex in shape.vertices)
              Offset(
                nextBounds.left +
                    (vertex.dx - oldBounds.left) /
                        oldBounds.width *
                        nextBounds.width,
                nextBounds.top +
                    (vertex.dy - oldBounds.top) /
                        oldBounds.height *
                        nextBounds.height,
              ),
          ];
    return shape.copyWith(end: nextEnd, vertices: nextVertices);
  }

  void _cancelDrawAndHoldPreview() {
    _drawAndHoldTimer?.cancel();
    if (_heldShapePreview == null) {
      return;
    }
    setState(() {
      _heldShapePreview = null;
      _heldShapePointer = null;
    });
  }

  StrokePoint _pointFromEvent(Offset offset, double pressure) {
    return StrokePoint(
      offset: offset,
      pressure: pressure == 0 ? 1 : pressure,
      time: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _startStroke,
      onPointerMove: _appendPoint,
      onPointerUp: _endStroke,
      onPointerCancel: _endStroke,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _StrokePainter(
            strokes: [
              ...widget.page.strokes,
              if (_heldShapePreview == null) ?_activeStroke,
            ],
            heldShapePreview: _heldShapePreview,
            replayRecordingId: widget.replayRecordingId,
            replayStartedAt: widget.replayStartedAt,
            replayPosition: widget.replayPosition,
            replayHighlightColor: Theme.of(context).colorScheme.primary,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

Stroke applyFingerWritingAssist({
  required Stroke stroke,
  required PointerDeviceKind? pointerKind,
  required bool enabled,
}) {
  if (!enabled || pointerKind != PointerDeviceKind.touch) {
    return stroke;
  }

  final smoothedPoints = StrokeGeometry.smoothFingerPoints(stroke.points);
  if (identical(smoothedPoints, stroke.points)) {
    return stroke;
  }
  return stroke.copyWith(points: smoothedPoints);
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.heldShapePreview,
    required this.replayRecordingId,
    required this.replayStartedAt,
    required this.replayPosition,
    required this.replayHighlightColor,
  });

  static const _highlightTrail = Duration(milliseconds: 1200);

  final List<Stroke> strokes;
  final NoteShape? heldShapePreview;
  final String? replayRecordingId;
  final DateTime? replayStartedAt;
  final Duration? replayPosition;
  final Color replayHighlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final highlightedPoints = _highlightedPoints(stroke);
      if (highlightedPoints.isEmpty) {
        continue;
      }

      final highlightWidth = math.max(12.0, stroke.width + 10);
      final highlightPaint = Paint()
        ..color = replayHighlightColor.withValues(alpha: 0.32)
        ..strokeWidth = highlightWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      _drawStroke(canvas, highlightedPoints, highlightWidth, highlightPaint);
    }

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = stroke.isHighlighter
            ? BlendMode.multiply
            : BlendMode.srcOver
        ..style = PaintingStyle.stroke;
      _drawStroke(canvas, stroke.points, stroke.width, paint);
    }
    if (heldShapePreview case final shape?) {
      paintNoteShape(canvas, shape);
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<StrokePoint> points,
    double width,
    Paint paint,
  ) {
    if (points.length == 1) {
      final pointWidth = width * _pressureFactor(points.first.pressure);
      canvas.drawCircle(
        points.first.offset,
        pointWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    // Draw segment-by-segment so local pressure can express brush thickness.
    for (var index = 1; index < points.length; index += 1) {
      final previous = points[index - 1];
      final current = points[index];
      final segmentWidth =
          width *
          ((_pressureFactor(previous.pressure) +
                  _pressureFactor(current.pressure)) /
              2);
      canvas.drawLine(
        previous.offset,
        current.offset,
        Paint()
          ..color = paint.color
          ..strokeWidth = segmentWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = paint.blendMode
          ..style = PaintingStyle.stroke
          ..maskFilter = paint.maskFilter,
      );
    }
  }

  double _pressureFactor(double pressure) {
    if (pressure <= 0) {
      return 1;
    }
    return pressure.clamp(0.18, 1.35).toDouble();
  }

  List<StrokePoint> _highlightedPoints(Stroke stroke) {
    final recordingId = replayRecordingId;
    final startedAt = replayStartedAt;
    final position = replayPosition;
    if (recordingId == null ||
        startedAt == null ||
        position == null ||
        stroke.audioRecordingId != recordingId) {
      return const [];
    }

    final cutoff = startedAt.add(position);
    final visiblePointCount = stroke.points
        .takeWhile((point) => !point.time.isAfter(cutoff))
        .length;
    if (visiblePointCount == 0) {
      return const [];
    }

    final lastVisiblePoint = stroke.points[visiblePointCount - 1];
    if (cutoff.difference(lastVisiblePoint.time) > _highlightTrail) {
      return const [];
    }

    final windowStart = cutoff.subtract(_highlightTrail);
    var startIndex = 0;
    while (startIndex < visiblePointCount &&
        stroke.points[startIndex].time.isBefore(windowStart)) {
      startIndex++;
    }
    if (startIndex > 0) {
      startIndex--;
    }

    return stroke.points.sublist(startIndex, visiblePointCount);
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.heldShapePreview != heldShapePreview ||
        oldDelegate.replayRecordingId != replayRecordingId ||
        oldDelegate.replayStartedAt != replayStartedAt ||
        oldDelegate.replayPosition != replayPosition ||
        oldDelegate.replayHighlightColor != replayHighlightColor;
  }
}
