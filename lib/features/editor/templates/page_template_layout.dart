import 'dart:ui';

import 'package:inknest_notes/models/note_page_template.dart';

enum PageTemplateLineStyle { minor, major }

class PageTemplateLine {
  const PageTemplateLine({
    required this.start,
    required this.end,
    this.style = PageTemplateLineStyle.minor,
  });

  final Offset start;
  final Offset end;
  final PageTemplateLineStyle style;
}

class PageTemplateLayout {
  const PageTemplateLayout({this.lines = const [], this.dots = const []});

  final List<PageTemplateLine> lines;
  final List<Offset> dots;
}

PageTemplateLayout buildPageTemplateLayout(
  NotePageTemplate template,
  Size pageSize,
) {
  if (template == NotePageTemplate.blank || pageSize.isEmpty) {
    return const PageTemplateLayout();
  }

  return switch (template) {
    NotePageTemplate.blank => const PageTemplateLayout(),
    NotePageTemplate.ruled => _ruledLayout(pageSize),
    NotePageTemplate.dotted => _dottedLayout(pageSize),
    NotePageTemplate.grid => _gridLayout(pageSize),
    NotePageTemplate.cornell => _cornellLayout(pageSize),
    NotePageTemplate.planner => _plannerLayout(pageSize),
  };
}

PageTemplateLayout _ruledLayout(Size size) {
  final bounds = _contentBounds(size);
  return PageTemplateLayout(
    lines: _horizontalLines(
      left: bounds.left,
      right: bounds.right,
      top: bounds.top + 24,
      bottom: bounds.bottom,
      spacing: 32,
    ),
  );
}

PageTemplateLayout _dottedLayout(Size size) {
  final bounds = _contentBounds(size);
  final dots = <Offset>[];
  for (var y = bounds.top; y <= bounds.bottom; y += 32) {
    for (var x = bounds.left; x <= bounds.right; x += 32) {
      dots.add(Offset(x, y));
    }
  }
  return PageTemplateLayout(dots: List.unmodifiable(dots));
}

PageTemplateLayout _gridLayout(Size size) {
  final bounds = _contentBounds(size);
  return PageTemplateLayout(
    lines: [
      ..._horizontalLines(
        left: bounds.left,
        right: bounds.right,
        top: bounds.top,
        bottom: bounds.bottom,
        spacing: 32,
      ),
      ..._verticalLines(
        top: bounds.top,
        bottom: bounds.bottom,
        left: bounds.left,
        right: bounds.right,
        spacing: 32,
      ),
    ],
  );
}

PageTemplateLayout _cornellLayout(Size size) {
  final bounds = _contentBounds(size);
  final cueX = size.width * 0.30;
  final summaryY = size.height * 0.80;
  return PageTemplateLayout(
    lines: [
      PageTemplateLine(
        start: Offset(cueX, bounds.top),
        end: Offset(cueX, summaryY),
        style: PageTemplateLineStyle.major,
      ),
      PageTemplateLine(
        start: Offset(bounds.left, summaryY),
        end: Offset(bounds.right, summaryY),
        style: PageTemplateLineStyle.major,
      ),
      ..._horizontalLines(
        left: cueX + 16,
        right: bounds.right,
        top: bounds.top + 32,
        bottom: summaryY - 16,
        spacing: 32,
      ),
      ..._horizontalLines(
        left: bounds.left,
        right: bounds.right,
        top: summaryY + 32,
        bottom: bounds.bottom,
        spacing: 32,
      ),
    ],
  );
}

PageTemplateLayout _plannerLayout(Size size) {
  final bounds = _contentBounds(size);
  final headerBottom = bounds.top + 72;
  final splitX = size.width * 0.66;
  final rightSplitY = headerBottom + (bounds.bottom - headerBottom) * 0.52;
  final majorLines = <PageTemplateLine>[
    PageTemplateLine(
      start: bounds.topLeft,
      end: bounds.topRight,
      style: PageTemplateLineStyle.major,
    ),
    PageTemplateLine(
      start: bounds.topRight,
      end: bounds.bottomRight,
      style: PageTemplateLineStyle.major,
    ),
    PageTemplateLine(
      start: bounds.bottomRight,
      end: bounds.bottomLeft,
      style: PageTemplateLineStyle.major,
    ),
    PageTemplateLine(
      start: bounds.bottomLeft,
      end: bounds.topLeft,
      style: PageTemplateLineStyle.major,
    ),
    PageTemplateLine(
      start: Offset(bounds.left, headerBottom),
      end: Offset(bounds.right, headerBottom),
      style: PageTemplateLineStyle.major,
    ),
    PageTemplateLine(
      start: Offset(splitX, headerBottom),
      end: Offset(splitX, bounds.bottom),
      style: PageTemplateLineStyle.major,
    ),
    PageTemplateLine(
      start: Offset(splitX, rightSplitY),
      end: Offset(bounds.right, rightSplitY),
      style: PageTemplateLineStyle.major,
    ),
  ];
  return PageTemplateLayout(
    lines: [
      ...majorLines,
      ..._horizontalLines(
        left: bounds.left,
        right: splitX,
        top: headerBottom + 40,
        bottom: bounds.bottom,
        spacing: 48,
      ),
      ..._horizontalLines(
        left: splitX + 16,
        right: bounds.right - 16,
        top: headerBottom + 32,
        bottom: rightSplitY - 16,
        spacing: 32,
      ),
      ..._horizontalLines(
        left: splitX + 16,
        right: bounds.right - 16,
        top: rightSplitY + 32,
        bottom: bounds.bottom - 16,
        spacing: 32,
      ),
    ],
  );
}

Rect _contentBounds(Size size) {
  final horizontalMargin = (size.width * 0.06).clamp(24.0, 48.0);
  final verticalMargin = (size.height * 0.05).clamp(24.0, 52.0);
  return Rect.fromLTRB(
    horizontalMargin,
    verticalMargin,
    size.width - horizontalMargin,
    size.height - verticalMargin,
  );
}

List<PageTemplateLine> _horizontalLines({
  required double left,
  required double right,
  required double top,
  required double bottom,
  required double spacing,
}) {
  return [
    for (var y = top; y <= bottom; y += spacing)
      PageTemplateLine(start: Offset(left, y), end: Offset(right, y)),
  ];
}

List<PageTemplateLine> _verticalLines({
  required double top,
  required double bottom,
  required double left,
  required double right,
  required double spacing,
}) {
  return [
    for (var x = left; x <= right; x += spacing)
      PageTemplateLine(start: Offset(x, top), end: Offset(x, bottom)),
  ];
}
