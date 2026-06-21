import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/tool.dart';

class ShapeLayer extends StatefulWidget {
  const ShapeLayer({
    super.key,
    required this.page,
    required this.tool,
    required this.fingerPanEnabled,
    this.onShapeComplete,
  });

  final NotePage page;
  final DrawingTool tool;
  final bool fingerPanEnabled;
  final ValueChanged<NoteShape>? onShapeComplete;

  @override
  State<ShapeLayer> createState() => _ShapeLayerState();
}

class _ShapeLayerState extends State<ShapeLayer> {
  static const _minimumDragDistance = 8.0;

  final Set<int> _activePointers = {};
  int? _drawingPointer;
  NoteShape? _activeShape;
  bool _isMultitouch = false;

  bool get _isEnabled => widget.onShapeComplete != null;

  @override
  void didUpdateWidget(covariant ShapeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEnabled || oldWidget.tool.shapeType != widget.tool.shapeType) {
      _cancelActiveShape(markMultitouch: false);
    }
  }

  void _startShape(PointerDownEvent event) {
    if (!_isEnabled || _shouldIgnorePointer(event)) {
      return;
    }

    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _cancelActiveShape(markMultitouch: true);
      return;
    }

    if (_isMultitouch) {
      return;
    }

    final start = _clampedPoint(event.localPosition);
    _drawingPointer = event.pointer;
    setState(() {
      _activeShape = NoteShape(
        id: 'shape-${DateTime.now().microsecondsSinceEpoch}',
        type: widget.tool.shapeType,
        start: start,
        end: start,
        color: widget.tool.color,
        width: widget.tool.width,
      );
    });
  }

  void _updateShape(PointerMoveEvent event) {
    if (!_isEnabled || _shouldIgnorePointer(event)) {
      return;
    }

    if (_isMultitouch || event.pointer != _drawingPointer) {
      return;
    }

    final activeShape = _activeShape;
    if (activeShape == null) {
      return;
    }

    setState(() {
      _activeShape = activeShape.copyWith(
        end: _clampedPoint(event.localPosition),
      );
    });
  }

  void _endShape(PointerEvent event) {
    if (!_isEnabled || _shouldIgnorePointer(event)) {
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

    final activeShape = _activeShape;
    _drawingPointer = null;
    if (activeShape == null) {
      return;
    }

    setState(() {
      _activeShape = null;
    });

    final cleanedShape = _cleanedShape(activeShape);
    if (_isValidShape(cleanedShape)) {
      widget.onShapeComplete!(cleanedShape);
    }
  }

  bool _shouldIgnorePointer(PointerEvent event) {
    return widget.fingerPanEnabled && event.kind == PointerDeviceKind.touch;
  }

  Offset _clampedPoint(Offset point) {
    return Offset(
      point.dx.clamp(0.0, widget.page.width).toDouble(),
      point.dy.clamp(0.0, widget.page.height).toDouble(),
    );
  }

  NoteShape _cleanedShape(NoteShape shape) {
    return switch (shape.type) {
      NoteShapeType.line || NoteShapeType.arrow => shape.copyWith(
        end: _snappedLineEnd(shape.start, shape.end),
      ),
      NoteShapeType.rectangle || NoteShapeType.ellipse => shape,
    };
  }

  Offset _snappedLineEnd(Offset start, Offset end) {
    final delta = end - start;
    if (delta.distance < _minimumDragDistance) {
      return end;
    }

    final angle = math.atan2(delta.dy, delta.dx);
    final snapStep = math.pi / 4;
    final snappedAngle = (angle / snapStep).round() * snapStep;
    final angleDelta = _smallestAngleDelta(angle, snappedAngle);
    if (angleDelta > math.pi / 18) {
      return end;
    }

    return start +
        Offset(
          math.cos(snappedAngle) * delta.distance,
          math.sin(snappedAngle) * delta.distance,
        );
  }

  double _smallestAngleDelta(double a, double b) {
    final delta = (a - b).abs() % (math.pi * 2);
    return delta > math.pi ? math.pi * 2 - delta : delta;
  }

  bool _isValidShape(NoteShape shape) {
    return switch (shape.type) {
      NoteShapeType.line || NoteShapeType.arrow =>
        (shape.end - shape.start).distance >= _minimumDragDistance,
      NoteShapeType.rectangle || NoteShapeType.ellipse =>
        shape.bounds.width >= _minimumDragDistance &&
            shape.bounds.height >= _minimumDragDistance,
    };
  }

  void _cancelActiveShape({required bool markMultitouch}) {
    _drawingPointer = null;
    _isMultitouch = markMultitouch;
    if (!markMultitouch) {
      _activePointers.clear();
    }

    if (_activeShape == null) {
      return;
    }

    setState(() {
      _activeShape = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final painter = _ShapePainter(
      shapes: [...widget.page.shapes, ?_activeShape],
      minimumStrokeWidth: 0,
    );

    return IgnorePointer(
      ignoring: !_isEnabled,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _startShape,
        onPointerMove: _updateShape,
        onPointerUp: _endShape,
        onPointerCancel: _endShape,
        child: RepaintBoundary(
          child: CustomPaint(painter: painter, child: const SizedBox.expand()),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter({required this.shapes, required this.minimumStrokeWidth});

  final List<NoteShape> shapes;
  final double minimumStrokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      paintNoteShape(canvas, shape, minimumStrokeWidth: minimumStrokeWidth);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) {
    return oldDelegate.shapes != shapes ||
        oldDelegate.minimumStrokeWidth != minimumStrokeWidth;
  }
}

void paintNoteShape(
  Canvas canvas,
  NoteShape shape, {
  double minimumStrokeWidth = 0,
}) {
  final strokeWidth = math.max(shape.width, minimumStrokeWidth);
  final paint = Paint()
    ..color = shape.color
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  switch (shape.type) {
    case NoteShapeType.line:
      canvas.drawLine(shape.start, shape.end, paint);
      break;
    case NoteShapeType.arrow:
      canvas.drawLine(shape.start, shape.end, paint);
      _paintArrowHead(canvas, shape.start, shape.end, paint);
      break;
    case NoteShapeType.rectangle:
      canvas.drawRect(shape.bounds, paint);
      break;
    case NoteShapeType.ellipse:
      canvas.drawOval(shape.bounds, paint);
      break;
  }
}

void _paintArrowHead(Canvas canvas, Offset start, Offset end, Paint paint) {
  final delta = end - start;
  if (delta.distance <= 0) {
    return;
  }

  final angle = math.atan2(delta.dy, delta.dx);
  final headLength = math.max(14.0, paint.strokeWidth * 4);
  const spread = math.pi / 7;
  final left =
      end -
      Offset(
        math.cos(angle - spread) * headLength,
        math.sin(angle - spread) * headLength,
      );
  final right =
      end -
      Offset(
        math.cos(angle + spread) * headLength,
        math.sin(angle + spread) * headLength,
      );

  canvas
    ..drawLine(end, left, paint)
    ..drawLine(end, right, paint);
}
