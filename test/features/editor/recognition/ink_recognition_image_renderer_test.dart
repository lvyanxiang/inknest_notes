import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:inknest_notes/features/editor/recognition/ink_recognition_image_renderer.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  test('renders selected strokes as a bounded PNG OCR input', () async {
    final renderedBytes = await const InkRecognitionImageRenderer().render([
      Stroke(
        id: 'stroke-1',
        tool: ToolType.pen,
        color: Colors.teal,
        width: 4,
        points: [
          StrokePoint(
            offset: const Offset(20, 30),
            pressure: 1,
            time: DateTime.utc(2026, 7, 18),
          ),
          StrokePoint(
            offset: const Offset(120, 80),
            pressure: 1,
            time: DateTime.utc(2026, 7, 18, 0, 0, 1),
          ),
        ],
      ),
    ]);

    expect(renderedBytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final decodedImage = image.decodePng(renderedBytes);
    expect(decodedImage, isNotNull);
    expect(decodedImage!.width, inInclusiveRange(1, 2048));
    expect(decodedImage.height, inInclusiveRange(1, 2048));
    expect(decodedImage.width, greaterThan(decodedImage.height));
  });
}
