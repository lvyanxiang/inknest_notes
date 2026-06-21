import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';

@immutable
class NotePage {
  const NotePage({
    required this.id,
    required this.width,
    required this.height,
    this.pdfBackground,
    this.strokes = const [],
    this.textBoxes = const [],
    this.images = const [],
  });

  final String id;
  final double width;
  final double height;
  final PdfBackground? pdfBackground;
  final List<Stroke> strokes;
  final List<NoteTextBox> textBoxes;
  final List<NoteImage> images;

  factory NotePage.fromJson(Map<String, Object?> json) {
    return NotePage(
      id: json['id']! as String,
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      pdfBackground: json['pdfBackground'] == null
          ? null
          : PdfBackground.fromJson(
              json['pdfBackground']! as Map<String, Object?>,
            ),
      strokes: (json['strokes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(Stroke.fromJson)
          .toList(),
      textBoxes: ((json['textBoxes'] as List<Object?>?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(NoteTextBox.fromJson)
          .toList(),
      images: ((json['images'] as List<Object?>?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(NoteImage.fromJson)
          .toList(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'width': width,
      'height': height,
      if (pdfBackground != null) 'pdfBackground': pdfBackground!.toJson(),
      'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
      'textBoxes': textBoxes.map((textBox) => textBox.toJson()).toList(),
      'images': images.map((image) => image.toJson()).toList(),
    };
  }

  NotePage copyWith({
    PdfBackground? pdfBackground,
    List<Stroke>? strokes,
    List<NoteTextBox>? textBoxes,
    List<NoteImage>? images,
  }) {
    return NotePage(
      id: id,
      width: width,
      height: height,
      pdfBackground: pdfBackground ?? this.pdfBackground,
      strokes: strokes ?? this.strokes,
      textBoxes: textBoxes ?? this.textBoxes,
      images: images ?? this.images,
    );
  }
}
