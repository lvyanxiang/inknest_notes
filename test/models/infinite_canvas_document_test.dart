import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  test('legacy notebook JSON defaults to paged layout', () {
    final notebook = Notebook.fromJson({
      'id': 'legacy',
      'title': 'Legacy',
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'pageIds': ['page-1'],
    });

    expect(notebook.layoutMode, NotebookLayoutMode.paged);
  });

  test('infinite canvas document round-trips world and viewport state', () {
    final document = InfiniteCanvasDocument(
      background: InfiniteCanvasBackground.grid,
      viewportFocus: const Offset(-240, 960),
      viewportScale: 2.25,
      strokes: [
        Stroke(
          id: 'ink-1',
          tool: ToolType.pen,
          color: const Color(0xFF123456),
          width: 4,
          points: [
            StrokePoint(
              offset: const Offset(-1000, 3200),
              pressure: 0.7,
              time: DateTime.utc(2026, 8, 3),
            ),
          ],
        ),
      ],
    );

    final restored = InfiniteCanvasDocument.fromJson(document.toJson());
    expect(restored.background, InfiniteCanvasBackground.grid);
    expect(restored.viewportFocus, const Offset(-240, 960));
    expect(restored.viewportScale, 2.25);
    expect(
      restored.strokes.single.points.single.offset,
      const Offset(-1000, 3200),
    );
  });
}
