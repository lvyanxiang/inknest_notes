import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/canvas/page_viewport_model.dart';

void main() {
  group('normalized page rotation', () {
    const documentSize = Size(300, 500);

    test('maps all document corners exactly for q0-q3', () {
      const corners = [
        Offset.zero,
        Offset(300, 0),
        Offset(0, 500),
        Offset(300, 500),
      ];
      const expectedByRotation = {
        0: [Offset.zero, Offset(300, 0), Offset(0, 500), Offset(300, 500)],
        1: [Offset(500, 0), Offset(500, 300), Offset.zero, Offset(0, 300)],
        2: [Offset(300, 500), Offset(0, 500), Offset(300, 0), Offset.zero],
        3: [Offset(0, 300), Offset.zero, Offset(500, 300), Offset(500, 0)],
      };

      for (var quarterTurns = 0; quarterTurns < 4; quarterTurns++) {
        expect(
          rotatedSizeFor(documentSize, rotationQuarterTurns: quarterTurns),
          quarterTurns.isOdd ? const Size(500, 300) : documentSize,
        );
        for (var index = 0; index < corners.length; index++) {
          final rotated = rotateDocumentPoint(
            corners[index],
            documentSize: documentSize,
            rotationQuarterTurns: quarterTurns,
          );
          expect(rotated, expectedByRotation[quarterTurns]![index]);
          expect(
            unrotatePagePoint(
              rotated,
              documentSize: documentSize,
              rotationQuarterTurns: quarterTurns,
            ),
            corners[index],
          );
        }
      }
    });

    test('round trips document and vector transforms for q0-q3', () {
      const documentPoint = Offset(83.25, 327.5);
      const documentVector = Offset(17.5, -9.25);

      for (var quarterTurns = 0; quarterTurns < 4; quarterTurns++) {
        final rotatedPoint = rotateDocumentPoint(
          documentPoint,
          documentSize: documentSize,
          rotationQuarterTurns: quarterTurns,
        );
        final rotatedVector = rotateDocumentVector(
          documentVector,
          rotationQuarterTurns: quarterTurns,
        );

        expect(
          unrotatePagePoint(
            rotatedPoint,
            documentSize: documentSize,
            rotationQuarterTurns: quarterTurns,
          ),
          documentPoint,
        );
        expect(
          unrotatePageVector(rotatedVector, rotationQuarterTurns: quarterTurns),
          documentVector,
        );
      }
    });
  });

  group('fit modes', () {
    const documentSize = Size(500, 1000);
    const usableRect = Rect.fromLTWH(10, 20, 1000, 700);

    test('first Fit Width uses exact padding and top alignment', () {
      final transform = PageViewportTransform.firstVisit(
        documentSize: documentSize,
        rotationQuarterTurns: 0,
        usableRect: usableRect,
      );

      expect(transform.mode, PageViewportMode.fitWidth);
      expect(transform.effectiveScale, closeTo(952 / 500, 1e-12));
      expect(transform.pageOriginInViewport.dx, closeTo(34, 1e-12));
      expect(transform.pageOriginInViewport.dy, closeTo(44, 1e-12));
      expect(transform.pageOriginInUsable, const Offset(24, 24));
    });

    test('Fit Page centers the padded complete page', () {
      final transform = PageViewportTransform.firstVisit(
        documentSize: documentSize,
        rotationQuarterTurns: 0,
        usableRect: usableRect,
        mode: PageViewportMode.fitPage,
      );

      expect(transform.effectiveScale, closeTo(652 / 1000, 1e-12));
      expect(transform.pageRectInViewport.center, usableRect.center);
      expect(transform.pageRectInViewport.top, closeTo(44, 1e-12));
      expect(transform.pageRectInViewport.bottom, closeTo(696, 1e-12));
    });

    test('rotation swaps fitted dimensions without changing document size', () {
      final transform = PageViewportTransform.firstVisit(
        documentSize: documentSize,
        rotationQuarterTurns: 1,
        usableRect: usableRect,
      );

      expect(transform.documentSize, documentSize);
      expect(transform.rotatedPageSize, const Size(1000, 500));
      expect(transform.effectiveScale, closeTo(952 / 1000, 1e-12));
      expect(transform.pageRectInViewport.center, usableRect.center);
    });
  });

  group('document and viewport round trips', () {
    test('use one exact transform for every quarter rotation', () {
      const documentSize = Size(768, 1024);
      const usableRect = Rect.fromLTWH(37, 61, 834, 940);
      const point = Offset(631.75, 903.125);

      for (var quarterTurns = 0; quarterTurns < 4; quarterTurns++) {
        final transform = PageViewportTransform.restore(
          documentSize: documentSize,
          rotationQuarterTurns: quarterTurns,
          usableRect: usableRect,
          state: const PageViewportSessionState(
            mode: PageViewportMode.custom,
            focusDocumentPoint: Offset(420, 610),
            customScale: 1.25,
          ),
        );

        final viewportPoint = transform.documentToViewport(point);
        expect(
          transform.viewportToDocument(viewportPoint).dx,
          closeTo(point.dx, 1e-9),
        );
        expect(
          transform.viewportToDocument(viewportPoint).dy,
          closeTo(point.dy, 1e-9),
        );

        const vector = Offset(14.25, -31.5);
        final viewportVector = transform.documentVectorToViewport(vector);
        final roundTripVector = transform.viewportVectorToDocument(
          viewportVector,
        );
        expect(roundTripVector.dx, closeTo(vector.dx, 1e-9));
        expect(roundTripVector.dy, closeTo(vector.dy, 1e-9));
      }
    });
  });

  group('custom gestures', () {
    test(
      'pinch and pan preserve the document focal point on a rotated page',
      () {
        final transform = PageViewportTransform.restore(
          documentSize: const Size(1000, 1200),
          rotationQuarterTurns: 1,
          usableRect: const Rect.fromLTWH(0, 0, 1000, 800),
          state: const PageViewportSessionState(
            mode: PageViewportMode.custom,
            focusDocumentPoint: Offset(500, 600),
            customScale: 1,
          ),
        );
        const previousFocalPoint = Offset(460, 360);
        const nextFocalPoint = Offset(485, 378);
        final anchoredDocumentPoint = transform.viewportToDocument(
          previousFocalPoint,
        );

        final updated = transform.applyViewportGesture(
          previousFocalPoint: previousFocalPoint,
          focalPoint: nextFocalPoint,
          scaleFactor: 1.4,
        );

        expect(updated.mode, PageViewportMode.custom);
        final projectedAnchor = updated.documentToViewport(
          anchoredDocumentPoint,
        );
        expect(projectedAnchor.dx, closeTo(nextFocalPoint.dx, 1e-9));
        expect(projectedAnchor.dy, closeTo(nextFocalPoint.dy, 1e-9));
      },
    );

    test('entering Custom does not move or rescale a provisional fit', () {
      final fitted = PageViewportTransform.firstVisit(
        documentSize: const Size(768, 1024),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 834, 1000),
      );

      final custom = fitted.enterCustom();

      expect(custom.mode, PageViewportMode.custom);
      expect(custom.effectiveScale, fitted.effectiveScale);
      expect(custom.pageOriginInViewport, fitted.pageOriginInViewport);
    });

    test('zoom steps are absolute Custom changes around the usable center', () {
      final fitted = PageViewportTransform.firstVisit(
        documentSize: const Size(768, 1024),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 834, 1000),
      );
      final anchorBefore = fitted.viewportToDocument(fitted.usableRect.center);

      final zoomedIn = fitted.zoomBy(scaleFactor: 1.25);
      final zoomedOut = zoomedIn.zoomBy(scaleFactor: 0.8);

      expect(
        zoomedIn.effectiveScale,
        closeTo(fitted.effectiveScale * 1.25, 1e-12),
      );
      expect(zoomedOut.effectiveScale, closeTo(fitted.effectiveScale, 1e-12));
      final anchorAfter = zoomedOut.viewportToDocument(
        zoomedOut.usableRect.center,
      );
      expect(anchorAfter.dx, closeTo(anchorBefore.dx, 1e-9));
      expect(anchorAfter.dy, closeTo(anchorBefore.dy, 1e-9));
    });

    test('Custom scale clamps to fit-derived minimum and maximum', () {
      final tooSmall = PageViewportTransform.restore(
        documentSize: const Size(1000, 1000),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 600, 400),
        state: const PageViewportSessionState(
          mode: PageViewportMode.custom,
          focusDocumentPoint: Offset(500, 500),
          customScale: 0.0001,
        ),
      );
      final tooLarge = PageViewportTransform.restore(
        documentSize: const Size(1000, 1000),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 600, 400),
        state: const PageViewportSessionState(
          mode: PageViewportMode.custom,
          focusDocumentPoint: Offset(500, 500),
          customScale: 100,
        ),
      );

      expect(tooSmall.effectiveScale, tooSmall.minimumCustomScale);
      expect(tooLarge.effectiveScale, tooLarge.maximumCustomScale);
    });
  });

  group('pan clamping', () {
    test('keeps exactly 72 pixels recoverable on each oversized edge', () {
      final centered = PageViewportTransform.restore(
        documentSize: const Size(400, 400),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 300, 300),
        state: const PageViewportSessionState(
          mode: PageViewportMode.custom,
          focusDocumentPoint: Offset(200, 200),
          customScale: 1,
        ),
      );

      final movedBottomRight = centered.panBy(const Offset(10000, 10000));
      expect(movedBottomRight.pageRectInViewport.left, closeTo(228, 1e-9));
      expect(movedBottomRight.pageRectInViewport.top, closeTo(228, 1e-9));
      expect(
        movedBottomRight.pageRectInViewport
            .intersect(movedBottomRight.usableRect)
            .size,
        const Size(72, 72),
      );

      final movedTopLeft = centered.panBy(const Offset(-10000, -10000));
      expect(movedTopLeft.pageRectInViewport.right, closeTo(72, 1e-9));
      expect(movedTopLeft.pageRectInViewport.bottom, closeTo(72, 1e-9));
      expect(
        movedTopLeft.pageRectInViewport.intersect(movedTopLeft.usableRect).size,
        const Size(72, 72),
      );
    });

    test('centers a page that is smaller than the usable axis', () {
      final fitted = PageViewportTransform.firstVisit(
        documentSize: const Size(100, 100),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(20, 40, 500, 400),
        mode: PageViewportMode.fitPage,
      );

      final attemptedPan = fitted.panBy(const Offset(200, -200));

      expect(attemptedPan.pageRectInViewport.center, fitted.usableRect.center);
    });
  });

  group('viewport and page reflow', () {
    test('resize preserves Custom scale and center document focus', () {
      final transform = PageViewportTransform.restore(
        documentSize: const Size(1000, 1000),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 600, 600),
        state: const PageViewportSessionState(
          mode: PageViewportMode.custom,
          focusDocumentPoint: Offset(700, 650),
          customScale: 1,
        ),
      );
      final focusBefore = transform.viewportToDocument(
        transform.usableRect.center,
      );

      final resized = transform.reflow(const Rect.fromLTWH(50, 30, 800, 500));

      expect(resized.effectiveScale, 1);
      final focusAfter = resized.viewportToDocument(resized.usableRect.center);
      expect(focusAfter.dx, closeTo(focusBefore.dx, 1e-9));
      expect(focusAfter.dy, closeTo(focusBefore.dy, 1e-9));
    });

    test('page rotation preserves Custom scale and document focus', () {
      final transform = PageViewportTransform.restore(
        documentSize: const Size(768, 1024),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 900, 700),
        state: const PageViewportSessionState(
          mode: PageViewportMode.custom,
          focusDocumentPoint: Offset(420, 590),
          customScale: 1.1,
        ),
      );
      final focusBefore = transform.viewportToDocument(
        transform.usableRect.center,
      );

      final rotated = transform.rotateTo(1);

      expect(rotated.effectiveScale, transform.effectiveScale);
      expect(rotated.rotatedPageSize, const Size(1024, 768));
      final focusAfter = rotated.viewportToDocument(rotated.usableRect.center);
      expect(focusAfter.dx, closeTo(focusBefore.dx, 1e-9));
      expect(focusAfter.dy, closeTo(focusBefore.dy, 1e-9));
    });

    test('Fit Width re-derives scale while preserving available focus', () {
      final initial = PageViewportTransform.firstVisit(
        documentSize: const Size(500, 1400),
        rotationQuarterTurns: 0,
        usableRect: const Rect.fromLTWH(0, 0, 600, 700),
      );
      final panned = initial
          .panBy(const Offset(0, -250))
          .fit(PageViewportMode.fitWidth);
      final focusBefore = panned.viewportToDocument(panned.usableRect.center);

      final resized = panned.reflow(const Rect.fromLTWH(0, 0, 800, 600));

      expect(resized.mode, PageViewportMode.fitWidth);
      expect(resized.effectiveScale, closeTo(752 / 500, 1e-12));
      final focusAfter = resized.viewportToDocument(resized.usableRect.center);
      expect(focusAfter.dx, closeTo(focusBefore.dx, 1e-9));
      expect(focusAfter.dy, closeTo(focusBefore.dy, 1e-9));
    });
  });
}
