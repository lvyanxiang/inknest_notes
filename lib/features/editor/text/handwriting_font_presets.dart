import 'package:flutter/foundation.dart';

/// Bundled handwriting fonts shared by typed text and Smart Ink redraw.
@immutable
class HandwritingFontPreset {
  const HandwritingFontPreset({
    required this.id,
    required this.label,
    required this.fontFamily,
    required this.preview,
  });

  final String id;
  final String label;
  final String fontFamily;
  final String preview;
}

class HandwritingFontPresets {
  const HandwritingFontPresets._();

  static const liuJianMaoCao = HandwritingFontPreset(
    id: 'liu_jian_mao_cao',
    label: 'Liu Jian Mao Cao',
    fontFamily: 'LiuJianMaoCao',
    preview: 'Smart Ink',
  );

  static const longCang = HandwritingFontPreset(
    id: 'long_cang',
    label: 'Long Cang',
    fontFamily: 'LongCang',
    preview: 'Smart Ink',
  );

  static const zhiMangXing = HandwritingFontPreset(
    id: 'zhi_mang_xing',
    label: 'Zhi Mang Xing',
    fontFamily: 'ZhiMangXing',
    preview: 'Smart Ink',
  );

  static const values = <HandwritingFontPreset>[
    liuJianMaoCao,
    longCang,
    zhiMangXing,
  ];

  static HandwritingFontPreset byId(String id) {
    return values.firstWhere(
      (font) => font.id == id,
      orElse: () => liuJianMaoCao,
    );
  }
}
