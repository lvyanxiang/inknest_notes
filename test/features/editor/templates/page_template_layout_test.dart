import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/templates/page_template_layout.dart';
import 'package:inknest_notes/models/note_page_template.dart';

void main() {
  const pageSize = Size(768, 1024);

  test('builds the expected geometry type for every page template', () {
    final blank = buildPageTemplateLayout(NotePageTemplate.blank, pageSize);
    final ruled = buildPageTemplateLayout(NotePageTemplate.ruled, pageSize);
    final dotted = buildPageTemplateLayout(NotePageTemplate.dotted, pageSize);
    final grid = buildPageTemplateLayout(NotePageTemplate.grid, pageSize);
    final cornell = buildPageTemplateLayout(NotePageTemplate.cornell, pageSize);
    final planner = buildPageTemplateLayout(NotePageTemplate.planner, pageSize);

    expect(blank.lines, isEmpty);
    expect(blank.dots, isEmpty);
    expect(ruled.lines, isNotEmpty);
    expect(ruled.dots, isEmpty);
    expect(dotted.lines, isEmpty);
    expect(dotted.dots, isNotEmpty);
    expect(grid.lines.any((line) => line.start.dx == line.end.dx), isTrue);
    expect(grid.lines.any((line) => line.start.dy == line.end.dy), isTrue);
    expect(
      cornell.lines.where((line) => line.style == PageTemplateLineStyle.major),
      hasLength(2),
    );
    expect(
      planner.lines.where((line) => line.style == PageTemplateLineStyle.major),
      hasLength(7),
    );
  });
}
