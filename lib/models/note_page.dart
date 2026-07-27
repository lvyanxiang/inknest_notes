import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page_template.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:inknest_notes/models/stroke.dart';

enum NotePageCoordinateSpaceStatus { legacy, canonical, unsupported }

@immutable
class NotePage {
  const NotePage({
    required this.id,
    required this.width,
    required this.height,
    this.coordinateSpaceVersion = canonicalCoordinateSpaceVersion,
    this.rotationQuarterTurns = 0,
    this.template = NotePageTemplate.blank,
    this.pdfBackground,
    this.strokes = const [],
    this.textBoxes = const [],
    this.images = const [],
    this.shapes = const [],
  }) : _unsupportedCoordinateSpaceVersion = null,
       assert(rotationQuarterTurns >= 0 && rotationQuarterTurns < 4);

  const NotePage._fromPersistedJson({
    required this.id,
    required this.width,
    required this.height,
    required this.coordinateSpaceVersion,
    required this._unsupportedCoordinateSpaceVersion,
    required this.rotationQuarterTurns,
    required this.template,
    required this.pdfBackground,
    required this.strokes,
    required this.textBoxes,
    required this.images,
    required this.shapes,
  }) : assert(rotationQuarterTurns >= 0 && rotationQuarterTurns < 4);

  static const int legacyCoordinateSpaceVersion = 0;
  static const int canonicalCoordinateSpaceVersion = 1;

  final String id;
  final double width;
  final double height;

  /// The persisted integer coordinate-space version.
  ///
  /// This is `null` only when the JSON value exists but is not an integer.
  /// Use [persistedCoordinateSpaceVersion] when diagnostics need the original
  /// unsupported value.
  final int? coordinateSpaceVersion;
  final Object? _unsupportedCoordinateSpaceVersion;

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

  Object? get persistedCoordinateSpaceVersion =>
      coordinateSpaceVersion ?? _unsupportedCoordinateSpaceVersion;

  NotePageCoordinateSpaceStatus get coordinateSpaceStatus {
    return switch (coordinateSpaceVersion) {
      legacyCoordinateSpaceVersion => NotePageCoordinateSpaceStatus.legacy,
      canonicalCoordinateSpaceVersion =>
        NotePageCoordinateSpaceStatus.canonical,
      _ => NotePageCoordinateSpaceStatus.unsupported,
    };
  }

  bool get usesCanonicalCoordinateSpace =>
      coordinateSpaceStatus == NotePageCoordinateSpaceStatus.canonical;

  bool get hasCoordinateBearingContent =>
      strokes.isNotEmpty ||
      textBoxes.isNotEmpty ||
      images.isNotEmpty ||
      shapes.isNotEmpty;

  bool get canSafelyUpgradeCoordinateSpace =>
      coordinateSpaceStatus == NotePageCoordinateSpaceStatus.legacy &&
      !hasCoordinateBearingContent;

  bool get isCoordinateSpaceWriteProtected =>
      !usesCanonicalCoordinateSpace && !canSafelyUpgradeCoordinateSpace;

  NotePage upgradeEmptyLegacyCoordinateSpace() {
    if (!canSafelyUpgradeCoordinateSpace) {
      return this;
    }
    return copyWith(coordinateSpaceVersion: canonicalCoordinateSpaceVersion);
  }

  factory NotePage.fromJson(Map<String, Object?> json) {
    final persistedCoordinateSpaceVersion =
        json.containsKey('coordinateSpaceVersion')
        ? json['coordinateSpaceVersion']
        : legacyCoordinateSpaceVersion;
    final integerCoordinateSpaceVersion = persistedCoordinateSpaceVersion is int
        ? persistedCoordinateSpaceVersion
        : null;

    return NotePage._fromPersistedJson(
      id: json['id']! as String,
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      coordinateSpaceVersion: integerCoordinateSpaceVersion,
      unsupportedCoordinateSpaceVersion: integerCoordinateSpaceVersion == null
          ? persistedCoordinateSpaceVersion
          : null,
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
      'coordinateSpaceVersion': persistedCoordinateSpaceVersion,
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
    int? coordinateSpaceVersion,
    int? rotationQuarterTurns,
    NotePageTemplate? template,
    PdfBackground? pdfBackground,
    List<Stroke>? strokes,
    List<NoteTextBox>? textBoxes,
    List<NoteImage>? images,
    List<NoteShape>? shapes,
  }) {
    return NotePage._fromPersistedJson(
      id: id,
      width: width,
      height: height,
      coordinateSpaceVersion:
          coordinateSpaceVersion ?? this.coordinateSpaceVersion,
      unsupportedCoordinateSpaceVersion: coordinateSpaceVersion == null
          ? _unsupportedCoordinateSpaceVersion
          : null,
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
