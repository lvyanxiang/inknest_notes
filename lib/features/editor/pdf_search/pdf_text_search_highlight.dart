import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/pdf_search/notebook_pdf_text_searcher.dart';

class PdfTextSearchHighlight extends StatelessWidget {
  const PdfTextSearchHighlight({
    super.key,
    required this.result,
    required this.color,
  });

  final PdfTextSearchResult result;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PdfTextSearchHighlightPainter(result: result, color: color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PdfTextSearchHighlightPainter extends CustomPainter {
  const _PdfTextSearchHighlightPainter({
    required this.result,
    required this.color,
  });

  final PdfTextSearchResult result;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pdfSize = result.pdfPageSize;
    if (size.isEmpty || pdfSize.isEmpty) {
      return;
    }

    final scale = math.min(
      size.width / pdfSize.width,
      size.height / pdfSize.height,
    );
    final displayedSize = Size(pdfSize.width * scale, pdfSize.height * scale);
    final pageOffset = Offset(
      (size.width - displayedSize.width) / 2,
      (size.height - displayedSize.height) / 2,
    );
    final normalizedBounds = result.normalizedBounds;
    final highlightRect = Rect.fromLTRB(
      pageOffset.dx + normalizedBounds.left * displayedSize.width,
      pageOffset.dy + normalizedBounds.top * displayedSize.height,
      pageOffset.dx + normalizedBounds.right * displayedSize.width,
      pageOffset.dy + normalizedBounds.bottom * displayedSize.height,
    ).inflate(2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(highlightRect, const Radius.circular(3)),
      Paint()..color = color.withValues(alpha: 0.34),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(highlightRect, const Radius.circular(3)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _PdfTextSearchHighlightPainter oldDelegate) {
    return oldDelegate.result.pageId != result.pageId ||
        oldDelegate.result.normalizedBounds != result.normalizedBounds ||
        oldDelegate.color != color;
  }
}
