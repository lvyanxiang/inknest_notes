import 'package:flutter/foundation.dart';

@immutable
class PdfBackground {
  const PdfBackground({
    required this.assetPath,
    required this.pageNumber,
    this.resolvedFilePath,
  });

  /// Stored path. Prefer notebook-relative values such as `assets/imported.pdf`
  /// because iOS can change an app container's absolute path between installs.
  final String assetPath;
  final int pageNumber;
  final String? resolvedFilePath;

  String get filePath => resolvedFilePath ?? assetPath;

  factory PdfBackground.fromJson(Map<String, Object?> json) {
    return PdfBackground(
      assetPath: json['assetPath']! as String,
      pageNumber: json['pageNumber']! as int,
    );
  }

  Map<String, Object?> toJson() {
    return {'assetPath': assetPath, 'pageNumber': pageNumber};
  }

  PdfBackground copyWith({String? assetPath, String? resolvedFilePath}) {
    return PdfBackground(
      assetPath: assetPath ?? this.assetPath,
      pageNumber: pageNumber,
      resolvedFilePath: resolvedFilePath ?? this.resolvedFilePath,
    );
  }
}
