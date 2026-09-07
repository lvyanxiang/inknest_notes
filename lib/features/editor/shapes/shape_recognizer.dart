import 'dart:math' as math;
import 'dart:ui';

import 'package:inknest_notes/models/note_shape.dart';

/// Converts one freehand path into a small set of predictable geometric
/// primitives. This deliberately stays local and deterministic so shape
/// recognition never blocks writing on a network or ML request.
NoteShape? recognizeHandDrawnShape({
  required List<Offset> points,
  required String id,
  required Color color,
  required double width,
}) {
  final cleaned = _removeNearDuplicates(points);
  if (cleaned.length < 2) {
    return null;
  }

  final bounds = _boundsFor(cleaned);
  final diagonal = math.max(1.0, bounds.longestSide);
  final pathLength = _pathLength(cleaned);
  if (pathLength < 24) {
    return null;
  }

  final closureDistance = (cleaned.first - cleaned.last).distance;
  final isClosed =
      cleaned.length >= 4 && closureDistance <= math.max(18, diagonal * 0.18);

  if (isClosed) {
    final corners = _simplifyClosed(cleaned, math.max(3, diagonal * 0.035));
    if (corners.length == 3) {
      return _shape(
        id: id,
        type: NoteShapeType.triangle,
        bounds: bounds,
        color: color,
        width: width,
      );
    }
    if (corners.length == 4 && _looksDiamond(corners, bounds)) {
      return _shape(
        id: id,
        type: NoteShapeType.diamond,
        bounds: bounds,
        color: color,
        width: width,
      );
    }
    if (corners.length == 4 && _looksRectangular(corners)) {
      return _shape(
        id: id,
        type: NoteShapeType.rectangle,
        bounds: bounds,
        color: color,
        width: width,
      );
    }
    if (corners.length >= 4 &&
        corners.length <= 8 &&
        _looksPolygonal(corners)) {
      return _shape(
        id: id,
        type: NoteShapeType.polygon,
        bounds: bounds,
        color: color,
        width: width,
        vertices: corners,
      );
    }
    if (corners.length >= 5 || !_looksRectangular(corners)) {
      return _shape(
        id: id,
        type: NoteShapeType.ellipse,
        bounds: bounds,
        color: color,
        width: width,
      );
    }
  }

  final arrow = _recognizeArrow(
    cleaned,
    id: id,
    color: color,
    width: width,
    diagonal: diagonal,
  );
  if (arrow != null) {
    return arrow;
  }

  final start = cleaned.first;
  final end = cleaned.last;
  final directDistance = (end - start).distance;
  final straightness = directDistance / pathLength;
  final deviation = _maximumDistanceFromSegment(cleaned, start, end);
  if (directDistance >= 24 &&
      straightness >= 0.86 &&
      deviation <= math.max(10, directDistance * 0.12)) {
    return NoteShape(
      id: id,
      type: NoteShapeType.line,
      start: start,
      end: end,
      color: color,
      width: width,
    );
  }

  return null;
}

NoteShape _shape({
  required String id,
  required NoteShapeType type,
  required Rect bounds,
  required Color color,
  required double width,
  List<Offset> vertices = const [],
}) {
  return NoteShape(
    id: id,
    type: type,
    start: bounds.topLeft,
    end: bounds.bottomRight,
    color: color,
    width: width,
    vertices: vertices,
  );
}

NoteShape? _recognizeArrow(
  List<Offset> points, {
  required String id,
  required Color color,
  required double width,
  required double diagonal,
}) {
  final simplified = _rdp(points, math.max(3, diagonal * 0.035));
  if (simplified.length < 4 || simplified.length > 7) {
    return null;
  }

  final tail = simplified.first;
  var tipIndex = 1;
  var shaftLength = 0.0;
  for (var index = 1; index < simplified.length; index++) {
    final distance = (simplified[index] - tail).distance;
    if (distance > shaftLength) {
      shaftLength = distance;
      tipIndex = index;
    }
  }
  if (tipIndex == simplified.length - 1 || shaftLength < 36) {
    return null;
  }

  final shaftPathLength = _pathLength(simplified.sublist(0, tipIndex + 1));
  if (shaftPathLength / shaftLength > 1.2) {
    return null;
  }

  final tip = simplified[tipIndex];
  final headPoints = simplified.sublist(tipIndex + 1);
  final usableHeadPoints = [
    for (final point in headPoints)
      if ((point - tip).distance >= shaftLength * 0.08 &&
          (point - tip).distance <= shaftLength * 0.5)
        point,
  ];
  if (usableHeadPoints.length < 2) {
    return null;
  }

  return NoteShape(
    id: id,
    type: NoteShapeType.arrow,
    start: tail,
    end: tip,
    color: color,
    width: width,
  );
}

List<Offset> _removeNearDuplicates(List<Offset> points) {
  final cleaned = <Offset>[];
  for (final point in points) {
    if (cleaned.isEmpty || (point - cleaned.last).distance >= 1) {
      cleaned.add(point);
    }
  }
  return cleaned;
}

double _pathLength(List<Offset> points) {
  var length = 0.0;
  for (var index = 1; index < points.length; index++) {
    length += (points[index] - points[index - 1]).distance;
  }
  return length;
}

Rect _boundsFor(List<Offset> points) {
  var bounds = Rect.fromCircle(center: points.first, radius: 0);
  for (final point in points.skip(1)) {
    bounds = bounds.expandToInclude(Rect.fromCircle(center: point, radius: 0));
  }
  return bounds;
}

List<Offset> _simplifyClosed(List<Offset> points, double epsilon) {
  final closed = List<Offset>.from(points);
  if ((closed.first - closed.last).distance > epsilon) {
    closed.add(closed.first);
  }
  final simplified = _rdp(closed, epsilon);
  if (simplified.length > 1 &&
      (simplified.first - simplified.last).distance <= epsilon * 1.5) {
    simplified.removeLast();
  }
  return simplified;
}

List<Offset> _rdp(List<Offset> points, double epsilon) {
  if (points.length <= 2) {
    return List<Offset>.from(points);
  }

  var maxDistance = 0.0;
  var splitIndex = 0;
  for (var index = 1; index < points.length - 1; index++) {
    final distance = _distanceToSegment(
      points[index],
      points.first,
      points.last,
    );
    if (distance > maxDistance) {
      maxDistance = distance;
      splitIndex = index;
    }
  }
  if (maxDistance <= epsilon) {
    return [points.first, points.last];
  }

  final left = _rdp(points.sublist(0, splitIndex + 1), epsilon);
  final right = _rdp(points.sublist(splitIndex), epsilon);
  return [...left.take(left.length - 1), ...right];
}

bool _looksRectangular(List<Offset> corners) {
  if (corners.length < 4) {
    return false;
  }
  for (var index = 0; index < corners.length; index++) {
    final previous = corners[(index - 1 + corners.length) % corners.length];
    final current = corners[index];
    final next = corners[(index + 1) % corners.length];
    final incoming = previous - current;
    final outgoing = next - current;
    if (incoming.distance < 1 || outgoing.distance < 1) {
      return false;
    }
    final cosine =
        (incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
        (incoming.distance * outgoing.distance);
    final angle = math.acos(cosine.clamp(-1.0, 1.0));
    if ((angle - math.pi / 2).abs() > math.pi / 5) {
      return false;
    }
  }
  return true;
}

bool _looksDiamond(List<Offset> corners, Rect bounds) {
  if (corners.length != 4 || bounds.width < 1 || bounds.height < 1) {
    return false;
  }
  for (final corner in corners) {
    final normalizedX =
        (corner.dx - bounds.center.dx).abs() / (bounds.width / 2);
    final normalizedY =
        (corner.dy - bounds.center.dy).abs() / (bounds.height / 2);
    if (math.max(normalizedX, normalizedY) < 0.72 ||
        math.min(normalizedX, normalizedY) > 0.42) {
      return false;
    }
  }
  return true;
}

bool _looksPolygonal(List<Offset> corners) {
  if (corners.length < 4) {
    return false;
  }
  var sharpCornerCount = 0;
  for (var index = 0; index < corners.length; index++) {
    final previous = corners[(index - 1 + corners.length) % corners.length];
    final current = corners[index];
    final next = corners[(index + 1) % corners.length];
    final incoming = previous - current;
    final outgoing = next - current;
    if (incoming.distance < 1 || outgoing.distance < 1) {
      continue;
    }
    final cosine =
        (incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
        (incoming.distance * outgoing.distance);
    final angle = math.acos(cosine.clamp(-1.0, 1.0));
    if (angle < math.pi * 0.72) {
      sharpCornerCount += 1;
    }
  }
  return sharpCornerCount >= math.max(4, corners.length - 1);
}

double _maximumDistanceFromSegment(
  List<Offset> points,
  Offset start,
  Offset end,
) {
  var maximum = 0.0;
  for (final point in points) {
    maximum = math.max(maximum, _distanceToSegment(point, start, end));
  }
  return maximum;
}

double _distanceToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared == 0) {
    return (point - start).distance;
  }
  final projection =
      ((point.dx - start.dx) * segment.dx +
          (point.dy - start.dy) * segment.dy) /
      lengthSquared;
  final t = projection.clamp(0.0, 1.0).toDouble();
  return (point - Offset(start.dx + segment.dx * t, start.dy + segment.dy * t))
      .distance;
}
