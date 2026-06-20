import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as image;
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

class NotebookPdfExporter {
  NotebookPdfExporter({
    required this.notebookRepository,
    PdfPageBackgroundRenderer? backgroundRenderer,
  }) : _backgroundRenderer =
           backgroundRenderer ?? PdfrxPageBackgroundRenderer(),
       _ownsBackgroundRenderer = backgroundRenderer == null;

  final NotebookRepository notebookRepository;
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

        document.addPage(
          pw.Page(
            pageFormat: pdf.PdfPageFormat(page.width, page.height),
            margin: pw.EdgeInsets.zero,
            build: (context) => _buildPage(page, background),
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

  pw.Widget _buildPage(NotePage page, RenderedPdfPageBackground? background) {
    return pw.Stack(
      children: [
        pw.Positioned.fill(child: pw.Container(color: pdf.PdfColors.white)),
        if (background != null)
          pw.Positioned.fill(
            child: pw.Image(
              pw.MemoryImage(background.pngBytes),
              fit: pw.BoxFit.contain,
            ),
          ),
        pw.Positioned.fill(
          child: pw.CustomPaint(
            painter: (canvas, size) => _paintStrokes(canvas, size, page),
          ),
        ),
        ..._buildTextBoxes(page),
      ],
    );
  }

  Iterable<pw.Widget> _buildTextBoxes(NotePage page) {
    return [
      for (final textBox in page.textBoxes)
        if (textBox.text.trim().isNotEmpty)
          pw.Positioned(
            left: textBox.position.dx,
            top: textBox.position.dy,
            child: pw.SizedBox(
              width: textBox.width,
              child: pw.Text(
                textBox.text,
                style: pw.TextStyle(
                  color: pdf.PdfColor.fromInt(
                    _opaqueArgb(textBox.color.toARGB32()),
                  ),
                  fontSize: textBox.fontSize,
                  lineSpacing: textBox.fontSize * 0.2,
                ),
              ),
            ),
          ),
    ];
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
    required Offset start,
    required Offset control,
    required Offset end,
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

  Offset _mapPointOffset(
    StrokePoint point,
    NotePage page,
    double scaleX,
    double scaleY,
  ) {
    return Offset(
      point.offset.dx * scaleX,
      (page.height - point.offset.dy) * scaleY,
    );
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
  }) : assert(maximumPixelDimension > 0),
       assert(targetPixelRatio > 0);

  final int maximumPixelDimension;
  final double targetPixelRatio;
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
        pngBytes: _pngFromBgraPixels(renderedImage),
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

  Uint8List _pngFromBgraPixels(pdfrx.PdfImage renderedImage) {
    final decodedImage = image.Image.fromBytes(
      width: renderedImage.width,
      height: renderedImage.height,
      bytes: renderedImage.pixels.buffer,
      numChannels: 4,
      order: image.ChannelOrder.bgra,
    );
    return image.encodePng(decodedImage);
  }
}

class RenderedPdfPageBackground {
  const RenderedPdfPageBackground({required this.pngBytes});

  final Uint8List pngBytes;
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

class _RenderSize {
  const _RenderSize({required this.width, required this.height});

  final int width;
  final int height;
}
