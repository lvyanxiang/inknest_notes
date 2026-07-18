import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:inknest_notes/models/note_page.dart';
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
    required this.onStrokeComplete,
    required this.onErase,
    this.replayRecordingId,
    this.replayStartedAt,
    this.replayPosition,
  });

  final NotePage page;
  final DrawingTool tool;
  final bool fingerPanEnabled;
  final ValueChanged<Stroke> onStrokeComplete;
  final ValueChanged<List<StrokePoint>> onErase;
  final String? replayRecordingId;
  final DateTime? replayStartedAt;
  final Duration? replayPosition;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  final Set<int> _activePointers = {};
  int? _drawingPointer;
  Stroke? _activeStroke;
  bool _isMultitouch = false;

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

    if (widget.tool.type == ToolType.eraser) {
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
    if (!StrokeGeometry.shouldAppendPoint(activeStroke.points, point)) {
      return;
    }

    setState(() {
      _activeStroke = activeStroke.copyWith(
        points: [...activeStroke.points, point],
      );
    });
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
    _drawingPointer = null;
    if (activeStroke == null) {
      return;
    }

    setState(() {
      _activeStroke = null;
    });

    if (activeStroke.points.isNotEmpty) {
      widget.onStrokeComplete(activeStroke);
    }
  }

  bool _shouldIgnorePointer(PointerEvent event) {
    if (widget.tool.type == ToolType.text ||
        widget.tool.type == ToolType.smartInk ||
        widget.tool.type == ToolType.shape) {
      return true;
    }

    return widget.fingerPanEnabled && event.kind == PointerDeviceKind.touch;
  }

  void _cancelActiveStroke() {
    _drawingPointer = null;
    _isMultitouch = true;

    if (_activeStroke == null) {
      return;
    }

    setState(() {
      _activeStroke = null;
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
            strokes: [...widget.page.strokes, ?_activeStroke],
            replayRecordingId: widget.replayRecordingId,
            replayStartedAt: widget.replayStartedAt,
            replayPosition: widget.replayPosition,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.replayRecordingId,
    required this.replayStartedAt,
    required this.replayPosition,
  });

  final List<Stroke> strokes;
  final String? replayRecordingId;
  final DateTime? replayStartedAt;
  final Duration? replayPosition;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final points = _visiblePoints(stroke);
      if (points.isEmpty) {
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

      if (points.length == 1) {
        canvas.drawCircle(
          points.first.offset,
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }

      canvas.drawPath(StrokeGeometry.buildSmoothPath(points), paint);
    }
  }

  List<StrokePoint> _visiblePoints(Stroke stroke) {
    final recordingId = replayRecordingId;
    final startedAt = replayStartedAt;
    final position = replayPosition;
    if (recordingId == null ||
        startedAt == null ||
        position == null ||
        stroke.audioRecordingId != recordingId) {
      return stroke.points;
    }

    final cutoff = startedAt.add(position);
    return stroke.points
        .takeWhile((point) => !point.time.isAfter(cutoff))
        .toList();
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.replayRecordingId != replayRecordingId ||
        oldDelegate.replayStartedAt != replayStartedAt ||
        oldDelegate.replayPosition != replayPosition;
  }
}
