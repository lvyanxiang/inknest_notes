class NoteAudioRecording {
  const NoteAudioRecording({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.createdAt,
    required this.durationMilliseconds,
    this.resolvedFilePath,
  });

  final String id;
  final String title;
  final String assetPath;
  final DateTime createdAt;
  final int durationMilliseconds;

  /// Absolute path resolved at runtime. Only [assetPath] is persisted because
  /// iOS can move an app container between launches.
  final String? resolvedFilePath;

  String get filePath => resolvedFilePath ?? assetPath;

  Duration get duration => Duration(milliseconds: durationMilliseconds);

  factory NoteAudioRecording.fromJson(Map<String, Object?> json) {
    return NoteAudioRecording(
      id: json['id']! as String,
      title: json['title']! as String,
      assetPath: json['assetPath']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      durationMilliseconds: json['durationMilliseconds']! as int,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'assetPath': assetPath,
      'createdAt': createdAt.toIso8601String(),
      'durationMilliseconds': durationMilliseconds,
    };
  }

  NoteAudioRecording copyWith({
    String? title,
    int? durationMilliseconds,
    Object? resolvedFilePath = _resolvedFilePathNotChanged,
  }) {
    return NoteAudioRecording(
      id: id,
      title: title ?? this.title,
      assetPath: assetPath,
      createdAt: createdAt,
      durationMilliseconds: durationMilliseconds ?? this.durationMilliseconds,
      resolvedFilePath: resolvedFilePath == _resolvedFilePathNotChanged
          ? this.resolvedFilePath
          : resolvedFilePath as String?,
    );
  }
}

const Object _resolvedFilePathNotChanged = Object();
