import 'package:flutter/foundation.dart';

/// Bundled handwriting fonts used to redraw selected ink as strokes.
@immutable
class InkBeautifyFont {
  const InkBeautifyFont({
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

class InkBeautifyFonts {
  const InkBeautifyFonts._();

  static const liuJianMaoCao = InkBeautifyFont(
    id: 'liu_jian_mao_cao',
    label: '刘建毛草',
    fontFamily: 'LiuJianMaoCao',
    preview: '美化笔迹',
  );

  static const longCang = InkBeautifyFont(
    id: 'long_cang',
    label: '龙藏',
    fontFamily: 'LongCang',
    preview: '美化笔迹',
  );

  static const zhiMangXing = InkBeautifyFont(
    id: 'zhi_mang_xing',
    label: '芝麻行',
    fontFamily: 'ZhiMangXing',
    preview: '美化笔迹',
  );

  static const values = <InkBeautifyFont>[
    liuJianMaoCao,
    longCang,
    zhiMangXing,
  ];

  static InkBeautifyFont byId(String id) {
    return values.firstWhere(
      (font) => font.id == id,
      orElse: () => liuJianMaoCao,
    );
  }
}
