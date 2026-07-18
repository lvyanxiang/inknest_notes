import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_page_template.dart';

void main() {
  test('persists page templates and defaults older pages to blank', () {
    const page = NotePage(
      id: 'page-1',
      width: 768,
      height: 1024,
      rotationQuarterTurns: 1,
      template: NotePageTemplate.cornell,
    );

    final reloaded = NotePage.fromJson(page.toJson());
    final legacyPage = NotePage.fromJson({
      'id': 'page-legacy',
      'width': 768,
      'height': 1024,
      'strokes': <Object?>[],
    });

    expect(reloaded.template, NotePageTemplate.cornell);
    expect(reloaded.rotationQuarterTurns, 1);
    expect(reloaded.displayWidth, 1024);
    expect(reloaded.displayHeight, 768);
    expect(legacyPage.template, NotePageTemplate.blank);
    expect(legacyPage.rotationQuarterTurns, 0);
    expect(legacyPage.displayWidth, 768);
    expect(legacyPage.displayHeight, 1024);
  });

  test('falls back to blank for unknown future template values', () {
    final page = NotePage.fromJson({
      'id': 'page-1',
      'width': 768,
      'height': 1024,
      'template': 'unknown-template',
      'strokes': <Object?>[],
    });

    expect(page.template, NotePageTemplate.blank);
  });

  test('normalizes persisted page rotation to a valid quarter turn', () {
    final page = NotePage.fromJson({
      'id': 'page-1',
      'width': 768,
      'height': 1024,
      'rotationQuarterTurns': -1,
      'strokes': <Object?>[],
    });

    expect(page.rotationQuarterTurns, 3);
    expect(page.isSideways, isTrue);
  });
}
