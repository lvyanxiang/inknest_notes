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
}
