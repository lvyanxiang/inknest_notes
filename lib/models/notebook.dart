class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.pageIds = const ['page-1'],
    this.isArchived = false,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> pageIds;
  final bool isArchived;

  factory Notebook.fromJson(Map<String, Object?> json) {
    return Notebook(
      id: json['id']! as String,
      title: json['title']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      pageIds:
          (json['pageIds'] as List<Object?>?)?.cast<String>() ??
          const ['page-1'],
      isArchived: json['isArchived'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'pageIds': pageIds,
      'isArchived': isArchived,
    };
  }

  Notebook copyWith({
    String? title,
    DateTime? updatedAt,
    List<String>? pageIds,
    bool? isArchived,
  }) {
    return Notebook(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pageIds: pageIds ?? this.pageIds,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
