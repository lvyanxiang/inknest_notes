import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as image;
import 'package:inknest_notes/models/stroke.dart';

class InkRecognitionImageRenderer {
  const InkRecognitionImageRenderer({
    this.pixelRatio = 3,
    this.padding = 20,
    this.maximumDimension = 2048,
  });

  final double pixelRatio;
  final double padding;
  final int maximumDimension;

  Future<Uint8List> render(List<Stroke> strokes) async {
    final drawableStrokes = [
      for (final stroke in strokes)
        if (stroke.points.isNotEmpty) stroke,
    ];
    if (drawableStrokes.isEmpty) {
      throw ArgumentError.value(strokes, 'strokes', 'No drawable strokes');
    }

    final bounds = _boundsForStrokes(drawableStrokes).inflate(padding);
    final logicalWidth = math.max(1.0, bounds.width);
    final logicalHeight = math.max(1.0, bounds.height);
    final longestDimension = math.max(logicalWidth, logicalHeight);
    final scale = math.min(pixelRatio, maximumDimension / longestDimension);
    final pixelWidth = math.max(1, (logicalWidth * scale).ceil());
    final pixelHeight = math.max(1, (logicalHeight * scale).ceil());
    final recognitionImage = image.Image(
      width: pixelWidth,
      height: pixelHeight,
      numChannels: 3,
    );
    final white = image.ColorRgb8(255, 255, 255);
    final black = image.ColorRgb8(0, 0, 0);
    image.fill(recognitionImage, color: white);

    for (final stroke in drawableStrokes) {
      int scaledX(int pointIndex) =>
          ((stroke.points[pointIndex].offset.dx - bounds.left) * scale).round();
      int scaledY(int pointIndex) =>
          ((stroke.points[pointIndex].offset.dy - bounds.top) * scale).round();
      final thickness = math.max(2.0, stroke.width * scale);
      if (stroke.points.length == 1) {
        image.fillCircle(
          recognitionImage,
          x: scaledX(0),
          y: scaledY(0),
          radius: math.max(1, (thickness / 2).round()),
          color: black,
          antialias: true,
        );
      } else {
        for (var index = 1; index < stroke.points.length; index += 1) {
          image.drawLine(
            recognitionImage,
            x1: scaledX(index - 1),
            y1: scaledY(index - 1),
            x2: scaledX(index),
            y2: scaledY(index),
            color: black,
            antialias: true,
            thickness: thickness,
          );
        }
      }
    }

    return Uint8List.fromList(image.encodePng(recognitionImage));
  }
}

ui.Rect _boundsForStrokes(List<Stroke> strokes) {
  ui.Rect? bounds;
  for (final stroke in strokes) {
    var left = stroke.points.first.offset.dx;
    var top = stroke.points.first.offset.dy;
    var right = left;
    var bottom = top;
    for (final point in stroke.points.skip(1)) {
      left = math.min(left, point.offset.dx);
      top = math.min(top, point.offset.dy);
      right = math.max(right, point.offset.dx);
      bottom = math.max(bottom, point.offset.dy);
    }
    final strokeBounds = ui.Rect.fromLTRB(
      left,
      top,
      right,
      bottom,
    ).inflate(math.max(stroke.width / 2, 2));
    bounds = bounds?.expandToInclude(strokeBounds) ?? strokeBounds;
  }
  return bounds!;
}
