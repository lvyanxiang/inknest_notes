import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:inknest_notes/models/note_audio_recording.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_audio_timeline.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    required this.page,
    required this.tool,
    required this.fingerPanEnabled,
    this.playbackRecording,
    this.playbackPosition = Duration.zero,
    this.playbackHighlightColor = const Color(0xFF2F6F73),
    required this.onStrokeComplete,
    required this.onErase,
  });

  final NotePage page;
  final DrawingTool tool;
  final bool fingerPanEnabled;
  final NoteAudioRecording? playbackRecording;
  final Duration playbackPosition;
  final Color playbackHighlightColor;
  final ValueChanged<Stroke> onStrokeComplete;
  final ValueChanged<List<StrokePoint>> onErase;

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
            playbackRecording: widget.playbackRecording,
            playbackPosition: widget.playbackPosition,
            playbackHighlightColor: widget.playbackHighlightColor,
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
    required this.playbackRecording,
    required this.playbackPosition,
    required this.playbackHighlightColor,
  });

  final List<Stroke> strokes;
  final NoteAudioRecording? playbackRecording;
  final Duration playbackPosition;
  final Color playbackHighlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final playbackState = playbackRecording == null
          ? StrokeAudioPlaybackState.unlinked
          : StrokeAudioTimeline.stateFor(
              stroke: stroke,
              recording: playbackRecording!,
              playbackPosition: playbackPosition,
            );
      if (playbackState == StrokeAudioPlaybackState.current) {
        _drawStroke(
          canvas,
          stroke,
          Paint()
            ..color = playbackHighlightColor.withValues(alpha: 0.28)
            ..strokeWidth = stroke.width + 8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..blendMode = BlendMode.srcOver
            ..style = PaintingStyle.stroke,
        );
      }

      final paint = Paint()
        ..color = playbackState == StrokeAudioPlaybackState.upcoming
            ? stroke.color.withValues(alpha: 0.18)
            : stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = stroke.isHighlighter
            ? BlendMode.multiply
            : BlendMode.srcOver
        ..style = PaintingStyle.stroke;

      _drawStroke(canvas, stroke, paint);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke, Paint paint) {
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first.offset,
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    canvas.drawPath(StrokeGeometry.buildSmoothPath(stroke.points), paint);
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.playbackRecording?.id != playbackRecording?.id ||
        oldDelegate.playbackPosition != playbackPosition ||
        oldDelegate.playbackHighlightColor != playbackHighlightColor;
  }
}
