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

  /// Returns the nearest stroke under [point], or null if nothing is close.
  static String? hitTestNearestStroke(
    Iterable<Stroke> strokes,
    Offset point, {
    double maxDistance = 28,
  }) {
    String? bestId;
    var bestDistance = maxDistance;
    for (final stroke in strokes) {
      final strokeBounds = boundsForStroke(stroke);
      if (strokeBounds == null ||
          !strokeBounds.inflate(maxDistance).contains(point)) {
        continue;
      }
      final distance = _distanceToStroke(stroke, point);
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestId = stroke.id;
      }
    }
    return bestId;
  }

  static List<Offset> rectPolygon(Rect rect) {
    return [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
  }

  static double _distanceToStroke(Stroke stroke, Offset point) {
    if (stroke.points.isEmpty) {
      return double.infinity;
    }
    if (stroke.points.length == 1) {
      return (stroke.points.first.offset - point).distance;
    }
    var best = double.infinity;
    for (var index = 1; index < stroke.points.length; index += 1) {
      final start = stroke.points[index - 1].offset;
      final end = stroke.points[index].offset;
      best = math.min(best, _distanceToSegment(point, start, end));
    }
    return best;
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    if (dx == 0 && dy == 0) {
      return (point - start).distance;
    }
    final t =
        ((point.dx - start.dx) * dx + (point.dy - start.dy) * dy) /
        (dx * dx + dy * dy);
    final clamped = t.clamp(0.0, 1.0).toDouble();
    final projection = Offset(start.dx + dx * clamped, start.dy + dy * clamped);
    return (point - projection).distance;
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
