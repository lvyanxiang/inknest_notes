import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  test('new pages use canonical coordinate space v1', () {
    const page = NotePage(id: 'page-1', width: 768, height: 1024);

    expect(
      page.coordinateSpaceVersion,
      NotePage.canonicalCoordinateSpaceVersion,
    );
    expect(page.coordinateSpaceStatus, NotePageCoordinateSpaceStatus.canonical);
    expect(page.usesCanonicalCoordinateSpace, isTrue);
    expect(
      page.toJson()['coordinateSpaceVersion'],
      NotePage.canonicalCoordinateSpaceVersion,
    );
  });

  test('missing coordinate version reads as unresolved legacy v0', () {
    final json = const NotePage(id: 'page-1', width: 768, height: 1024).toJson()
      ..remove('coordinateSpaceVersion');

    final page = NotePage.fromJson(json);

    expect(page.coordinateSpaceVersion, NotePage.legacyCoordinateSpaceVersion);
    expect(page.coordinateSpaceStatus, NotePageCoordinateSpaceStatus.legacy);
    expect(page.canSafelyUpgradeCoordinateSpace, isTrue);

    final upgradedPage = page.upgradeEmptyLegacyCoordinateSpace();
    expect(
      upgradedPage.coordinateSpaceStatus,
      NotePageCoordinateSpaceStatus.canonical,
    );
    expect(page.coordinateSpaceStatus, NotePageCoordinateSpaceStatus.legacy);
  });

  test('every coordinate-bearing content type protects a legacy page', () {
    final pages = <NotePage>[
      NotePage(
        id: 'stroke-page',
        width: 768,
        height: 1024,
        coordinateSpaceVersion: NotePage.legacyCoordinateSpaceVersion,
        strokes: [_stroke()],
      ),
      const NotePage(
        id: 'text-page',
        width: 768,
        height: 1024,
        coordinateSpaceVersion: NotePage.legacyCoordinateSpaceVersion,
        textBoxes: [NoteTextBox(id: 'text-1', position: Offset(10, 20))],
      ),
      const NotePage(
        id: 'image-page',
        width: 768,
        height: 1024,
        coordinateSpaceVersion: NotePage.legacyCoordinateSpaceVersion,
        images: [
          NoteImage(
            id: 'image-1',
            position: Offset(10, 20),
            width: 100,
            height: 80,
            assetPath: 'assets/images/image.png',
          ),
        ],
      ),
      const NotePage(
        id: 'shape-page',
        width: 768,
        height: 1024,
        coordinateSpaceVersion: NotePage.legacyCoordinateSpaceVersion,
        shapes: [
          NoteShape(
            id: 'shape-1',
            type: NoteShapeType.rectangle,
            start: Offset(10, 20),
            end: Offset(100, 80),
          ),
        ],
      ),
    ];

    for (final page in pages) {
      expect(page.hasCoordinateBearingContent, isTrue, reason: page.id);
      expect(page.canSafelyUpgradeCoordinateSpace, isFalse, reason: page.id);
      expect(page.isCoordinateSpaceWriteProtected, isTrue, reason: page.id);
    }
  });

  test('future, negative, and non-integer versions stay unsupported', () {
    for (final version in <Object?>[2, -1, 1.5, null, '1']) {
      final json = const NotePage(
        id: 'page-1',
        width: 768,
        height: 1024,
      ).toJson()..['coordinateSpaceVersion'] = version;

      final page = NotePage.fromJson(json);

      expect(
        page.coordinateSpaceStatus,
        NotePageCoordinateSpaceStatus.unsupported,
        reason: '$version',
      );
      expect(page.persistedCoordinateSpaceVersion, version, reason: '$version');
      expect(
        page.toJson()['coordinateSpaceVersion'],
        version,
        reason: '$version',
      );
      expect(page.isCoordinateSpaceWriteProtected, isTrue, reason: '$version');
    }
  });
}

Stroke _stroke() {
  return Stroke(
    id: 'stroke-1',
    tool: ToolType.pen,
    color: const Color(0xFF1E2526),
    width: 4,
    points: [
      StrokePoint(
        offset: const Offset(10, 20),
        pressure: 1,
        time: DateTime.utc(2026, 7, 27),
      ),
    ],
  );
}
