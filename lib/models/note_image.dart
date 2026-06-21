import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
class NoteImage {
  const NoteImage({
    required this.id,
    required this.position,
    required this.width,
    required this.height,
    required this.assetPath,
    this.resolvedFilePath,
  });

  final String id;
  final Offset position;
  final double width;
  final double height;

  /// Stored path. Prefer notebook-relative values such as
  /// `assets/images/image.png` because iOS can change an app container's
  /// absolute path between installs.
  final String assetPath;
  final String? resolvedFilePath;

  String get filePath => resolvedFilePath ?? assetPath;

  factory NoteImage.fromJson(Map<String, Object?> json) {
    return NoteImage(
      id: json['id']! as String,
      position: Offset(
        (json['x']! as num).toDouble(),
        (json['y']! as num).toDouble(),
      ),
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      assetPath: json['assetPath']! as String,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'x': position.dx,
      'y': position.dy,
      'width': width,
      'height': height,
      'assetPath': assetPath,
    };
  }

  NoteImage copyWith({
    Offset? position,
    double? width,
    double? height,
    String? assetPath,
    String? resolvedFilePath,
  }) {
    return NoteImage(
      id: id,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      assetPath: assetPath ?? this.assetPath,
      resolvedFilePath: resolvedFilePath ?? this.resolvedFilePath,
    );
  }
}
