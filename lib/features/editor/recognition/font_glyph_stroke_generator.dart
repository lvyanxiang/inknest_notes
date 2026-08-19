import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/text/handwriting_font_presets.dart';
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

  static const double _referenceFontSize = 96;

  Future<List<Stroke>> generate({
    required String text,
    required HandwritingFontPreset font,
    required Rect targetBounds,
    required Color color,
    required double strokeWidth,
  }) async {
    final normalized = _normalizeText(text);
    if (normalized.isEmpty || targetBounds.isEmpty) {
      return const [];
    }

    // Render at a stable reference size without maxWidth. Only explicit line
    // breaks are honored, so a single handwritten line can never be reflowed
    // merely because the replacement font is wider.
    final painter = TextPainter(
      text: TextSpan(
        text: normalized,
        style: TextStyle(
          fontFamily: font.fontFamily,
          fontSize: _referenceFontSize,
          color: Colors.black,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // One em of padding on every side protects negative bearings, flourishes,
    // and other glyph overhang before the real raster ink bounds are measured.
    const renderPadding = _referenceFontSize;
    final renderWidth = math.max(1.0, painter.width + renderPadding * 2);
    final renderHeight = math.max(1.0, painter.height + renderPadding * 2);
    final longest = math.max(renderWidth, renderHeight);
    final scale = math.min(pixelRatio, maximumDimension / longest);
    final imageWidth = math.max(1, (renderWidth * scale).ceil());
    final imageHeight = math.max(1, (renderHeight * scale).ceil());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.scale(scale);
    painter.paint(canvas, const Offset(renderPadding, renderPadding));
    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (byteData == null) {
      return const [];
    }

    final bytes = byteData.buffer.asUint8List();
    final inkBounds = _inkPixelBounds(bytes, imageWidth, imageHeight);
    if (inkBounds == null || inkBounds.isEmpty) {
      return const [];
    }

    var contentScale = math.min(
      targetBounds.width / inkBounds.width,
      targetBounds.height / inkBounds.height,
    );
    var rowWidth = (contentScale * 1.15)
        .clamp(0.5, math.max(0.5, strokeWidth))
        .toDouble();
    Rect fittedBounds = targetBounds;
    for (var iteration = 0; iteration < 2; iteration += 1) {
      final inset = math.min(
        math.max(4.0, rowWidth / 2 + 0.25),
        targetBounds.shortestSide / 4,
      );
      fittedBounds = targetBounds.deflate(inset);
      if (fittedBounds.isEmpty) {
        return const [];
      }
      contentScale = math.min(
        fittedBounds.width / inkBounds.width,
        fittedBounds.height / inkBounds.height,
      );
      rowWidth = (contentScale * 1.15)
          .clamp(0.5, math.max(0.5, strokeWidth))
          .toDouble();
    }

    final origin = Offset(
      fittedBounds.left +
          (fittedBounds.width - inkBounds.width * contentScale) / 2,
      fittedBounds.top +
          (fittedBounds.height - inkBounds.height * contentScale) / 2,
    );
    final now = DateTime.now().toUtc();
    final strokes = <Stroke>[];
    var strokeIndex = 0;

    final inkLeft = inkBounds.left.toInt();
    final inkTop = inkBounds.top.toInt();
    final inkRight = inkBounds.right.toInt();
    final inkBottom = inkBounds.bottom.toInt();
    for (var y = inkTop; y < inkBottom; y += 1) {
      var x = inkLeft;
      while (x < inkRight) {
        while (x < inkRight && !_isInk(bytes, imageWidth, x, y)) {
          x += 1;
        }
        if (x >= inkRight) {
          break;
        }
        final startX = x;
        while (x < inkRight && _isInk(bytes, imageWidth, x, y)) {
          x += 1;
        }
        final endX = x; // exclusive
        final pageY = origin.dy + (y + 0.5 - inkBounds.top) * contentScale;
        final pageStartX = origin.dx + (startX - inkBounds.left) * contentScale;
        final pageEndX = origin.dx + (endX - inkBounds.left) * contentScale;
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

  Rect? _inkPixelBounds(Uint8List bytes, int width, int height) {
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        if (!_isInk(bytes, width, x, y)) continue;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    if (maxX < minX || maxY < minY) {
      return null;
    }
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
}
