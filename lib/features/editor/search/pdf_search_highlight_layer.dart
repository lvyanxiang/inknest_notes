import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PdfSearchHighlightLayer extends StatelessWidget {
  const PdfSearchHighlightLayer({
    super.key,
    required this.rects,
    required this.referencePageSize,
  });

  final List<Rect> rects;
  final Size referencePageSize;

  @override
  Widget build(BuildContext context) {
    if (rects.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: CustomPaint(
        painter: _PdfSearchHighlightPainter(
          rects: rects,
          referencePageSize: referencePageSize,
        ),
      ),
    );
  }
}

class _PdfSearchHighlightPainter extends CustomPainter {
  const _PdfSearchHighlightPainter({
    required this.rects,
    required this.referencePageSize,
  });

  final List<Rect> rects;
  final Size referencePageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = const Color(0x66FFD54F)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xCCF57F17)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final canvasRects = scalePdfSearchHighlightRects(
      rects: rects,
      referencePageSize: referencePageSize,
      canvasSize: size,
    );
    for (final rect in canvasRects) {
      final highlight = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(highlight, fillPaint);
      canvas.drawRRect(highlight, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PdfSearchHighlightPainter oldDelegate) {
    return !listEquals(oldDelegate.rects, rects) ||
        oldDelegate.referencePageSize != referencePageSize;
  }
}

@visibleForTesting
List<Rect> scalePdfSearchHighlightRects({
  required List<Rect> rects,
  required Size referencePageSize,
  required Size canvasSize,
}) {
  if (referencePageSize.isEmpty || canvasSize.isEmpty) {
    return const [];
  }

  final scaleX = canvasSize.width / referencePageSize.width;
  final scaleY = canvasSize.height / referencePageSize.height;
  final canvasBounds = Offset.zero & canvasSize;
  return [
    for (final rect in rects)
      Rect.fromLTRB(
        rect.left * scaleX,
        rect.top * scaleY,
        rect.right * scaleX,
        rect.bottom * scaleY,
      ).intersect(canvasBounds),
  ].where((rect) => rect.isFinite && !rect.isEmpty).toList(growable: false);
}
