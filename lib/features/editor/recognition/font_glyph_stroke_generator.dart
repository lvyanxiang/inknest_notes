import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/recognition/ink_beautify_fonts.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

/// Turns recognized text + a bundled handwriting font into page-space strokes.
///
/// Instead of approximating glyph centerlines, this renders the font exactly
/// and packs the filled silhouette into horizontal ink runs so the result
/// matches the chosen typeface.
class FontGlyphStrokeGenerator {
  const FontGlyphStrokeGenerator({
    this.maximumDimension = 720,
    this.pixelRatio = 3.0,
  });

  final int maximumDimension;
  final double pixelRatio;

  Future<List<Stroke>> generate({
    required String text,
    required InkBeautifyFont font,
    required Rect targetBounds,
    required Color color,
    required double strokeWidth,
  }) async {
    final normalized = _normalizeText(text);
    if (normalized.isEmpty || targetBounds.isEmpty) {
      return const [];
    }

    final layoutSize = Size(
      math.max(24, targetBounds.width),
      math.max(24, targetBounds.height),
    );
    final fontSize = _fitFontSize(
      text: normalized,
      fontFamily: font.fontFamily,
      layoutSize: layoutSize,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: normalized,
        style: TextStyle(
          fontFamily: font.fontFamily,
          fontSize: fontSize,
          color: Colors.black,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: layoutSize.width);

    final contentWidth = math.max(1.0, painter.width);
    final contentHeight = math.max(1.0, painter.height);
    final longest = math.max(contentWidth, contentHeight);
    final scale = math.min(pixelRatio, maximumDimension / longest);
    final imageWidth = math.max(1, (contentWidth * scale).ceil());
    final imageHeight = math.max(1, (contentHeight * scale).ceil());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (byteData == null) {
      return const [];
    }

    final bytes = byteData.buffer.asUint8List();
    final origin = Offset(
      targetBounds.left + math.max(0, (targetBounds.width - contentWidth) / 2),
      targetBounds.top + math.max(0, (targetBounds.height - contentHeight) / 2),
    );
    // Slight overlap between rows avoids hairline gaps after round caps.
    final rowWidth = (1.15 / scale).clamp(0.8, 8.0).toDouble();
    final now = DateTime.now().toUtc();
    final strokes = <Stroke>[];
    var strokeIndex = 0;

    for (var y = 0; y < imageHeight; y += 1) {
      var x = 0;
      while (x < imageWidth) {
        while (x < imageWidth && !_isInk(bytes, imageWidth, x, y)) {
          x += 1;
        }
        if (x >= imageWidth) {
          break;
        }
        final startX = x;
        while (x < imageWidth && _isInk(bytes, imageWidth, x, y)) {
          x += 1;
        }
        final endX = x; // exclusive
        final pageY = origin.dy + (y + 0.5) / scale;
        final pageStartX = origin.dx + startX / scale;
        final pageEndX = origin.dx + endX / scale;
        final points = pageEndX - pageStartX < 0.01
            ? [
                StrokePoint(
                  offset: Offset(pageStartX, pageY),
                  pressure: 1,
                  time: now.add(Duration(milliseconds: strokeIndex)),
                ),
              ]
            : [
                StrokePoint(
                  offset: Offset(pageStartX, pageY),
                  pressure: 1,
                  time: now.add(Duration(milliseconds: strokeIndex)),
                ),
                StrokePoint(
                  offset: Offset(pageEndX, pageY),
                  pressure: 1,
                  time: now.add(Duration(milliseconds: strokeIndex + 1)),
                ),
              ];
        strokes.add(
          Stroke(
            id: 'beautify-${now.microsecondsSinceEpoch}-$strokeIndex',
            tool: ToolType.pen,
            color: color,
            width: rowWidth,
            points: points,
          ),
        );
        strokeIndex += 1;
      }
    }

    return strokes;
  }

  bool _isInk(Uint8List bytes, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    final r = bytes[offset];
    final g = bytes[offset + 1];
    final b = bytes[offset + 2];
    final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    return luminance < 210;
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  double _fitFontSize({
    required String text,
    required String fontFamily,
    required Size layoutSize,
  }) {
    var low = 12.0;
    var high = math.min(96.0, math.max(18.0, layoutSize.shortestSide));
    var best = low;
    for (var i = 0; i < 10; i += 1) {
      final mid = (low + high) / 2;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: mid,
            height: 1.15,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: layoutSize.width);
      if (painter.height <= layoutSize.height &&
          painter.width <= layoutSize.width * 1.02) {
        best = mid;
        low = mid;
      } else {
        high = mid;
      }
    }
    return best;
  }
}
