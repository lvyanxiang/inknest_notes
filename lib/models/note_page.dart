import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page_template.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';

@immutable
class NotePage {
  const NotePage({
    required this.id,
    required this.width,
    required this.height,
    this.rotationQuarterTurns = 0,
    this.template = NotePageTemplate.blank,
    this.pdfBackground,
    this.strokes = const [],
    this.textBoxes = const [],
    this.images = const [],
    this.shapes = const [],
  }) : assert(rotationQuarterTurns >= 0 && rotationQuarterTurns < 4);

  final String id;
  final double width;
  final double height;
  final int rotationQuarterTurns;
  final NotePageTemplate template;
  final PdfBackground? pdfBackground;
  final List<Stroke> strokes;
  final List<NoteTextBox> textBoxes;
  final List<NoteImage> images;
  final List<NoteShape> shapes;

  bool get isSideways => rotationQuarterTurns.isOdd;

  double get displayWidth => isSideways ? height : width;

  double get displayHeight => isSideways ? width : height;

  factory NotePage.fromJson(Map<String, Object?> json) {
    return NotePage(
      id: json['id']! as String,
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      rotationQuarterTurns: _rotationQuarterTurnsFromJson(
        json['rotationQuarterTurns'],
      ),
      template: notePageTemplateFromJson(json['template']),
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
      shapes: ((json['shapes'] as List<Object?>?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(NoteShape.fromJson)
          .toList(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'width': width,
      'height': height,
      if (rotationQuarterTurns != 0)
        'rotationQuarterTurns': rotationQuarterTurns,
      if (template != NotePageTemplate.blank) 'template': template.name,
      if (pdfBackground != null) 'pdfBackground': pdfBackground!.toJson(),
      'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
      'textBoxes': textBoxes.map((textBox) => textBox.toJson()).toList(),
      'images': images.map((image) => image.toJson()).toList(),
      'shapes': shapes.map((shape) => shape.toJson()).toList(),
    };
  }

  NotePage copyWith({
    int? rotationQuarterTurns,
    NotePageTemplate? template,
    PdfBackground? pdfBackground,
    List<Stroke>? strokes,
    List<NoteTextBox>? textBoxes,
    List<NoteImage>? images,
    List<NoteShape>? shapes,
  }) {
    return NotePage(
      id: id,
      width: width,
      height: height,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      template: template ?? this.template,
      pdfBackground: pdfBackground ?? this.pdfBackground,
      strokes: strokes ?? this.strokes,
      textBoxes: textBoxes ?? this.textBoxes,
      images: images ?? this.images,
      shapes: shapes ?? this.shapes,
    );
  }
}

int _rotationQuarterTurnsFromJson(Object? value) {
  if (value is! num) {
    return 0;
  }
  final normalized = value.toInt() % 4;
  return normalized < 0 ? normalized + 4 : normalized;
}
