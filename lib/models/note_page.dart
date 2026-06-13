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

  NotePage copyWith({List<Stroke>? strokes}) {
    return NotePage(
      id: id,
      width: width,
      height: height,
      strokes: strokes ?? this.strokes,
    );
  }
}
