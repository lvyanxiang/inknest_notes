import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' as painting;
import 'package:image/image.dart' as image;
import 'package:inknest_notes/features/editor/templates/page_template_layout.dart';
import 'package:inknest_notes/features/editor/text/note_text_box_styles.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_page_template.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

enum PdfExportQuality { compact, balanced, best }

enum PdfExportBackgroundEncoding { jpeg, png }

extension PdfExportQualityDetails on PdfExportQuality {
  String get label => switch (this) {
    PdfExportQuality.compact => 'Compact',
    PdfExportQuality.balanced => 'Balanced',
    PdfExportQuality.best => 'Best',
  };

  String get description => switch (this) {
    PdfExportQuality.compact => 'Smaller file for sharing and submission.',
    PdfExportQuality.balanced => 'Recommended balance of clarity and size.',
    PdfExportQuality.best => 'Maximum clarity with a larger file.',
  };

  PdfExportRasterSettings get rasterSettings => switch (this) {
    PdfExportQuality.compact => const PdfExportRasterSettings(
      maximumPixelDimension: 1600,
      targetPixelRatio: 1.25,
      backgroundEncoding: PdfExportBackgroundEncoding.jpeg,
      jpegQuality: 72,
    ),
    PdfExportQuality.balanced => const PdfExportRasterSettings(
      maximumPixelDimension: 2400,
      targetPixelRatio: 2,
      backgroundEncoding: PdfExportBackgroundEncoding.jpeg,
      jpegQuality: 88,
    ),
    PdfExportQuality.best => const PdfExportRasterSettings(
      maximumPixelDimension: 3600,
      targetPixelRatio: 3,
      backgroundEncoding: PdfExportBackgroundEncoding.png,
      jpegQuality: 100,
    ),
  };
}

class PdfExportRasterSettings {
  const PdfExportRasterSettings({
    required this.maximumPixelDimension,
    required this.targetPixelRatio,
    required this.backgroundEncoding,
    required this.jpegQuality,
  }) : assert(maximumPixelDimension > 0),
       assert(targetPixelRatio > 0),
       assert(jpegQuality >= 1 && jpegQuality <= 100);

  final int maximumPixelDimension;
  final double targetPixelRatio;
  final PdfExportBackgroundEncoding backgroundEncoding;
  final int jpegQuality;
}

class NotebookPdfExporter {
  NotebookPdfExporter({
    required this.notebookRepository,
    this.quality = PdfExportQuality.balanced,
    PdfPageBackgroundRenderer? backgroundRenderer,
  }) : _backgroundRenderer =
           backgroundRenderer ??
           PdfrxPageBackgroundRenderer.forQuality(quality),
       _ownsBackgroundRenderer = backgroundRenderer == null;

  final NotebookRepository notebookRepository;
  final PdfExportQuality quality;
  final PdfPageBackgroundRenderer _backgroundRenderer;
  final bool _ownsBackgroundRenderer;
  final Map<_BackgroundCacheKey, Future<RenderedPdfPageBackground?>>
  _backgroundsByKey = {};

  Future<Uint8List> exportNotebook(
    Notebook notebook, {
    List<String>? pageIds,
  }) async {
    try {
      final document = pw.Document(title: notebook.title);
      final exportPageIds = pageIds ?? notebook.pageIds;

      for (final pageId in exportPageIds) {
        final page = await notebookRepository.loadPage(notebook, pageId);
        final background = await _renderBackground(page);
        final pageImages = await _renderImages(page);
        final textBoxes = await _renderTextBoxes(page);

        document.addPage(
          pw.Page(
            pageFormat: pdf.PdfPageFormat(
              page.displayWidth,
              page.displayHeight,
            ),
            margin: pw.EdgeInsets.zero,
            build: (context) =>
                _buildRotatedPage(page, background, pageImages, textBoxes),
          ),
        );
      }

      return await document.save();
    } finally {
      _backgroundsByKey.clear();
      if (_ownsBackgroundRenderer) {
        await _backgroundRenderer.dispose();
      }
    }
  }

  pw.Widget _buildRotatedPage(
    NotePage page,
    RenderedPdfPageBackground? background,
    List<_RenderedPageImage> pageImages,
    List<_RenderedTextBox> textBoxes,
  ) {
    final content = pw.SizedBox(
      width: page.width,
      height: page.height,
      child: _buildPage(page, background, pageImages, textBoxes),
    );
    if (page.rotationQuarterTurns == 0) {
      return content;
    }

    return pw.Transform.rotateBox(
      angle: -page.rotationQuarterTurns * math.pi / 2,
      unconstrained: true,
      child: content,
    );
  }

  Future<RenderedPdfPageBackground?> _renderBackground(NotePage page) {
    final background = page.pdfBackground;
    if (background == null) {
      return Future.value();
    }

    final cacheKey = _BackgroundCacheKey(
      filePath: background.filePath,
      pageNumber: background.pageNumber,
      width: page.width,
      height: page.height,
    );

    return _backgroundsByKey.putIfAbsent(
      cacheKey,
      () => _backgroundRenderer.render(background, page),
    );
  }

  pw.Widget _buildPage(
    NotePage page,
    RenderedPdfPageBackground? background,
    List<_RenderedPageImage> pageImages,
    List<_RenderedTextBox> textBoxes,
  ) {
    return pw.Stack(
      children: [
        pw.Positioned.fill(child: pw.Container(color: pdf.PdfColors.white)),
        if (background == null && page.template != NotePageTemplate.blank)
          pw.Positioned.fill(
            child: pw.CustomPaint(
              painter: (canvas, size) {
                _paintPageTemplate(canvas, size, page);
              },
            ),
          ),
        if (background != null)
          pw.Positioned.fill(
            child: pw.Image(
              pw.MemoryImage(background.imageBytes),
              fit: pw.BoxFit.contain,
            ),
          ),
        ..._buildImages(pageImages),
        pw.Positioned.fill(
          child: pw.CustomPaint(
            painter: (canvas, size) {
              _paintStrokes(canvas, size, page);
              _paintShapes(canvas, size, page);
            },
          ),
        ),
        ..._buildTextBoxes(textBoxes),
      ],
    );
  }

  Iterable<pw.Widget> _buildImages(List<_RenderedPageImage> pageImages) {
    return [
      for (final pageImage in pageImages)
        pw.Positioned(
          left: pageImage.model.position.dx,
          top: pageImage.model.position.dy,
          child: pw.Image(
            pw.MemoryImage(pageImage.pngBytes),
            width: pageImage.model.width,
            height: pageImage.model.height,
            fit: pw.BoxFit.contain,
          ),
        ),
    ];
  }

  void _paintPageTemplate(
    pdf.PdfGraphics canvas,
    pdf.PdfPoint size,
    NotePage page,
  ) {
    final layout = buildPageTemplateLayout(
      page.template,
      ui.Size(page.width, page.height),
    );
    final scaleX = size.x / page.width;
    final scaleY = size.y / page.height;
    final strokeScale = (scaleX + scaleY) / 2;

    void paintLines(PageTemplateLineStyle style, pdf.PdfColor color) {
      final lines = layout.lines.where((line) => line.style == style);
      if (lines.isEmpty) {
        return;
      }
      canvas
        ..setStrokeColor(color)
        ..setLineCap(pdf.PdfLineCap.round)
        ..setLineWidth(
          (style == PageTemplateLineStyle.major ? 1.4 : 0.9) * strokeScale,
        );
      for (final line in lines) {
        final start = _mapTemplateOffset(line.start, page, scaleX, scaleY);
        final end = _mapTemplateOffset(line.end, page, scaleX, scaleY);
        canvas
          ..moveTo(start.x, start.y)
          ..lineTo(end.x, end.y);
      }
      canvas.strokePath();
    }

    canvas.saveContext();
    paintLines(PageTemplateLineStyle.minor, pdf.PdfColor.fromInt(0xFFD9E5E8));
    paintLines(PageTemplateLineStyle.major, pdf.PdfColor.fromInt(0xFFA8C1C6));
    if (layout.dots.isNotEmpty) {
      canvas.setFillColor(pdf.PdfColor.fromInt(0xFFB8CDD1));
      final radius = 1.15 * strokeScale;
      for (final dot in layout.dots) {
        final center = _mapTemplateOffset(dot, page, scaleX, scaleY);
        canvas.drawEllipse(center.x, center.y, radius, radius);
      }
      canvas.fillPath();
    }
    canvas.restoreContext();
  }

  pdf.PdfPoint _mapTemplateOffset(
    ui.Offset offset,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    return pdf.PdfPoint(offset.dx * scaleX, (page.height - offset.dy) * scaleY);
  }

  Iterable<pw.Widget> _buildTextBoxes(List<_RenderedTextBox> textBoxes) {
    return [
      for (final textBox in textBoxes)
        pw.Positioned(
          left: textBox.model.position.dx,
          top: textBox.model.position.dy,
          child: pw.Image(
            pw.MemoryImage(textBox.pngBytes),
            width: textBox.width,
            height: textBox.height,
          ),
        ),
    ];
  }

  Future<List<_RenderedTextBox>> _renderTextBoxes(NotePage page) async {
    final renderedTextBoxes = <_RenderedTextBox>[];
    for (final textBox in page.textBoxes) {
      if (textBox.text.trim().isEmpty) {
        continue;
      }

      final renderedTextBox = await _renderTextBox(textBox);
      if (renderedTextBox != null) {
        renderedTextBoxes.add(renderedTextBox);
      }
    }

    return renderedTextBoxes;
  }

  Future<List<_RenderedPageImage>> _renderImages(NotePage page) async {
    final renderedImages = <_RenderedPageImage>[];
    for (final noteImage in page.images) {
      final renderedImage = await _renderImage(noteImage);
      if (renderedImage != null) {
        renderedImages.add(renderedImage);
      }
    }

    return renderedImages;
  }

  Future<_RenderedPageImage?> _renderImage(NoteImage noteImage) async {
    final file = File(noteImage.filePath);
    if (!await file.exists()) {
      return null;
    }

    final decodedImage = image.decodeImage(await file.readAsBytes());
    if (decodedImage == null) {
      return null;
    }

    return _RenderedPageImage(
      model: noteImage,
      pngBytes: Uint8List.fromList(image.encodePng(decodedImage)),
    );
  }

  Future<_RenderedTextBox?> _renderTextBox(NoteTextBox textBox) async {
    const pixelRatio = 2.0;
    final textPainter = painting.TextPainter(
      text: painting.TextSpan(
        text: textBox.text,
        style: noteTextBoxTextStyle(textBox),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: textBox.width);
    final width = math.max(1.0, textBox.width);
    final height = math.max(1.0, textPainter.height);
    final pixelWidth = math.max(1, (width * pixelRatio).ceil());
    final pixelHeight = math.max(1, (height * pixelRatio).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(pixelRatio, pixelRatio);

    textPainter.paint(canvas, ui.Offset.zero);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(pixelWidth, pixelHeight);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          return null;
        }

        return _RenderedTextBox(
          model: textBox,
          width: width,
          height: height,
          pngBytes: byteData.buffer.asUint8List(),
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  void _paintShapes(pdf.PdfGraphics canvas, pdf.PdfPoint size, NotePage page) {
    final scaleX = size.x / page.width;
    final scaleY = size.y / page.height;
    final strokeScale = (scaleX + scaleY) / 2;

    for (final shape in page.shapes) {
      final color = pdf.PdfColor.fromInt(_opaqueArgb(shape.color.toARGB32()));
      canvas
        ..saveContext()
        ..setStrokeColor(color)
        ..setLineCap(pdf.PdfLineCap.round)
        ..setLineJoin(pdf.PdfLineJoin.round)
        ..setLineWidth(shape.width * strokeScale);

      switch (shape.type) {
        case NoteShapeType.line:
          _paintShapeLine(canvas, shape.start, shape.end, page, scaleX, scaleY);
          break;
        case NoteShapeType.arrow:
          _paintShapeLine(canvas, shape.start, shape.end, page, scaleX, scaleY);
          _paintShapeArrowHead(
            canvas,
            shape.start,
            shape.end,
            page,
            scaleX,
            scaleY,
            shape.width * strokeScale,
          );
          break;
        case NoteShapeType.rectangle:
          _paintShapeRect(canvas, shape, page, scaleX, scaleY);
          break;
        case NoteShapeType.ellipse:
          _paintShapeEllipse(canvas, shape, page, scaleX, scaleY);
          break;
      }

      canvas
        ..strokePath()
        ..restoreContext();
    }
  }

  void _paintShapeLine(
    pdf.PdfGraphics canvas,
    ui.Offset start,
    ui.Offset end,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    final mappedStart = _mapOffset(start, page, scaleX, scaleY);
    final mappedEnd = _mapOffset(end, page, scaleX, scaleY);
    canvas
      ..moveTo(mappedStart.dx, mappedStart.dy)
      ..lineTo(mappedEnd.dx, mappedEnd.dy);
  }

  void _paintShapeArrowHead(
    pdf.PdfGraphics canvas,
    ui.Offset start,
    ui.Offset end,
    NotePage page,
    double scaleX,
    double scaleY,
    double strokeWidth,
  ) {
    final mappedStart = _mapOffset(start, page, scaleX, scaleY);
    final mappedEnd = _mapOffset(end, page, scaleX, scaleY);
    final delta = mappedEnd - mappedStart;
    if (delta.distance <= 0) {
      return;
    }

    final angle = math.atan2(delta.dy, delta.dx);
    final headLength = math.max(14.0, strokeWidth * 4);
    const spread = math.pi / 7;
    final left =
        mappedEnd -
        ui.Offset(
          math.cos(angle - spread) * headLength,
          math.sin(angle - spread) * headLength,
        );
    final right =
        mappedEnd -
        ui.Offset(
          math.cos(angle + spread) * headLength,
          math.sin(angle + spread) * headLength,
        );

    canvas
      ..moveTo(mappedEnd.dx, mappedEnd.dy)
      ..lineTo(left.dx, left.dy)
      ..moveTo(mappedEnd.dx, mappedEnd.dy)
      ..lineTo(right.dx, right.dy);
  }

  void _paintShapeRect(
    pdf.PdfGraphics canvas,
    NoteShape shape,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    final rect = shape.bounds;
    canvas.drawRect(
      rect.left * scaleX,
      (page.height - rect.bottom) * scaleY,
      rect.width * scaleX,
      rect.height * scaleY,
    );
  }

  void _paintShapeEllipse(
    pdf.PdfGraphics canvas,
    NoteShape shape,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    final rect = shape.bounds;
    canvas.drawEllipse(
      rect.center.dx * scaleX,
      (page.height - rect.center.dy) * scaleY,
      rect.width * scaleX / 2,
      rect.height * scaleY / 2,
    );
  }

  void _paintStrokes(pdf.PdfGraphics canvas, pdf.PdfPoint size, NotePage page) {
    final scaleX = size.x / page.width;
    final scaleY = size.y / page.height;
    final strokeScale = (scaleX + scaleY) / 2;

    for (final stroke in page.strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final color = pdf.PdfColor.fromInt(_opaqueArgb(stroke.color.toARGB32()));

      canvas
        ..saveContext()
        ..setStrokeColor(color)
        ..setFillColor(color)
        ..setLineCap(pdf.PdfLineCap.round)
        ..setLineJoin(pdf.PdfLineJoin.round)
        ..setLineWidth(stroke.width * strokeScale)
        ..setGraphicState(_graphicStateFor(stroke));

      if (stroke.points.length == 1) {
        final point = _mapPoint(stroke.points.first, page, scaleX, scaleY);
        final radius = stroke.width * strokeScale / 2;
        canvas
          ..drawEllipse(point.x, point.y, radius, radius)
          ..fillPath();
      } else {
        _paintSmoothStrokePath(canvas, stroke, page, scaleX, scaleY);

        canvas.strokePath();
      }

      canvas.restoreContext();
    }
  }

  void _paintSmoothStrokePath(
    pdf.PdfGraphics canvas,
    Stroke stroke,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    final mappedPoints = [
      for (final point in stroke.points)
        _mapPointOffset(point, page, scaleX, scaleY),
    ];

    canvas.moveTo(mappedPoints.first.dx, mappedPoints.first.dy);
    var currentPoint = mappedPoints.first;
    for (final segment in StrokeGeometry.buildSmoothSegments(mappedPoints)) {
      final control = segment.control;
      if (control == null) {
        canvas.lineTo(segment.end.dx, segment.end.dy);
      } else {
        _quadraticCurveTo(
          canvas: canvas,
          start: currentPoint,
          control: control,
          end: segment.end,
        );
      }
      currentPoint = segment.end;
    }
  }

  void _quadraticCurveTo({
    required pdf.PdfGraphics canvas,
    required ui.Offset start,
    required ui.Offset control,
    required ui.Offset end,
  }) {
    final firstControl = start + (control - start) * (2 / 3);
    final secondControl = end + (control - end) * (2 / 3);
    canvas.curveTo(
      firstControl.dx,
      firstControl.dy,
      secondControl.dx,
      secondControl.dy,
      end.dx,
      end.dy,
    );
  }

  pdf.PdfGraphicState _graphicStateFor(Stroke stroke) {
    final opacity = _alphaFromArgb(stroke.color.toARGB32());
    if (!stroke.isHighlighter) {
      return pdf.PdfGraphicState(strokeOpacity: opacity, fillOpacity: opacity);
    }

    return pdf.PdfGraphicState(
      strokeOpacity: math.min(opacity, 0.35),
      fillOpacity: math.min(opacity, 0.35),
      blendMode: pdf.PdfBlendMode.multiply,
    );
  }

  pdf.PdfPoint _mapPoint(
    StrokePoint point,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    return pdf.PdfPoint(
      point.offset.dx * scaleX,
      (page.height - point.offset.dy) * scaleY,
    );
  }

  ui.Offset _mapPointOffset(
    StrokePoint point,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    return ui.Offset(
      point.offset.dx * scaleX,
      (page.height - point.offset.dy) * scaleY,
    );
  }

  ui.Offset _mapOffset(
    ui.Offset offset,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    return ui.Offset(offset.dx * scaleX, (page.height - offset.dy) * scaleY);
  }

  double _alphaFromArgb(int argb) {
    return ((argb >> 24) & 0xff) / 255;
  }

  int _opaqueArgb(int argb) {
    return 0xff000000 | (argb & 0x00ffffff);
  }
}

abstract class PdfPageBackgroundRenderer {
  Future<RenderedPdfPageBackground?> render(
    PdfBackground background,
    NotePage page,
  );

  Future<void> dispose() async {}
}

class PdfrxPageBackgroundRenderer implements PdfPageBackgroundRenderer {
  PdfrxPageBackgroundRenderer({
    this.maximumPixelDimension = 2400,
    this.targetPixelRatio = 2.0,
    this.backgroundEncoding = PdfExportBackgroundEncoding.png,
    this.jpegQuality = 88,
  }) : assert(maximumPixelDimension > 0),
       assert(targetPixelRatio > 0),
       assert(jpegQuality >= 1 && jpegQuality <= 100);

  PdfrxPageBackgroundRenderer.forQuality(PdfExportQuality quality)
    : this(
        maximumPixelDimension: quality.rasterSettings.maximumPixelDimension,
        targetPixelRatio: quality.rasterSettings.targetPixelRatio,
        backgroundEncoding: quality.rasterSettings.backgroundEncoding,
        jpegQuality: quality.rasterSettings.jpegQuality,
      );

  final int maximumPixelDimension;
  final double targetPixelRatio;
  final PdfExportBackgroundEncoding backgroundEncoding;
  final int jpegQuality;
  final Map<String, Future<pdfrx.PdfDocument>> _documentsByPath = {};

  @override
  Future<RenderedPdfPageBackground?> render(
    PdfBackground background,
    NotePage page,
  ) async {
    final document = await _documentFor(background.filePath);
    final pdfPage = await document.pages[background.pageNumber - 1]
        .ensureLoaded();
    final renderSize = _containedRenderSize(pdfPage, page);
    final renderedImage = await pdfPage.render(
      fullWidth: renderSize.width.toDouble(),
      fullHeight: renderSize.height.toDouble(),
      backgroundColor: 0xffffffff,
    );

    if (renderedImage == null) {
      return null;
    }

    try {
      return RenderedPdfPageBackground(
        imageBytes: encodePdfExportBackgroundImage(
          width: renderedImage.width,
          height: renderedImage.height,
          bgraPixels: renderedImage.pixels.buffer,
          encoding: backgroundEncoding,
          jpegQuality: jpegQuality,
        ),
      );
    } finally {
      renderedImage.dispose();
    }
  }

  Future<pdfrx.PdfDocument> _documentFor(String filePath) {
    return _documentsByPath.putIfAbsent(
      filePath,
      () => pdfrx.PdfDocument.openFile(filePath),
    );
  }

  @override
  Future<void> dispose() async {
    final documentFutures = _documentsByPath.values.toList();
    _documentsByPath.clear();

    for (final documentFuture in documentFutures) {
      try {
        final document = await documentFuture;
        await document.dispose();
      } catch (_) {
        // Ignore cleanup failures for documents that failed to open.
      }
    }
  }

  _RenderSize _containedRenderSize(pdfrx.PdfPage pdfPage, NotePage notePage) {
    final pageScale = math.min(
      notePage.width / pdfPage.width,
      notePage.height / pdfPage.height,
    );
    final width = pdfPage.width * pageScale;
    final height = pdfPage.height * pageScale;
    final pixelScale = math.min(
      targetPixelRatio,
      maximumPixelDimension / math.max(width, height),
    );

    return _RenderSize(
      width: math.max(1, (width * pixelScale).round()),
      height: math.max(1, (height * pixelScale).round()),
    );
  }
}

class RenderedPdfPageBackground {
  RenderedPdfPageBackground({Uint8List? imageBytes, Uint8List? pngBytes})
    : assert(imageBytes != null || pngBytes != null),
      imageBytes = imageBytes ?? pngBytes!;

  final Uint8List imageBytes;
}

Uint8List encodePdfExportBackgroundImage({
  required int width,
  required int height,
  required ByteBuffer bgraPixels,
  required PdfExportBackgroundEncoding encoding,
  int jpegQuality = 88,
}) {
  assert(width > 0);
  assert(height > 0);
  assert(jpegQuality >= 1 && jpegQuality <= 100);

  final decodedImage = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: bgraPixels,
    numChannels: 4,
    order: image.ChannelOrder.bgra,
  );
  return switch (encoding) {
    PdfExportBackgroundEncoding.jpeg => Uint8List.fromList(
      image.encodeJpg(decodedImage, quality: jpegQuality),
    ),
    PdfExportBackgroundEncoding.png => Uint8List.fromList(
      image.encodePng(decodedImage),
    ),
  };
}

class _BackgroundCacheKey {
  const _BackgroundCacheKey({
    required this.filePath,
    required this.pageNumber,
    required this.width,
    required this.height,
  });

  final String filePath;
  final int pageNumber;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) {
    return other is _BackgroundCacheKey &&
        other.filePath == filePath &&
        other.pageNumber == pageNumber &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(filePath, pageNumber, width, height);
}

class _RenderedPageImage {
  const _RenderedPageImage({required this.model, required this.pngBytes});

  final NoteImage model;
  final Uint8List pngBytes;
}

class _RenderedTextBox {
  const _RenderedTextBox({
    required this.model,
    required this.width,
    required this.height,
    required this.pngBytes,
  });

  final NoteTextBox model;
  final double width;
  final double height;
  final Uint8List pngBytes;
}

class _RenderSize {
  const _RenderSize({required this.width, required this.height});

  final int width;
  final int height;
}
