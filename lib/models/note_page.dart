import 'package:flutter/foundation.dart';
import 'package:inknest_notes/models/stroke.dart';

@immutable
class NotePage {
  const NotePage({
    required this.id,
    required this.width,
    required this.height,
    this.strokes = const [],
  });

  final String id;
  final double width;
  final double height;
  final List<Stroke> strokes;

  factory NotePage.fromJson(Map<String, Object?> json) {
    return NotePage(
      id: json['id']! as String,
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      strokes: (json['strokes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(Stroke.fromJson)
          .toList(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'width': width,
      'height': height,
      'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    };
  }

  NotePage copyWith({List<Stroke>? strokes}) {
    return NotePage(
      id: id,
      width: width,
      height: height,
      strokes: strokes ?? this.strokes,
    );
  }
}
