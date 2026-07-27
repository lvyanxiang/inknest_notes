import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The way a notebook page is fitted into its usable editor viewport.
enum PageViewportMode {
  /// Derives scale from the rotated page width and the current viewport width.
  fitWidth,

  /// Derives scale from both axes so the complete rotated page is visible.
  fitPage,

  /// Uses an absolute, session-only scale selected by the user.
  custom,
}

/// The small amount of viewport state that should be remembered per page.
///
/// [focusDocumentPoint] is the document-space point under the center of the
/// usable viewport. Fit modes derive their scale when restored. Custom mode
/// additionally restores [customScale] as an absolute viewport-pixels per
/// document-unit scale.
@immutable
class PageViewportSessionState {
  const PageViewportSessionState({
    required this.mode,
    required this.focusDocumentPoint,
    this.customScale,
  }) : assert(
         mode == PageViewportMode.custom
             ? customScale != null
             : customScale == null,
       );

  final PageViewportMode mode;
  final Offset focusDocumentPoint;
  final double? customScale;
}

/// Canonical fixed-document page geometry for the notebook editor.
///
/// The three coordinate spaces are:
///
/// * document (D): the unrotated persisted [documentSize];
/// * rotated page (R): the normalized clockwise page bounding box; and
/// * viewport (V): logical pixels in the editor, including [usableRect]'s
///   offset.
///
/// [pageOriginInViewport] is the top-left of R in V. Content is therefore
/// transformed with:
///
/// `V = pageOriginInViewport + effectiveScale * rotateAndNormalize(D)`.
///
/// Instances are immutable. Gesture and reflow methods return a new transform
/// so an editor can keep one instance as the source of truth for rendering and
/// hit testing.
@immutable
class PageViewportTransform {
  const PageViewportTransform._({
    required this.documentSize,
    required this.rotationQuarterTurns,
    required this.usableRect,
    required this.mode,
    required this.effectiveScale,
    required this.pageOriginInViewport,
    required this.pagePadding,
    required this.recoverablePageExtent,
  });

  /// Creates a page's first-visit view.
  ///
  /// Fit Width is the writing-first default. When its page is taller than the
  /// usable viewport, the page starts [pagePadding] below the viewport top. A
  /// page that is smaller on an axis is centered on that axis.
  factory PageViewportTransform.firstVisit({
    required Size documentSize,
    required int rotationQuarterTurns,
    required Rect usableRect,
    PageViewportMode mode = PageViewportMode.fitWidth,
    double pagePadding = 24,
    double recoverablePageExtent = 72,
  }) {
    _validateInputs(
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
      usableRect: usableRect,
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
    if (mode == PageViewportMode.custom) {
      throw ArgumentError.value(
        mode,
        'mode',
        'A first-visit view must use Fit Width or Fit Page.',
      );
    }

    final metrics = _PageViewportMetrics(
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
      usableRect: usableRect,
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
    final scale = metrics.scaleFor(mode);
    final scaledPageSize = metrics.rotatedPageSize * scale;
    final centeredOrigin = Offset(
      usableRect.left + (usableRect.width - scaledPageSize.width) / 2,
      usableRect.top + (usableRect.height - scaledPageSize.height) / 2,
    );
    final requestedOrigin = switch (mode) {
      PageViewportMode.fitWidth
          when scaledPageSize.height > usableRect.height =>
        Offset(centeredOrigin.dx, usableRect.top + pagePadding),
      _ => centeredOrigin,
    };

    return PageViewportTransform._fromMetrics(
      metrics: metrics,
      mode: mode,
      scale: scale,
      requestedOrigin: requestedOrigin,
    );
  }

  /// Restores a remembered page view into the current viewport geometry.
  ///
  /// The remembered document focus is placed under [usableRect.center] before
  /// pan bounds are applied. This is also the primitive used for window and
  /// page-orientation changes.
  factory PageViewportTransform.restore({
    required Size documentSize,
    required int rotationQuarterTurns,
    required Rect usableRect,
    required PageViewportSessionState state,
    double pagePadding = 24,
    double recoverablePageExtent = 72,
  }) {
    _validateInputs(
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
      usableRect: usableRect,
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
    if (state.mode == PageViewportMode.custom) {
      _validateCustomScale(state.customScale);
    }

    final metrics = _PageViewportMetrics(
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
      usableRect: usableRect,
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
    final scale = metrics.scaleFor(state.mode, customScale: state.customScale);
    final rotatedFocus = rotateDocumentPoint(
      state.focusDocumentPoint,
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
    );
    final requestedOrigin = usableRect.center - rotatedFocus * scale;

    return PageViewportTransform._fromMetrics(
      metrics: metrics,
      mode: state.mode,
      scale: scale,
      requestedOrigin: requestedOrigin,
    );
  }

  factory PageViewportTransform._fromMetrics({
    required _PageViewportMetrics metrics,
    required PageViewportMode mode,
    required double scale,
    required Offset requestedOrigin,
  }) {
    return PageViewportTransform._(
      documentSize: metrics.documentSize,
      rotationQuarterTurns: metrics.rotationQuarterTurns,
      usableRect: metrics.usableRect,
      mode: mode,
      effectiveScale: scale,
      pageOriginInViewport: metrics.clampPageOrigin(
        requestedOrigin,
        scale: scale,
      ),
      pagePadding: metrics.pagePadding,
      recoverablePageExtent: metrics.recoverablePageExtent,
    );
  }

  final Size documentSize;
  final int rotationQuarterTurns;
  final Rect usableRect;
  final PageViewportMode mode;

  /// Logical viewport pixels per document-space unit.
  final double effectiveScale;

  /// Top-left of the normalized rotated page (R) in viewport space (V).
  final Offset pageOriginInViewport;

  final double pagePadding;
  final double recoverablePageExtent;

  Size get rotatedPageSize =>
      rotatedSizeFor(documentSize, rotationQuarterTurns: rotationQuarterTurns);

  double get minimumCustomScale => _metrics.minimumCustomScale;

  double get maximumCustomScale => _metrics.maximumCustomScale;

  /// The rotated-page origin relative to [usableRect]'s top-left.
  Offset get pageOriginInUsable => pageOriginInViewport - usableRect.topLeft;

  Rect get pageRectInViewport =>
      pageOriginInViewport & (rotatedPageSize * effectiveScale);

  /// A session-safe representation of this page view.
  PageViewportSessionState get sessionState => PageViewportSessionState(
    mode: mode,
    focusDocumentPoint: viewportToDocument(usableRect.center),
    customScale: mode == PageViewportMode.custom ? effectiveScale : null,
  );

  _PageViewportMetrics get _metrics => _PageViewportMetrics(
    documentSize: documentSize,
    rotationQuarterTurns: rotationQuarterTurns,
    usableRect: usableRect,
    pagePadding: pagePadding,
    recoverablePageExtent: recoverablePageExtent,
  );

  Offset documentToRotated(Offset documentPoint) => rotateDocumentPoint(
    documentPoint,
    documentSize: documentSize,
    rotationQuarterTurns: rotationQuarterTurns,
  );

  Offset rotatedToDocument(Offset rotatedPoint) => unrotatePagePoint(
    rotatedPoint,
    documentSize: documentSize,
    rotationQuarterTurns: rotationQuarterTurns,
  );

  Offset documentToViewport(Offset documentPoint) {
    return pageOriginInViewport +
        documentToRotated(documentPoint) * effectiveScale;
  }

  Offset viewportToDocument(Offset viewportPoint) {
    final rotatedPoint =
        (viewportPoint - pageOriginInViewport) / effectiveScale;
    return rotatedToDocument(rotatedPoint);
  }

  Offset documentVectorToViewport(Offset documentVector) {
    return rotateDocumentVector(
          documentVector,
          rotationQuarterTurns: rotationQuarterTurns,
        ) *
        effectiveScale;
  }

  Offset viewportVectorToDocument(Offset viewportVector) {
    return unrotatePageVector(
      viewportVector / effectiveScale,
      rotationQuarterTurns: rotationQuarterTurns,
    );
  }

  /// Locks a provisional fit view into Custom without moving the page.
  PageViewportTransform enterCustom() {
    if (mode == PageViewportMode.custom) {
      return this;
    }
    return PageViewportTransform._(
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
      usableRect: usableRect,
      mode: PageViewportMode.custom,
      effectiveScale: effectiveScale,
      pageOriginInViewport: pageOriginInViewport,
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
  }

  /// Applies pinch zoom and focal-point movement as one anchor-preserving step.
  ///
  /// The document point under [previousFocalPoint] is placed under
  /// [focalPoint] at the new scale. Pan clamping can move that anchor only when
  /// required to keep the page recoverable.
  PageViewportTransform applyViewportGesture({
    required Offset previousFocalPoint,
    required Offset focalPoint,
    double scaleFactor = 1,
  }) {
    if (!scaleFactor.isFinite || scaleFactor <= 0) {
      throw ArgumentError.value(
        scaleFactor,
        'scaleFactor',
        'Must be finite and greater than zero.',
      );
    }

    final documentAnchor = viewportToDocument(previousFocalPoint);
    final nextScale = (effectiveScale * scaleFactor).clamp(
      minimumCustomScale,
      maximumCustomScale,
    );
    final rotatedAnchor = documentToRotated(documentAnchor);
    final requestedOrigin = focalPoint - rotatedAnchor * nextScale;

    return PageViewportTransform._fromMetrics(
      metrics: _metrics,
      mode: PageViewportMode.custom,
      scale: nextScale,
      requestedOrigin: requestedOrigin,
    );
  }

  /// Zooms around a viewport point while preserving its document anchor.
  PageViewportTransform zoomBy({
    required double scaleFactor,
    Offset? focalPoint,
  }) {
    final anchor = focalPoint ?? usableRect.center;
    return applyViewportGesture(
      previousFocalPoint: anchor,
      focalPoint: anchor,
      scaleFactor: scaleFactor,
    );
  }

  /// Pans in viewport pixels and enters Custom mode.
  PageViewportTransform panBy(Offset viewportDelta) {
    return applyViewportGesture(
      previousFocalPoint: usableRect.center,
      focalPoint: usableRect.center + viewportDelta,
    );
  }

  /// Switches to an explicit fit mode while retaining the current focus.
  PageViewportTransform fit(PageViewportMode fitMode) {
    if (fitMode == PageViewportMode.custom) {
      throw ArgumentError.value(
        fitMode,
        'fitMode',
        'Use enterCustom or a viewport gesture to enter Custom mode.',
      );
    }
    return PageViewportTransform.restore(
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
      usableRect: usableRect,
      state: PageViewportSessionState(
        mode: fitMode,
        focusDocumentPoint: viewportToDocument(usableRect.center),
      ),
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
  }

  /// Reprojects this view into a new usable editor rectangle.
  ///
  /// Custom preserves its absolute scale unless the new fit-derived bounds
  /// require clamping. Fit modes preserve their mode and derive a new scale.
  PageViewportTransform reflow(Rect nextUsableRect) {
    return PageViewportTransform.restore(
      documentSize: documentSize,
      rotationQuarterTurns: rotationQuarterTurns,
      usableRect: nextUsableRect,
      state: sessionState,
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
  }

  /// Reprojects this view after an explicit page rotation.
  ///
  /// Document coordinates and the focused document point are unchanged.
  PageViewportTransform rotateTo(int nextRotationQuarterTurns) {
    return PageViewportTransform.restore(
      documentSize: documentSize,
      rotationQuarterTurns: nextRotationQuarterTurns,
      usableRect: usableRect,
      state: sessionState,
      pagePadding: pagePadding,
      recoverablePageExtent: recoverablePageExtent,
    );
  }
}

/// Returns the normalized rotated-page size for a clockwise quarter rotation.
Size rotatedSizeFor(Size documentSize, {required int rotationQuarterTurns}) {
  _validateDocumentSize(documentSize);
  _validateQuarterTurns(rotationQuarterTurns);
  return rotationQuarterTurns.isOdd
      ? Size(documentSize.height, documentSize.width)
      : documentSize;
}

/// Maps a point from unrotated document space (D) into normalized rotated page
/// space (R).
Offset rotateDocumentPoint(
  Offset point, {
  required Size documentSize,
  required int rotationQuarterTurns,
}) {
  _validateDocumentSize(documentSize);
  _validateQuarterTurns(rotationQuarterTurns);

  return switch (rotationQuarterTurns) {
    0 => point,
    1 => Offset(documentSize.height - point.dy, point.dx),
    2 => Offset(documentSize.width - point.dx, documentSize.height - point.dy),
    3 => Offset(point.dy, documentSize.width - point.dx),
    _ => throw StateError('Unreachable validated rotation.'),
  };
}

/// Maps a point from normalized rotated page space (R) back to document space
/// (D).
Offset unrotatePagePoint(
  Offset point, {
  required Size documentSize,
  required int rotationQuarterTurns,
}) {
  _validateDocumentSize(documentSize);
  _validateQuarterTurns(rotationQuarterTurns);

  return switch (rotationQuarterTurns) {
    0 => point,
    1 => Offset(point.dy, documentSize.height - point.dx),
    2 => Offset(documentSize.width - point.dx, documentSize.height - point.dy),
    3 => Offset(documentSize.width - point.dy, point.dx),
    _ => throw StateError('Unreachable validated rotation.'),
  };
}

/// Applies only the linear clockwise rotation component to a document vector.
///
/// Unlike [rotateDocumentPoint], vectors receive no normalization translation.
Offset rotateDocumentVector(
  Offset vector, {
  required int rotationQuarterTurns,
}) {
  _validateQuarterTurns(rotationQuarterTurns);
  return switch (rotationQuarterTurns) {
    0 => vector,
    1 => Offset(-vector.dy, vector.dx),
    2 => -vector,
    3 => Offset(vector.dy, -vector.dx),
    _ => throw StateError('Unreachable validated rotation.'),
  };
}

/// Applies the inverse linear rotation component to a rotated-page vector.
Offset unrotatePageVector(Offset vector, {required int rotationQuarterTurns}) {
  _validateQuarterTurns(rotationQuarterTurns);
  return switch (rotationQuarterTurns) {
    0 => vector,
    1 => Offset(vector.dy, -vector.dx),
    2 => -vector,
    3 => Offset(-vector.dy, vector.dx),
    _ => throw StateError('Unreachable validated rotation.'),
  };
}

class _PageViewportMetrics {
  const _PageViewportMetrics({
    required this.documentSize,
    required this.rotationQuarterTurns,
    required this.usableRect,
    required this.pagePadding,
    required this.recoverablePageExtent,
  });

  final Size documentSize;
  final int rotationQuarterTurns;
  final Rect usableRect;
  final double pagePadding;
  final double recoverablePageExtent;

  Size get rotatedPageSize =>
      rotatedSizeFor(documentSize, rotationQuarterTurns: rotationQuarterTurns);

  double get fitWidthScale =>
      _fitExtent(usableRect.width, pagePadding) / rotatedPageSize.width;

  double get fitPageScale => math.min(
    fitWidthScale,
    _fitExtent(usableRect.height, pagePadding) / rotatedPageSize.height,
  );

  double get minimumCustomScale => fitPageScale * 0.5;

  double get maximumCustomScale => fitWidthScale * 8;

  double scaleFor(PageViewportMode mode, {double? customScale}) {
    return switch (mode) {
      PageViewportMode.fitWidth => fitWidthScale,
      PageViewportMode.fitPage => fitPageScale,
      PageViewportMode.custom => customScale!.clamp(
        minimumCustomScale,
        maximumCustomScale,
      ),
    };
  }

  Offset clampPageOrigin(Offset requestedOrigin, {required double scale}) {
    final scaledSize = rotatedPageSize * scale;
    return Offset(
      _clampAxisOrigin(
        requested: requestedOrigin.dx,
        usableStart: usableRect.left,
        usableExtent: usableRect.width,
        pageExtent: scaledSize.width,
        recoverableExtent: recoverablePageExtent,
      ),
      _clampAxisOrigin(
        requested: requestedOrigin.dy,
        usableStart: usableRect.top,
        usableExtent: usableRect.height,
        pageExtent: scaledSize.height,
        recoverableExtent: recoverablePageExtent,
      ),
    );
  }
}

double _fitExtent(double usableExtent, double padding) {
  return math.max(1, usableExtent - padding * 2);
}

double _clampAxisOrigin({
  required double requested,
  required double usableStart,
  required double usableExtent,
  required double pageExtent,
  required double recoverableExtent,
}) {
  if (pageExtent <= usableExtent) {
    return usableStart + (usableExtent - pageExtent) / 2;
  }

  final usableEnd = usableStart + usableExtent;
  final visibleExtent = math.min(
    recoverableExtent,
    math.min(usableExtent, pageExtent) / 2,
  );
  final minimum = usableStart + visibleExtent - pageExtent;
  final maximum = usableEnd - visibleExtent;
  if (minimum > maximum) {
    return usableStart + (usableExtent - pageExtent) / 2;
  }
  return requested.clamp(minimum, maximum).toDouble();
}

void _validateInputs({
  required Size documentSize,
  required int rotationQuarterTurns,
  required Rect usableRect,
  required double pagePadding,
  required double recoverablePageExtent,
}) {
  _validateDocumentSize(documentSize);
  _validateQuarterTurns(rotationQuarterTurns);
  if (!usableRect.left.isFinite ||
      !usableRect.top.isFinite ||
      !usableRect.width.isFinite ||
      !usableRect.height.isFinite ||
      usableRect.width <= 0 ||
      usableRect.height <= 0) {
    throw ArgumentError.value(
      usableRect,
      'usableRect',
      'Must have finite coordinates and positive dimensions.',
    );
  }
  if (!pagePadding.isFinite || pagePadding < 0) {
    throw ArgumentError.value(
      pagePadding,
      'pagePadding',
      'Must be finite and non-negative.',
    );
  }
  if (!recoverablePageExtent.isFinite || recoverablePageExtent < 0) {
    throw ArgumentError.value(
      recoverablePageExtent,
      'recoverablePageExtent',
      'Must be finite and non-negative.',
    );
  }
}

void _validateDocumentSize(Size documentSize) {
  if (!documentSize.width.isFinite ||
      !documentSize.height.isFinite ||
      documentSize.width <= 0 ||
      documentSize.height <= 0) {
    throw ArgumentError.value(
      documentSize,
      'documentSize',
      'Must have finite, positive dimensions.',
    );
  }
}

void _validateQuarterTurns(int rotationQuarterTurns) {
  if (rotationQuarterTurns < 0 || rotationQuarterTurns > 3) {
    throw RangeError.range(rotationQuarterTurns, 0, 3, 'rotationQuarterTurns');
  }
}

void _validateCustomScale(double? customScale) {
  if (customScale == null || !customScale.isFinite || customScale <= 0) {
    throw ArgumentError.value(
      customScale,
      'customScale',
      'Custom mode requires a finite scale greater than zero.',
    );
  }
}
