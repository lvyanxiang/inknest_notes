import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_geometry.dart';
import 'package:inknest_notes/models/stroke.dart';

class LassoSelectionLayer extends StatefulWidget {
  const LassoSelectionLayer({
    super.key,
    required this.selectedStrokes,
    required this.onSelectionComplete,
    required this.onStrokesPreviewChanged,
    required this.onStrokesChanged,
    required this.onClearSelection,
  });

  final List<Stroke> selectedStrokes;
  final ValueChanged<List<Offset>> onSelectionComplete;
  final ValueChanged<List<Stroke>> onStrokesPreviewChanged;
  final ValueChanged<List<Stroke>> onStrokesChanged;
  final VoidCallback onClearSelection;

  @override
  State<LassoSelectionLayer> createState() => _LassoSelectionLayerState();
}

class _LassoSelectionLayerState extends State<LassoSelectionLayer> {
  static const _minimumLassoExtent = 12.0;
  static const _selectionHitPadding = 10.0;
  static const _resizeHandleSize = 32.0;
  static const _minimumScale = 0.25;
  static const _maximumScale = 4.0;

  final List<Offset> _lassoPoints = [];
  List<Stroke> _transformSourceStrokes = const [];
  List<Stroke>? _latestTransformedStrokes;
  Rect? _transformSourceBounds;
  Offset _transformDelta = Offset.zero;

  Rect? get _selectionBounds =>
      LassoGeometry.boundsForStrokes(widget.selectedStrokes);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pageSize = constraints.biggest;
          final selectionBounds = _selectionBounds;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('lasso-drawing-region'),
                  behavior: HitTestBehavior.translucent,
                  onPanStart: _startLasso,
                  onPanUpdate: _updateLasso,
                  onPanEnd: (_) => _finishLasso(),
                  onPanCancel: _cancelLasso,
                  child: CustomPaint(
                    painter: _LassoSelectionPainter(
                      lassoPoints: List<Offset>.of(_lassoPoints),
                      selectionBounds: selectionBounds,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (selectionBounds != null) ...[
                _buildMoveRegion(selectionBounds, pageSize),
                _buildResizeHandle(selectionBounds, pageSize),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildMoveRegion(Rect bounds, Size pageSize) {
    final expandedBounds = bounds.inflate(_selectionHitPadding);
    final hitRect = Rect.fromLTRB(
      expandedBounds.left.clamp(0, pageSize.width).toDouble(),
      expandedBounds.top.clamp(0, pageSize.height).toDouble(),
      expandedBounds.right.clamp(0, pageSize.width).toDouble(),
      expandedBounds.bottom.clamp(0, pageSize.height).toDouble(),
    );
    return Positioned.fromRect(
      rect: hitRect,
      child: GestureDetector(
        key: const ValueKey('lasso-move-region'),
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _startTransform(bounds),
        onPanUpdate: (details) => _updateMove(details.delta, pageSize),
        onPanEnd: (_) => _finishTransform(),
        onPanCancel: _cancelTransform,
      ),
    );
  }

  Widget _buildResizeHandle(Rect bounds, Size pageSize) {
    final center = Offset(
      bounds.right.clamp(0, pageSize.width).toDouble(),
      bounds.bottom.clamp(0, pageSize.height).toDouble(),
    );
    return Positioned(
      left: center.dx - _resizeHandleSize / 2,
      top: center.dy - _resizeHandleSize / 2,
      width: _resizeHandleSize,
      height: _resizeHandleSize,
      child: GestureDetector(
        key: const ValueKey('lasso-resize-handle'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _startTransform(bounds),
        onPanUpdate: (details) => _updateScale(details.delta, pageSize),
        onPanEnd: (_) => _finishTransform(),
        onPanCancel: _cancelTransform,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 5),
              ],
            ),
            child: const SizedBox.square(dimension: 18),
          ),
        ),
      ),
    );
  }

  void _startLasso(DragStartDetails details) {
    widget.onClearSelection();
    setState(() {
      _lassoPoints
        ..clear()
        ..add(details.localPosition);
    });
  }

  void _updateLasso(DragUpdateDetails details) {
    final point = details.localPosition;
    if (_lassoPoints.isNotEmpty && (_lassoPoints.last - point).distance < 2) {
      return;
    }
    setState(() {
      _lassoPoints.add(point);
    });
  }

  void _finishLasso() {
    final polygon = List<Offset>.of(_lassoPoints);
    _cancelLasso();
    if (polygon.length < 3) {
      return;
    }

    final bounds = _boundsForOffsets(polygon);
    if (bounds.width < _minimumLassoExtent &&
        bounds.height < _minimumLassoExtent) {
      return;
    }
    widget.onSelectionComplete(polygon);
  }

  void _cancelLasso() {
    if (_lassoPoints.isEmpty) {
      return;
    }
    setState(_lassoPoints.clear);
  }

  void _startTransform(Rect bounds) {
    _transformSourceBounds = bounds;
    _transformSourceStrokes = List<Stroke>.of(widget.selectedStrokes);
    _latestTransformedStrokes = null;
    _transformDelta = Offset.zero;
  }

  void _updateMove(Offset delta, Size pageSize) {
    final bounds = _transformSourceBounds;
    if (bounds == null || _transformSourceStrokes.isEmpty) {
      return;
    }

    _transformDelta += delta;
    final clampedDelta = Offset(
      _transformDelta.dx
          .clamp(-bounds.left, pageSize.width - bounds.right)
          .toDouble(),
      _transformDelta.dy
          .clamp(-bounds.top, pageSize.height - bounds.bottom)
          .toDouble(),
    );
    _previewTransformedStrokes(
      LassoGeometry.translateStrokes(_transformSourceStrokes, clampedDelta),
    );
  }

  void _updateScale(Offset delta, Size pageSize) {
    final bounds = _transformSourceBounds;
    if (bounds == null || _transformSourceStrokes.isEmpty) {
      return;
    }

    _transformDelta += delta;
    final diagonalSquared =
        bounds.width * bounds.width + bounds.height * bounds.height;
    if (diagonalSquared == 0) {
      return;
    }
    final projectedScaleDelta =
        (_transformDelta.dx * bounds.width +
            _transformDelta.dy * bounds.height) /
        diagonalSquared;
    final availableScaleX = bounds.width == 0
        ? _maximumScale
        : (pageSize.width - bounds.left) / bounds.width;
    final availableScaleY = bounds.height == 0
        ? _maximumScale
        : (pageSize.height - bounds.top) / bounds.height;
    final maximumScale = math.max(
      _minimumScale,
      math.min(_maximumScale, math.min(availableScaleX, availableScaleY)),
    );
    final scale = (1 + projectedScaleDelta)
        .clamp(_minimumScale, maximumScale)
        .toDouble();
    _previewTransformedStrokes(
      LassoGeometry.scaleStrokes(
        _transformSourceStrokes,
        anchor: bounds.topLeft,
        scale: scale,
      ),
    );
  }

  void _previewTransformedStrokes(List<Stroke> strokes) {
    _latestTransformedStrokes = strokes;
    widget.onStrokesPreviewChanged(strokes);
  }

  void _finishTransform() {
    final transformedStrokes = _latestTransformedStrokes;
    if (transformedStrokes != null) {
      widget.onStrokesChanged(transformedStrokes);
    }
    _resetTransform();
  }

  void _cancelTransform() {
    if (_latestTransformedStrokes != null) {
      widget.onStrokesPreviewChanged(_transformSourceStrokes);
    }
    _resetTransform();
  }

  void _resetTransform() {
    _transformSourceBounds = null;
    _transformSourceStrokes = const [];
    _latestTransformedStrokes = null;
    _transformDelta = Offset.zero;
  }

  Rect _boundsForOffsets(List<Offset> offsets) {
    var left = offsets.first.dx;
    var top = offsets.first.dy;
    var right = left;
    var bottom = top;
    for (final offset in offsets.skip(1)) {
      left = math.min(left, offset.dx);
      top = math.min(top, offset.dy);
      right = math.max(right, offset.dx);
      bottom = math.max(bottom, offset.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

class _LassoSelectionPainter extends CustomPainter {
  const _LassoSelectionPainter({
    required this.lassoPoints,
    required this.selectionBounds,
  });

  final List<Offset> lassoPoints;
  final Rect? selectionBounds;

  @override
  void paint(Canvas canvas, Size size) {
    final color = const Color(0xFF2F6F73);
    final selectionBounds = this.selectionBounds;
    if (selectionBounds != null) {
      final selectionFill = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      final selectionBorder = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final selection = RRect.fromRectAndRadius(
        selectionBounds,
        const Radius.circular(8),
      );
      canvas
        ..drawRRect(selection, selectionFill)
        ..drawRRect(selection, selectionBorder);
    }

    if (lassoPoints.length < 2) {
      return;
    }
    final path = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
    for (final point in lassoPoints.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (lassoPoints.length >= 3) {
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LassoSelectionPainter oldDelegate) {
    return oldDelegate.lassoPoints != lassoPoints ||
        oldDelegate.selectionBounds != selectionBounds;
  }
}

class LassoSelectionToolbar extends StatelessWidget {
  const LassoSelectionToolbar({
    super.key,
    required this.selectedStrokeCount,
    required this.onColorChanged,
    required this.onDelete,
    required this.onClearSelection,
  });

  final int selectedStrokeCount;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onDelete;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      key: const ValueKey('lasso-selection-toolbar'),
      color: colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_with, size: 18, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              '$selectedStrokeCount',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(width: 6),
            for (final colorChoice in _colorChoices)
              _LassoColorButton(
                color: colorChoice.color,
                label: colorChoice.label,
                onPressed: () => onColorChanged(colorChoice.color),
              ),
            IconButton(
              key: const ValueKey('lasso-delete-selection'),
              onPressed: onDelete,
              tooltip: 'Delete selected strokes',
              icon: const Icon(Icons.delete_outline),
              iconSize: 20,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              key: const ValueKey('lasso-clear-selection'),
              onPressed: onClearSelection,
              tooltip: 'Clear lasso selection',
              icon: const Icon(Icons.close),
              iconSize: 20,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _LassoColorButton extends StatelessWidget {
  const _LassoColorButton({
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Recolor selected strokes $label',
      child: InkResponse(
        key: ValueKey('lasso-color-${color.toARGB32()}'),
        onTap: onPressed,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 3),
              ],
            ),
            child: const SizedBox.square(dimension: 18),
          ),
        ),
      ),
    );
  }
}

const _colorChoices = [
  (color: Color(0xFF1E2526), label: 'black'),
  (color: Color(0xFF2F6F73), label: 'teal'),
  (color: Color(0xFFC24B3A), label: 'red'),
  (color: Color(0xFFB98A16), label: 'gold'),
];
