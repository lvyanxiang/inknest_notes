import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
class StrokePoint {
  const StrokePoint({
    required this.offset,
    required this.pressure,
    required this.time,
  });

  final Offset offset;
  final double pressure;
  final DateTime time;

  factory StrokePoint.fromJson(Map<String, Object?> json) {
    return StrokePoint(
      offset: Offset(
        (json['x']! as num).toDouble(),
        (json['y']! as num).toDouble(),
      ),
      pressure: (json['pressure']! as num).toDouble(),
      time: DateTime.parse(json['time']! as String),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'x': offset.dx,
      'y': offset.dy,
      'pressure': pressure,
      'time': time.toIso8601String(),
    };
  }
}
