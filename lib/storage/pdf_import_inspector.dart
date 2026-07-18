import 'dart:io';

import 'package:inknest_notes/models/pdf_outline_entry.dart';
import 'package:pdfrx/pdfrx.dart';

abstract class PdfImportInspector {
  Future<PdfImportInspection> inspect(File sourceFile);
}

class PdfrxPdfImportInspector implements PdfImportInspector {
  const PdfrxPdfImportInspector();

  @override
  Future<PdfImportInspection> inspect(File sourceFile) async {
    final document = await PdfDocument.openFile(sourceFile.path);
    try {
      List<PdfImportOutlineNode> outlines;
      try {
        outlines = [
          for (final node in await document.loadOutline())
            _mapOutlineNode(node),
        ];
      } catch (_) {
        outlines = const [];
      }
      return PdfImportInspection(
        pageCount: document.pages.length,
        outlines: outlines,
      );
    } finally {
      await document.dispose();
    }
  }

  PdfImportOutlineNode _mapOutlineNode(PdfOutlineNode node) {
    return PdfImportOutlineNode(
      title: node.title.trim().isEmpty ? 'Untitled' : node.title.trim(),
      pageNumber: node.dest?.pageNumber,
      children: [for (final child in node.children) _mapOutlineNode(child)],
    );
  }
}

class PdfImportInspection {
  const PdfImportInspection({
    required this.pageCount,
    this.outlines = const [],
  });

  final int pageCount;
  final List<PdfImportOutlineNode> outlines;

  List<PdfOutlineEntry> buildOutlineEntries(List<String> pageIds) {
    return [for (final outline in outlines) ?outline.toOutlineEntry(pageIds)];
  }
}

class PdfImportOutlineNode {
  const PdfImportOutlineNode({
    required this.title,
    this.pageNumber,
    this.children = const [],
  });

  final String title;
  final int? pageNumber;
  final List<PdfImportOutlineNode> children;

  PdfOutlineEntry? toOutlineEntry(List<String> pageIds) {
    final pageNumber = this.pageNumber;
    final pageId =
        pageNumber == null || pageNumber < 1 || pageNumber > pageIds.length
        ? null
        : pageIds[pageNumber - 1];
    final childEntries = [
      for (final child in children) ?child.toOutlineEntry(pageIds),
    ];
    if (pageId == null && childEntries.isEmpty) {
      return null;
    }
    return PdfOutlineEntry(
      title: title.trim().isEmpty ? 'Untitled' : title.trim(),
      pageId: pageId,
      children: childEntries,
    );
  }
}
