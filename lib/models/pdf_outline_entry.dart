class PdfOutlineEntry {
  const PdfOutlineEntry({
    required this.title,
    this.pageId,
    this.children = const [],
  });

  final String title;
  final String? pageId;
  final List<PdfOutlineEntry> children;

  factory PdfOutlineEntry.fromJson(Map<String, Object?> json) {
    return PdfOutlineEntry(
      title: json['title']! as String,
      pageId: json['pageId'] as String?,
      children:
          (json['children'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(PdfOutlineEntry.fromJson)
              .toList() ??
          const [],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      if (pageId != null) 'pageId': pageId,
      if (children.isNotEmpty)
        'children': children.map((entry) => entry.toJson()).toList(),
    };
  }
}
