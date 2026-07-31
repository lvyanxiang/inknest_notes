import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/recognition/font_glyph_stroke_generator.dart';
import 'package:inknest_notes/features/editor/recognition/ink_beautify_fonts.dart';

Future<void> _loadHandwritingFonts() async {
  Future<void> load(String asset, String family) async {
    final data = await rootBundle.load(asset);
    await loadFontFromList(
      Uint8List.sublistView(data),
      fontFamily: family,
    );
  }

  await load(
    'assets/fonts/handwriting/LiuJianMaoCao-Regular.ttf',
    'LiuJianMaoCao',
  );
  await load('assets/fonts/handwriting/LongCang-Regular.ttf', 'LongCang');
  await load('assets/fonts/handwriting/ZhiMangXing-Regular.ttf', 'ZhiMangXing');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadHandwritingFonts);

  test('generates page-space strokes from bundled handwriting fonts', () async {
    const generator = FontGlyphStrokeGenerator(maximumDimension: 320);
    final strokes = await generator.generate(
      text: '美',
      font: InkBeautifyFonts.liuJianMaoCao,
      targetBounds: const Rect.fromLTWH(40, 60, 120, 120),
      color: const Color(0xFF1E2526),
      strokeWidth: 3,
    );

    expect(strokes, isNotEmpty);
    expect(strokes.every((stroke) => stroke.points.isNotEmpty), isTrue);
    expect(
      strokes.every(
        (stroke) => stroke.points.every(
          (point) =>
              point.offset.dx >= 30 &&
              point.offset.dx <= 170 &&
              point.offset.dy >= 50 &&
              point.offset.dy <= 190,
        ),
      ),
      isTrue,
    );
    // Scanline packing should cover the glyph with many ink runs.
    expect(strokes.length, greaterThan(8));
  });

  test('supports each bundled beautify font family', () async {
    const generator = FontGlyphStrokeGenerator(maximumDimension: 280);
    for (final font in InkBeautifyFonts.values) {
      final strokes = await generator.generate(
        text: 'A',
        font: font,
        targetBounds: const Rect.fromLTWH(0, 0, 80, 80),
        color: const Color(0xFF2F6F73),
        strokeWidth: 2.5,
      );
      expect(strokes, isNotEmpty, reason: font.label);
    }
  });
}
