import 'package:inknest_notes/models/pdf_outline_entry.dart';

class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.pageIds = const ['page-1'],
    this.isArchived = false,
    this.folderId,
    this.pdfOutlines = const [],
    this.bookmarkedPageIds = const [],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> pageIds;
  final bool isArchived;
  final String? folderId;
  final List<PdfOutlineEntry> pdfOutlines;
  final List<String> bookmarkedPageIds;

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
      folderId: json['folderId'] as String?,
      pdfOutlines:
          (json['pdfOutlines'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(PdfOutlineEntry.fromJson)
              .toList() ??
          const [],
      bookmarkedPageIds:
          (json['bookmarkedPageIds'] as List<Object?>?)?.cast<String>() ??
          const [],
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
      if (folderId != null) 'folderId': folderId,
      if (pdfOutlines.isNotEmpty)
        'pdfOutlines': pdfOutlines.map((entry) => entry.toJson()).toList(),
      if (bookmarkedPageIds.isNotEmpty) 'bookmarkedPageIds': bookmarkedPageIds,
    };
  }

  Notebook copyWith({
    String? title,
    DateTime? updatedAt,
    List<String>? pageIds,
    bool? isArchived,
    Object? folderId = _folderIdNotChanged,
    List<PdfOutlineEntry>? pdfOutlines,
    List<String>? bookmarkedPageIds,
  }) {
    return Notebook(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pageIds: pageIds ?? this.pageIds,
      isArchived: isArchived ?? this.isArchived,
      folderId: folderId == _folderIdNotChanged
          ? this.folderId
          : folderId as String?,
      pdfOutlines: pdfOutlines ?? this.pdfOutlines,
      bookmarkedPageIds: bookmarkedPageIds ?? this.bookmarkedPageIds,
    );
  }
}

const Object _folderIdNotChanged = Object();
