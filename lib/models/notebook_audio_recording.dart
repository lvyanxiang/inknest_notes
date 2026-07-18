import 'package:flutter/foundation.dart';

@immutable
class NotebookAudioRecording {
  const NotebookAudioRecording({
    required this.id,
    required this.createdAt,
    required this.duration,
    required this.assetPath,
    this.pageId,
    this.resolvedFilePath,
  });

  final String id;
  final DateTime createdAt;
  final Duration duration;
  final String assetPath;
  final String? pageId;

  /// Stored path. Prefer notebook-relative values such as
  /// `assets/audio/recording.m4a` because mobile app containers can move
  /// between installs.
  final String? resolvedFilePath;

  String get filePath => resolvedFilePath ?? assetPath;

  factory NotebookAudioRecording.fromJson(Map<String, Object?> json) {
    return NotebookAudioRecording(
      id: json['id']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.round() ?? 0,
      ),
      assetPath: json['assetPath']! as String,
      pageId: json['pageId'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'durationMs': duration.inMilliseconds,
      'assetPath': assetPath,
      if (pageId != null) 'pageId': pageId,
    };
  }

  NotebookAudioRecording copyWith({
    DateTime? createdAt,
    Duration? duration,
    String? assetPath,
    Object? pageId = _pageIdNotChanged,
    Object? resolvedFilePath = _resolvedFilePathNotChanged,
  }) {
    return NotebookAudioRecording(
      id: id,
      createdAt: createdAt ?? this.createdAt,
      duration: duration ?? this.duration,
      assetPath: assetPath ?? this.assetPath,
      pageId: pageId == _pageIdNotChanged ? this.pageId : pageId as String?,
      resolvedFilePath: resolvedFilePath == _resolvedFilePathNotChanged
          ? this.resolvedFilePath
          : resolvedFilePath as String?,
    );
  }
}

const Object _pageIdNotChanged = Object();
const Object _resolvedFilePathNotChanged = Object();
