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
    label: '刘建毛草',
    fontFamily: 'LiuJianMaoCao',
    preview: '美化笔迹',
  );

  static const longCang = HandwritingFontPreset(
    id: 'long_cang',
    label: '龙藏',
    fontFamily: 'LongCang',
    preview: '美化笔迹',
  );

  static const zhiMangXing = HandwritingFontPreset(
    id: 'zhi_mang_xing',
    label: '芝麻行',
    fontFamily: 'ZhiMangXing',
    preview: '美化笔迹',
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
