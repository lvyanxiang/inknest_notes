import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_geometry.dart';
import 'package:inknest_notes/features/editor/recognition/font_glyph_stroke_generator.dart';
import 'package:inknest_notes/features/editor/text/handwriting_font_presets.dart';
import 'package:inknest_notes/models/stroke.dart';

Future<void> _loadHandwritingFonts() async {
  Future<void> load(String asset, String family) async {
    final data = await rootBundle.load(asset);
    await loadFontFromList(Uint8List.sublistView(data), fontFamily: family);
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
    const targetBounds = Rect.fromLTWH(40, 60, 120, 120);
    final strokes = await generator.generate(
      text: '美',
      font: HandwritingFontPresets.liuJianMaoCao,
      targetBounds: targetBounds,
      color: const Color(0xFF1E2526),
      strokeWidth: 3,
    );

    expect(strokes, isNotEmpty);
    expect(strokes.every((stroke) => stroke.points.isNotEmpty), isTrue);
    _expectContained(strokes, targetBounds);
    // Scanline packing should cover the glyph with many ink runs.
    expect(strokes.length, greaterThan(8));
  });

  test('supports each bundled beautify font family', () async {
    const generator = FontGlyphStrokeGenerator(maximumDimension: 280);
    for (final font in HandwritingFontPresets.values) {
      final strokes = await generator.generate(
        text: 'A',
        font: font,
        targetBounds: const Rect.fromLTWH(0, 0, 80, 80),
        color: const Color(0xFF2F6F73),
        strokeWidth: 2.5,
      );
      expect(strokes, isNotEmpty, reason: font.label);
      _expectContained(
        strokes,
        const Rect.fromLTWH(0, 0, 80, 80),
        reason: font.label,
      );
    }
  });

  test(
    'contains long single-line text without expanding or wrapping',
    () async {
      const generator = FontGlyphStrokeGenerator(maximumDimension: 720);
      const targetBounds = Rect.fromLTWH(100, 140, 96, 30);

      for (final font in HandwritingFontPresets.values) {
        final strokes = await generator.generate(
          text: '这是一段已经写好的文字',
          font: font,
          targetBounds: targetBounds,
          color: const Color(0xFF1E2526),
          strokeWidth: 3,
        );
        final bounds = _paintedBounds(strokes)!;

        _expectContained(strokes, targetBounds, reason: font.label);
        expect(
          bounds.width / bounds.height,
          greaterThan(2),
          reason: '${font.label} must remain one line',
        );
      }
    },
  );

  test('preserves explicit line breaks inside the fixed target', () async {
    const generator = FontGlyphStrokeGenerator(maximumDimension: 480);
    const targetBounds = Rect.fromLTWH(24, 32, 90, 70);
    final strokes = await generator.generate(
      text: '第一行\n第二行',
      font: HandwritingFontPresets.longCang,
      targetBounds: targetBounds,
      color: const Color(0xFF1E2526),
      strokeWidth: 3,
    );

    expect(strokes, isNotEmpty);
    _expectContained(strokes, targetBounds);
  });
}

void _expectContained(List<Stroke> strokes, Rect container, {String? reason}) {
  expect(_paintedBounds(strokes), _isContainedBy(container), reason: reason);
  expect(
    LassoGeometry.boundsForStrokes(strokes),
    _isContainedBy(container),
    reason: reason,
  );
}

Rect? _paintedBounds(List<Stroke> strokes) {
  Rect? result;
  for (final stroke in strokes) {
    for (final point in stroke.points) {
      final pointBounds = Rect.fromCircle(
        center: point.offset,
        radius: stroke.width / 2,
      );
      result = result == null
          ? pointBounds
          : result.expandToInclude(pointBounds);
    }
  }
  return result;
}

Matcher _isContainedBy(Rect container) {
  const tolerance = 0.01;
  return predicate<Rect?>((bounds) {
    if (bounds == null) return false;
    return bounds.left >= container.left - tolerance &&
        bounds.top >= container.top - tolerance &&
        bounds.right <= container.right + tolerance &&
        bounds.bottom <= container.bottom + tolerance;
  }, 'painted bounds contained by $container');
}
