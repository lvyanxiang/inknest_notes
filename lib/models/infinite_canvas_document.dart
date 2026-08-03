import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/stroke.dart';

enum InfiniteCanvasBackground { blank, dotted, grid }

@immutable
class InfiniteCanvasDocument {
  const InfiniteCanvasDocument({
    this.strokes = const [],
    this.background = InfiniteCanvasBackground.blank,
    this.viewportFocus = Offset.zero,
    this.viewportScale = 1,
  });

  final List<Stroke> strokes;
  final InfiniteCanvasBackground background;
  final Offset viewportFocus;
  final double viewportScale;

  factory InfiniteCanvasDocument.fromJson(Map<String, Object?> json) {
    final focus = json['viewportFocus'] as Map<String, Object?>?;
    final backgroundName = json['background'] as String?;
    return InfiniteCanvasDocument(
      strokes:
          (json['strokes'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(Stroke.fromJson)
              .toList() ??
          const [],
      background: InfiniteCanvasBackground.values.firstWhere(
        (value) => value.name == backgroundName,
        orElse: () => InfiniteCanvasBackground.blank,
      ),
      viewportFocus: focus == null
          ? Offset.zero
          : Offset(
              (focus['dx'] as num?)?.toDouble() ?? 0,
              (focus['dy'] as num?)?.toDouble() ?? 0,
            ),
      viewportScale: ((json['viewportScale'] as num?)?.toDouble() ?? 1)
          .clamp(0.2, 6)
          .toDouble(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
      'background': background.name,
      'viewportFocus': {'dx': viewportFocus.dx, 'dy': viewportFocus.dy},
      'viewportScale': viewportScale,
    };
  }

  InfiniteCanvasDocument copyWith({
    List<Stroke>? strokes,
    InfiniteCanvasBackground? background,
    Offset? viewportFocus,
    double? viewportScale,
  }) {
    return InfiniteCanvasDocument(
      strokes: strokes ?? this.strokes,
      background: background ?? this.background,
      viewportFocus: viewportFocus ?? this.viewportFocus,
      viewportScale: viewportScale ?? this.viewportScale,
    );
  }
}
