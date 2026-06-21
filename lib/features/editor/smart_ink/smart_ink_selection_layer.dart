import 'package:flutter/material.dart';

class SmartInkSelectionLayer extends StatefulWidget {
  const SmartInkSelectionLayer({super.key, required this.onSelectionComplete});

  final ValueChanged<Rect> onSelectionComplete;

  @override
  State<SmartInkSelectionLayer> createState() => _SmartInkSelectionLayerState();
}

class _SmartInkSelectionLayerState extends State<SmartInkSelectionLayer> {
  Offset? _start;
  Offset? _current;

  Rect? get _selectionRect {
    final start = _start;
    final current = _current;
    if (start == null || current == null) {
      return null;
    }

    return Rect.fromPoints(start, current);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) {
          setState(() {
            _start = details.localPosition;
            _current = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _current = details.localPosition;
          });
        },
        onPanEnd: (_) => _finishSelection(),
        onPanCancel: _clearSelection,
        child: CustomPaint(
          painter: _SmartInkSelectionPainter(rect: _selectionRect),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  void _finishSelection() {
    final rect = _selectionRect;
    _clearSelection();

    if (rect == null || rect.width < 12 || rect.height < 12) {
      return;
    }

    widget.onSelectionComplete(rect);
  }

  void _clearSelection() {
    if (_start == null && _current == null) {
      return;
    }

    setState(() {
      _start = null;
      _current = null;
    });
  }
}

class _SmartInkSelectionPainter extends CustomPainter {
  const _SmartInkSelectionPainter({required this.rect});

  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final selectionRect = rect;
    if (selectionRect == null) {
      return;
    }

    final fillPaint = Paint()
      ..color = const Color(0x333F7E8C)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF2F6F73)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(selectionRect, const Radius.circular(6)),
        fillPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(selectionRect, const Radius.circular(6)),
        borderPaint,
      );
  }

  @override
  bool shouldRepaint(covariant _SmartInkSelectionPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}
