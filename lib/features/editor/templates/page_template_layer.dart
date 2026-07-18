import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/templates/page_template_layout.dart';
import 'package:inknest_notes/models/note_page_template.dart';

class PageTemplateLayer extends StatelessWidget {
  const PageTemplateLayer({super.key, required this.template});

  final NotePageTemplate template;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: PageTemplatePainter(template: template)),
    );
  }
}

class PageTemplatePainter extends CustomPainter {
  const PageTemplatePainter({required this.template});

  final NotePageTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    paintPageTemplate(canvas, size, template);
  }

  @override
  bool shouldRepaint(covariant PageTemplatePainter oldDelegate) {
    return oldDelegate.template != template;
  }
}

void paintPageTemplate(
  Canvas canvas,
  Size size,
  NotePageTemplate template, {
  double minimumStrokeWidth = 0,
}) {
  final layout = buildPageTemplateLayout(template, size);
  if (layout.lines.isEmpty && layout.dots.isEmpty) {
    return;
  }

  final minorPaint = Paint()
    ..color = const Color(0xFFD9E5E8)
    ..strokeWidth = math.max(0.9, minimumStrokeWidth)
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final majorPaint = Paint()
    ..color = const Color(0xFFA8C1C6)
    ..strokeWidth = math.max(1.4, minimumStrokeWidth)
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final dotPaint = Paint()
    ..color = const Color(0xFFB8CDD1)
    ..style = PaintingStyle.fill;

  for (final line in layout.lines) {
    canvas.drawLine(
      line.start,
      line.end,
      line.style == PageTemplateLineStyle.major ? majorPaint : minorPaint,
    );
  }
  final dotRadius = math.max(1.15, minimumStrokeWidth * 0.75);
  for (final dot in layout.dots) {
    canvas.drawCircle(dot, dotRadius, dotPaint);
  }
}
