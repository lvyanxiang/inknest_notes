import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
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
      textBoxes: const [
        NoteTextBox(
          id: 'text-1',
          position: Offset(-800, 120),
          text: 'Canvas idea',
        ),
      ],
      images: const [
        NoteImage(
          id: 'image-1',
          position: Offset(400, -600),
          width: 320,
          height: 180,
          assetPath: 'assets/images/idea.png',
        ),
      ],
      shapes: const [
        NoteShape(
          id: 'shape-1',
          type: NoteShapeType.arrow,
          start: Offset(-20, -30),
          end: Offset(240, 180),
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
    expect(restored.textBoxes.single.text, 'Canvas idea');
    expect(restored.textBoxes.single.position, const Offset(-800, 120));
    expect(restored.images.single.position, const Offset(400, -600));
    expect(restored.shapes.single.type, NoteShapeType.arrow);
  });
}
