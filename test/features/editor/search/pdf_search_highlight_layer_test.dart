import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/search/pdf_search_highlight_layer.dart';

void main() {
  test('scales model-page PDF highlights into the fitted canvas', () {
    final rects = scalePdfSearchHighlightRects(
      rects: const [Rect.fromLTRB(120, 220, 320, 330)],
      referencePageSize: const Size(800, 1100),
      canvasSize: const Size(400, 550),
    );

    expect(rects, const [Rect.fromLTRB(60, 110, 160, 165)]);
  });

  test('clips scaled PDF highlights to the visible canvas', () {
    final rects = scalePdfSearchHighlightRects(
      rects: const [Rect.fromLTRB(-20, 1000, 840, 1140)],
      referencePageSize: const Size(800, 1100),
      canvasSize: const Size(400, 550),
    );

    expect(rects, const [Rect.fromLTRB(0, 500, 400, 550)]);
  });
}
