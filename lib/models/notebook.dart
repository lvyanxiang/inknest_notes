class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.pageIds = const ['page-1'],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> pageIds;

  factory Notebook.fromJson(Map<String, Object?> json) {
    return Notebook(
      id: json['id']! as String,
      title: json['title']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      pageIds:
          (json['pageIds'] as List<Object?>?)?.cast<String>() ??
          const ['page-1'],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'pageIds': pageIds,
    };
  }

  Notebook copyWith({DateTime? updatedAt, List<String>? pageIds}) {
    return Notebook(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pageIds: pageIds ?? this.pageIds,
    );
  }
}
