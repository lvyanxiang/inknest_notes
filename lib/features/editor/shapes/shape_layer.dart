import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/features/editor/shapes/shape_recognizer.dart';

class ShapeLayer extends StatefulWidget {
  const ShapeLayer({
    super.key,
    required this.page,
    required this.tool,
    required this.fingerPanEnabled,
    this.onShapeComplete,
    this.onStrokeFallback,
  });

  final NotePage page;
  final DrawingTool tool;
  final bool fingerPanEnabled;
  final ValueChanged<NoteShape>? onShapeComplete;
  final ValueChanged<Stroke>? onStrokeFallback;

  @override
  State<ShapeLayer> createState() => _ShapeLayerState();
}

class _ShapeLayerState extends State<ShapeLayer> {
  static const _minimumDragDistance = 8.0;

  final Set<int> _activePointers = {};
  int? _drawingPointer;
  NoteShape? _activeShape;
  final List<StrokePoint> _activePath = [];
  bool _isMultitouch = false;

  bool get _isEnabled =>
      widget.onShapeComplete != null || widget.onStrokeFallback != null;

  @override
  void didUpdateWidget(covariant ShapeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEnabled ||
        oldWidget.tool.shapeType != widget.tool.shapeType ||
        oldWidget.tool.shapeCreationMode != widget.tool.shapeCreationMode) {
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
    _activePath
      ..clear()
      ..add(_pointFromEvent(start, event.pressure));
    if (widget.tool.shapeCreationMode == ShapeCreationMode.auto) {
      setState(() => _activeShape = null);
    } else {
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
  }

  void _updateShape(PointerMoveEvent event) {
    if (!_isEnabled || _shouldIgnorePointer(event)) {
      return;
    }

    if (_isMultitouch || event.pointer != _drawingPointer) {
      return;
    }

    final activeShape = _activeShape;
    final point = _pointFromEvent(
      _clampedPoint(event.localPosition),
      event.pressure,
    );
    if (_activePath.isEmpty ||
        (point.offset - _activePath.last.offset).distance >= 1) {
      _activePath.add(point);
    }
    if (widget.tool.shapeCreationMode == ShapeCreationMode.auto) {
      setState(() {});
      return;
    }
    if (activeShape == null) {
      return;
    }

    setState(() {
      _activeShape = activeShape.copyWith(end: point.offset);
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
    final finalPoint = _pointFromEvent(
      _clampedPoint(event.localPosition),
      event.pressure,
    );
    if (_activePath.isEmpty ||
        (finalPoint.offset - _activePath.last.offset).distance >= 1) {
      _activePath.add(finalPoint);
    }
    _drawingPointer = null;
    if (widget.tool.shapeCreationMode == ShapeCreationMode.auto) {
      setState(() => _activeShape = null);
      final points = [for (final point in _activePath) point.offset];
      final recognized = recognizeHandDrawnShape(
        points: points,
        id: 'shape-${DateTime.now().microsecondsSinceEpoch}',
        color: widget.tool.color,
        width: widget.tool.width,
      );
      if (recognized != null) {
        widget.onShapeComplete?.call(recognized);
      } else if (points.length >= 2) {
        widget.onStrokeFallback?.call(
          Stroke(
            id: 'stroke-${DateTime.now().microsecondsSinceEpoch}',
            tool: ToolType.pen,
            color: widget.tool.color,
            width: widget.tool.width,
            points: List<StrokePoint>.from(_activePath),
          ),
        );
      }
      _activePath.clear();
      return;
    }
    if (activeShape == null) {
      return;
    }

    setState(() {
      _activeShape = null;
    });
    _activePath.clear();

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
      NoteShapeType.rectangle ||
      NoteShapeType.ellipse ||
      NoteShapeType.triangle ||
      NoteShapeType.diamond ||
      NoteShapeType.polygon => shape,
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
      NoteShapeType.triangle =>
        shape.bounds.width >= _minimumDragDistance &&
            shape.bounds.height >= _minimumDragDistance,
      NoteShapeType.diamond || NoteShapeType.polygon =>
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
      _activePath.clear();
      return;
    }

    setState(() {
      _activeShape = null;
    });
    _activePath.clear();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _ShapePainter(
      shapes: [...widget.page.shapes, ?_activeShape],
      minimumStrokeWidth: 0,
      previewPath: widget.tool.shapeCreationMode == ShapeCreationMode.auto
          ? [for (final point in _activePath) point.offset]
          : const [],
      previewColor: widget.tool.color,
      previewWidth: widget.tool.width,
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
  const _ShapePainter({
    required this.shapes,
    required this.minimumStrokeWidth,
    required this.previewPath,
    required this.previewColor,
    required this.previewWidth,
  });

  final List<NoteShape> shapes;
  final double minimumStrokeWidth;
  final List<Offset> previewPath;
  final Color previewColor;
  final double previewWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      paintNoteShape(canvas, shape, minimumStrokeWidth: minimumStrokeWidth);
    }
    if (previewPath.length > 1) {
      final path = Path()..moveTo(previewPath.first.dx, previewPath.first.dy);
      for (final point in previewPath.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = previewColor
          ..strokeWidth = previewWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) {
    return oldDelegate.shapes != shapes ||
        oldDelegate.minimumStrokeWidth != minimumStrokeWidth ||
        oldDelegate.previewPath != previewPath ||
        oldDelegate.previewColor != previewColor ||
        oldDelegate.previewWidth != previewWidth;
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
    case NoteShapeType.triangle:
      final bounds = shape.bounds;
      final path = Path()
        ..moveTo(bounds.center.dx, bounds.top)
        ..lineTo(bounds.right, bounds.bottom)
        ..lineTo(bounds.left, bounds.bottom)
        ..close();
      canvas.drawPath(path, paint);
      break;
    case NoteShapeType.diamond:
      final bounds = shape.bounds;
      final path = Path()
        ..moveTo(bounds.center.dx, bounds.top)
        ..lineTo(bounds.right, bounds.center.dy)
        ..lineTo(bounds.center.dx, bounds.bottom)
        ..lineTo(bounds.left, bounds.center.dy)
        ..close();
      canvas.drawPath(path, paint);
      break;
    case NoteShapeType.polygon:
      final vertices = shape.vertices.isNotEmpty
          ? shape.vertices
          : _regularPolygonVertices(shape.bounds, 5);
      if (vertices.isEmpty) {
        break;
      }
      final path = Path()..moveTo(vertices.first.dx, vertices.first.dy);
      for (final vertex in vertices.skip(1)) {
        path.lineTo(vertex.dx, vertex.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
      break;
  }
}

List<Offset> _regularPolygonVertices(Rect bounds, int sides) {
  if (bounds.isEmpty || sides < 3) {
    return const [];
  }
  final radiusX = bounds.width / 2;
  final radiusY = bounds.height / 2;
  return [
    for (var index = 0; index < sides; index++)
      Offset(
        bounds.center.dx +
            math.cos(-math.pi / 2 + math.pi * 2 * index / sides) * radiusX,
        bounds.center.dy +
            math.sin(-math.pi / 2 + math.pi * 2 * index / sides) * radiusY,
      ),
  ];
}

StrokePoint _pointFromEvent(Offset offset, double pressure) {
  return StrokePoint(
    offset: offset,
    pressure: pressure == 0 ? 1 : pressure,
    time: DateTime.now(),
  );
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
