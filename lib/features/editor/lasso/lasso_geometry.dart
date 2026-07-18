import 'dart:math' as math;
import 'dart:ui';

import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';

class LassoGeometry {
  const LassoGeometry._();

  static Set<String> selectStrokeIds(
    Iterable<Stroke> strokes,
    List<Offset> polygon,
  ) {
    if (polygon.length < 3) {
      return const {};
    }

    final polygonBounds = _boundsForOffsets(polygon);
    return {
      for (final stroke in strokes)
        if (_strokeIntersectsPolygon(stroke, polygon, polygonBounds)) stroke.id,
    };
  }

  static Rect? boundsForStrokes(Iterable<Stroke> strokes) {
    Rect? bounds;
    for (final stroke in strokes) {
      final strokeBounds = boundsForStroke(stroke);
      if (strokeBounds == null) {
        continue;
      }
      bounds = bounds == null
          ? strokeBounds
          : bounds.expandToInclude(strokeBounds);
    }
    return bounds;
  }

  static Rect? boundsForStroke(Stroke stroke) {
    if (stroke.points.isEmpty) {
      return null;
    }

    final pointBounds = _boundsForOffsets([
      for (final point in stroke.points) point.offset,
    ]);
    return pointBounds.inflate(math.max(stroke.width / 2, 4));
  }

  static List<Stroke> translateStrokes(Iterable<Stroke> strokes, Offset delta) {
    return [
      for (final stroke in strokes)
        stroke.copyWith(
          points: [
            for (final point in stroke.points)
              StrokePoint(
                offset: point.offset + delta,
                pressure: point.pressure,
                time: point.time,
              ),
          ],
        ),
    ];
  }

  static List<Stroke> scaleStrokes(
    Iterable<Stroke> strokes, {
    required Offset anchor,
    required double scale,
  }) {
    return [
      for (final stroke in strokes)
        stroke.copyWith(
          width: stroke.width * scale,
          points: [
            for (final point in stroke.points)
              StrokePoint(
                offset: anchor + (point.offset - anchor) * scale,
                pressure: point.pressure,
                time: point.time,
              ),
          ],
        ),
    ];
  }

  static bool _strokeIntersectsPolygon(
    Stroke stroke,
    List<Offset> polygon,
    Rect polygonBounds,
  ) {
    final strokeBounds = boundsForStroke(stroke);
    if (strokeBounds == null || !strokeBounds.overlaps(polygonBounds)) {
      return false;
    }

    if (stroke.points.any((point) => _pointInPolygon(point.offset, polygon))) {
      return true;
    }
    if (_pointInPolygon(strokeBounds.center, polygon) ||
        polygon.any(strokeBounds.contains)) {
      return true;
    }

    for (
      var strokeIndex = 1;
      strokeIndex < stroke.points.length;
      strokeIndex++
    ) {
      final strokeStart = stroke.points[strokeIndex - 1].offset;
      final strokeEnd = stroke.points[strokeIndex].offset;
      for (
        var polygonIndex = 0;
        polygonIndex < polygon.length;
        polygonIndex++
      ) {
        final polygonStart = polygon[polygonIndex];
        final polygonEnd = polygon[(polygonIndex + 1) % polygon.length];
        if (_segmentsIntersect(
          strokeStart,
          strokeEnd,
          polygonStart,
          polygonEnd,
        )) {
          return true;
        }
      }
    }

    return false;
  }

  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final currentPoint = polygon[index];
      final previousPoint = polygon[previous];
      final crossesY =
          (currentPoint.dy > point.dy) != (previousPoint.dy > point.dy);
      if (!crossesY) {
        continue;
      }
      final intersectionX =
          (previousPoint.dx - currentPoint.dx) *
              (point.dy - currentPoint.dy) /
              (previousPoint.dy - currentPoint.dy) +
          currentPoint.dx;
      if (point.dx < intersectionX) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool _segmentsIntersect(
    Offset firstStart,
    Offset firstEnd,
    Offset secondStart,
    Offset secondEnd,
  ) {
    final firstA = _orientation(firstStart, firstEnd, secondStart);
    final firstB = _orientation(firstStart, firstEnd, secondEnd);
    final secondA = _orientation(secondStart, secondEnd, firstStart);
    final secondB = _orientation(secondStart, secondEnd, firstEnd);

    if (firstA * firstB < 0 && secondA * secondB < 0) {
      return true;
    }

    const epsilon = 0.000001;
    return (firstA.abs() < epsilon &&
            _pointOnSegment(secondStart, firstStart, firstEnd)) ||
        (firstB.abs() < epsilon &&
            _pointOnSegment(secondEnd, firstStart, firstEnd)) ||
        (secondA.abs() < epsilon &&
            _pointOnSegment(firstStart, secondStart, secondEnd)) ||
        (secondB.abs() < epsilon &&
            _pointOnSegment(firstEnd, secondStart, secondEnd));
  }

  static double _orientation(Offset start, Offset end, Offset point) {
    return (end.dx - start.dx) * (point.dy - start.dy) -
        (end.dy - start.dy) * (point.dx - start.dx);
  }

  static bool _pointOnSegment(Offset point, Offset start, Offset end) {
    const epsilon = 0.000001;
    return point.dx >= math.min(start.dx, end.dx) - epsilon &&
        point.dx <= math.max(start.dx, end.dx) + epsilon &&
        point.dy >= math.min(start.dy, end.dy) - epsilon &&
        point.dy <= math.max(start.dy, end.dy) + epsilon;
  }

  static Rect _boundsForOffsets(List<Offset> offsets) {
    var left = offsets.first.dx;
    var top = offsets.first.dy;
    var right = left;
    var bottom = top;
    for (final offset in offsets.skip(1)) {
      left = math.min(left, offset.dx);
      top = math.min(top, offset.dy);
      right = math.max(right, offset.dx);
      bottom = math.max(bottom, offset.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
