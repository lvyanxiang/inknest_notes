import 'dart:math' as math;
import 'dart:ui';

import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';

class StrokeGeometry {
  const StrokeGeometry._();

  static const defaultMinimumPointDistance = 1.4;

  static bool shouldAppendPoint(
    List<StrokePoint> points,
    StrokePoint point, {
    double minimumDistance = defaultMinimumPointDistance,
  }) {
    if (points.isEmpty) {
      return true;
    }

    return (points.last.offset - point.offset).distance >= minimumDistance;
  }

  static Path buildSmoothPath(List<StrokePoint> points) {
    return buildSmoothPathFromOffsets([
      for (final point in points) point.offset,
    ]);
  }

  static Path buildSmoothPathFromOffsets(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) {
      return path;
    }

    path.moveTo(points.first.dx, points.first.dy);
    for (final segment in buildSmoothSegments(points)) {
      final control = segment.control;
      if (control == null) {
        path.lineTo(segment.end.dx, segment.end.dy);
      } else {
        path.quadraticBezierTo(
          control.dx,
          control.dy,
          segment.end.dx,
          segment.end.dy,
        );
      }
    }

    return path;
  }

  static List<SmoothStrokeSegment> buildSmoothSegments(List<Offset> points) {
    if (points.length < 2) {
      return const [];
    }

    if (points.length == 2) {
      return [SmoothStrokeSegment.lineTo(points.last)];
    }

    final segments = <SmoothStrokeSegment>[];
    for (var index = 1; index < points.length - 1; index++) {
      final midpoint = Offset(
        (points[index].dx + points[index + 1].dx) / 2,
        (points[index].dy + points[index + 1].dy) / 2,
      );
      segments.add(
        SmoothStrokeSegment.quadraticTo(control: points[index], end: midpoint),
      );
    }
    segments.add(SmoothStrokeSegment.lineTo(points.last));

    return segments;
  }

  static List<Stroke> eraseStrokes({
    required List<Stroke> strokes,
    required List<StrokePoint> eraserPoints,
    required double radius,
  }) {
    if (strokes.isEmpty || eraserPoints.isEmpty || radius <= 0) {
      return strokes;
    }

    var didChange = false;
    final updatedStrokes = <Stroke>[];
    for (final stroke in strokes) {
      final erasedStrokeParts = _eraseStroke(
        stroke: stroke,
        eraserPoints: eraserPoints,
        radius: radius,
      );
      final isUnchanged =
          erasedStrokeParts.length == 1 &&
          identical(erasedStrokeParts.first, stroke);
      didChange = didChange || !isUnchanged;
      updatedStrokes.addAll(erasedStrokeParts);
    }

    return didChange ? updatedStrokes : strokes;
  }

  static List<Stroke> _eraseStroke({
    required Stroke stroke,
    required List<StrokePoint> eraserPoints,
    required double radius,
  }) {
    if (stroke.points.isEmpty) {
      return [stroke];
    }

    if (stroke.points.length == 1) {
      return _pointIntersectsEraser(
            stroke.points.single.offset,
            eraserPoints,
            radius,
          )
          ? const []
          : [stroke];
    }

    var didHit = false;
    final segments = <List<StrokePoint>>[];
    var currentSegment = <StrokePoint>[];

    void flushSegment() {
      if (currentSegment.length >= 2) {
        segments.add(currentSegment);
      }
      currentSegment = <StrokePoint>[];
    }

    for (var index = 0; index < stroke.points.length; index++) {
      final point = stroke.points[index];
      final isPointHit = _pointIntersectsEraser(
        point.offset,
        eraserPoints,
        radius,
      );

      if (isPointHit) {
        didHit = true;
        flushSegment();
        continue;
      }

      if (currentSegment.isEmpty) {
        currentSegment.add(point);
        continue;
      }

      final previousPoint = stroke.points[index - 1];
      final isSegmentHit = _segmentIntersectsEraser(
        start: previousPoint.offset,
        end: point.offset,
        eraserPoints: eraserPoints,
        radius: radius,
      );

      if (isSegmentHit) {
        didHit = true;
        flushSegment();
        currentSegment.add(point);
      } else {
        currentSegment.add(point);
      }
    }

    flushSegment();

    if (!didHit) {
      return [stroke];
    }

    return [
      for (final (index, segment) in segments.indexed)
        Stroke(
          id: '${stroke.id}-part-$index',
          tool: stroke.tool,
          color: stroke.color,
          width: stroke.width,
          points: segment,
        ),
    ];
  }

  static bool _pointIntersectsEraser(
    Offset point,
    List<StrokePoint> eraserPoints,
    double radius,
  ) {
    for (final eraserPoint in eraserPoints) {
      if ((point - eraserPoint.offset).distance <= radius) {
        return true;
      }
    }

    return false;
  }

  static bool _segmentIntersectsEraser({
    required Offset start,
    required Offset end,
    required List<StrokePoint> eraserPoints,
    required double radius,
  }) {
    for (final eraserPoint in eraserPoints) {
      if (_distanceToSegment(eraserPoint.offset, start, end) <= radius) {
        return true;
      }
    }

    return false;
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared == 0) {
      return (point - start).distance;
    }

    final t =
        ((point.dx - start.dx) * segment.dx +
            (point.dy - start.dy) * segment.dy) /
        lengthSquared;
    final clampedT = math.max(0.0, math.min(1.0, t));
    final projection = Offset(
      start.dx + segment.dx * clampedT,
      start.dy + segment.dy * clampedT,
    );

    return (point - projection).distance;
  }
}

class SmoothStrokeSegment {
  const SmoothStrokeSegment.lineTo(this.end) : control = null;

  const SmoothStrokeSegment.quadraticTo({
    required this.control,
    required this.end,
  });

  final Offset? control;
  final Offset end;
}
