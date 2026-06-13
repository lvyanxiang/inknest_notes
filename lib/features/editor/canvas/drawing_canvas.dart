import 'package:flutter/material.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    required this.page,
    required this.tool,
    required this.onStrokeComplete,
  });

  final NotePage page;
  final DrawingTool tool;
  final ValueChanged<Stroke> onStrokeComplete;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Stroke? _activeStroke;

  void _startStroke(PointerDownEvent event) {
    final point = _pointFromEvent(event.localPosition, event.pressure);

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
    final activeStroke = _activeStroke;
    if (activeStroke == null) {
      return;
    }

    setState(() {
      _activeStroke = activeStroke.copyWith(
        points: [
          ...activeStroke.points,
          _pointFromEvent(event.localPosition, event.pressure),
        ],
      );
    });
  }

  void _endStroke() {
    final activeStroke = _activeStroke;
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
      onPointerUp: (_) => _endStroke(),
      onPointerCancel: (_) => _endStroke(),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _StrokePainter(
            strokes: [...widget.page.strokes, ?_activeStroke],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({required this.strokes});

  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first.offset,
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }

      final path = Path()
        ..moveTo(stroke.points.first.offset.dx, stroke.points.first.offset.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.offset.dx, point.offset.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}
