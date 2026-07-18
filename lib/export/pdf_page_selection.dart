class PdfPageSelectionParseResult {
  const PdfPageSelectionParseResult._({
    required this.pageNumbers,
    this.errorMessage,
  });

  const PdfPageSelectionParseResult.valid(List<int> pageNumbers)
    : this._(pageNumbers: pageNumbers);

  const PdfPageSelectionParseResult.invalid(String errorMessage)
    : this._(pageNumbers: const [], errorMessage: errorMessage);

  final List<int> pageNumbers;
  final String? errorMessage;

  bool get isValid => errorMessage == null;
}

PdfPageSelectionParseResult parsePdfPageSelection(
  String input, {
  required int pageCount,
}) {
  if (pageCount < 1) {
    return const PdfPageSelectionParseResult.invalid(
      'This notebook has no pages to export.',
    );
  }

  final normalizedInput = input
      .trim()
      .replaceAll('，', ',')
      .replaceAll(RegExp('[–—]'), '-');
  if (normalizedInput.isEmpty) {
    return const PdfPageSelectionParseResult.invalid(
      'Enter pages such as 1,3,5-7.',
    );
  }

  final pageNumbers = <int>[];
  final seenPageNumbers = <int>{};

  for (final rawPart in normalizedInput.split(',')) {
    final part = rawPart.trim();
    if (part.isEmpty) {
      return const PdfPageSelectionParseResult.invalid(
        'Use page numbers and ranges such as 1,3,5-7.',
      );
    }

    final singlePage = int.tryParse(part);
    if (singlePage != null) {
      if (!_isPageNumberInBounds(singlePage, pageCount)) {
        return PdfPageSelectionParseResult.invalid(
          'Pages must be between 1 and $pageCount.',
        );
      }
      if (seenPageNumbers.add(singlePage)) {
        pageNumbers.add(singlePage);
      }
      continue;
    }

    final rangeMatch = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(part);
    if (rangeMatch == null) {
      return const PdfPageSelectionParseResult.invalid(
        'Use page numbers and ranges such as 1,3,5-7.',
      );
    }

    final start = int.tryParse(rangeMatch.group(1)!);
    final end = int.tryParse(rangeMatch.group(2)!);
    if (start == null || end == null) {
      return const PdfPageSelectionParseResult.invalid(
        'Use page numbers and ranges such as 1,3,5-7.',
      );
    }
    if (!_isPageNumberInBounds(start, pageCount) ||
        !_isPageNumberInBounds(end, pageCount)) {
      return PdfPageSelectionParseResult.invalid(
        'Pages must be between 1 and $pageCount.',
      );
    }
    if (start > end) {
      return const PdfPageSelectionParseResult.invalid(
        'Page ranges must use ascending order.',
      );
    }

    for (var pageNumber = start; pageNumber <= end; pageNumber++) {
      if (seenPageNumbers.add(pageNumber)) {
        pageNumbers.add(pageNumber);
      }
    }
  }

  return PdfPageSelectionParseResult.valid(List.unmodifiable(pageNumbers));
}

bool _isPageNumberInBounds(int pageNumber, int pageCount) {
  return pageNumber >= 1 && pageNumber <= pageCount;
}
