import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/stroke.dart';

enum InfiniteCanvasBackground { blank, dotted, grid }

@immutable
class InfiniteCanvasDocument {
  const InfiniteCanvasDocument({
    this.strokes = const [],
    this.textBoxes = const [],
    this.images = const [],
    this.shapes = const [],
    this.background = InfiniteCanvasBackground.blank,
    this.viewportFocus = Offset.zero,
    this.viewportScale = 1,
  });

  final List<Stroke> strokes;
  final List<NoteTextBox> textBoxes;
  final List<NoteImage> images;
  final List<NoteShape> shapes;
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
      textBoxes:
          (json['textBoxes'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(NoteTextBox.fromJson)
              .toList() ??
          const [],
      images:
          (json['images'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(NoteImage.fromJson)
              .toList() ??
          const [],
      shapes:
          (json['shapes'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(NoteShape.fromJson)
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
      'textBoxes': textBoxes.map((textBox) => textBox.toJson()).toList(),
      'images': images.map((image) => image.toJson()).toList(),
      'shapes': shapes.map((shape) => shape.toJson()).toList(),
      'background': background.name,
      'viewportFocus': {'dx': viewportFocus.dx, 'dy': viewportFocus.dy},
      'viewportScale': viewportScale,
    };
  }

  InfiniteCanvasDocument copyWith({
    List<Stroke>? strokes,
    List<NoteTextBox>? textBoxes,
    List<NoteImage>? images,
    List<NoteShape>? shapes,
    InfiniteCanvasBackground? background,
    Offset? viewportFocus,
    double? viewportScale,
  }) {
    return InfiniteCanvasDocument(
      strokes: strokes ?? this.strokes,
      textBoxes: textBoxes ?? this.textBoxes,
      images: images ?? this.images,
      shapes: shapes ?? this.shapes,
      background: background ?? this.background,
      viewportFocus: viewportFocus ?? this.viewportFocus,
      viewportScale: viewportScale ?? this.viewportScale,
    );
  }
}
