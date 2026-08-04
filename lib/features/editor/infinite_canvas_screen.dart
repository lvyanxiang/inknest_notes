import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_codec;
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/images/image_layer.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_geometry.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_selection_layer.dart';
import 'package:inknest_notes/features/editor/shapes/shape_layer.dart';
import 'package:inknest_notes/features/editor/text/text_box_layer.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/infinite_canvas_document.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class InfiniteCanvasScreen extends StatefulWidget {
  const InfiniteCanvasScreen({
    super.key,
    required this.notebook,
    required this.notebookRepository,
    this.imageFilePicker,
    this.imageSizeReader,
  });

  final Notebook notebook;
  final NotebookRepository notebookRepository;
  final Future<File?> Function()? imageFilePicker;
  final Future<Size> Function(File)? imageSizeReader;

  @override
  State<InfiniteCanvasScreen> createState() => _InfiniteCanvasScreenState();
}

class _InfiniteCanvasScreenState extends State<InfiniteCanvasScreen> {
  final _viewportKey = GlobalKey<_InfiniteCanvasViewportState>();
  final List<_CanvasContentState> _undoStates = [];
  final List<_CanvasContentState> _redoStates = [];
  final Set<String> _selectedStrokeIds = {};
  InfiniteCanvasDocument? _document;
  DrawingTool _tool = const DrawingTool(
    type: ToolType.pen,
    color: Color(0xFF1E2526),
    width: 3,
  );
  bool _fingerPanEnabled = false;
  bool _fingerWritingAssistEnabled = true;
  _CanvasContentState? _eraseStartState;
  _CanvasContentState? _lassoPreviewStartState;
  String? _activeTextBoxId;
  String? _activeImageId;
  bool? _fingerPanBeforeLasso;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final document = await widget.notebookRepository.loadInfiniteCanvas(
      widget.notebook,
    );
    if (!mounted) return;
    setState(() => _document = document);
  }

  Future<void> _save(InfiniteCanvasDocument document) {
    return widget.notebookRepository.saveInfiniteCanvas(
      widget.notebook,
      document,
    );
  }

  _CanvasContentState _contentState(InfiniteCanvasDocument document) {
    return _CanvasContentState.fromDocument(document);
  }

  InfiniteCanvasDocument _withContent(
    InfiniteCanvasDocument document,
    _CanvasContentState content,
  ) {
    return document.copyWith(
      strokes: content.strokes,
      textBoxes: content.textBoxes,
      images: content.images,
      shapes: content.shapes,
    );
  }

  void _commitContent(InfiniteCanvasDocument updated) {
    final document = _document;
    if (document == null) return;
    _undoStates.add(_contentState(document));
    _redoStates.clear();
    setState(() => _document = updated);
    unawaited(_save(updated));
  }

  void _commitStroke(Stroke stroke) {
    final document = _document;
    if (document == null) return;
    final updated = document.copyWith(strokes: [...document.strokes, stroke]);
    _commitContent(updated);
  }

  void _beginErase() {
    final document = _document;
    if (document != null) {
      _eraseStartState ??= _contentState(document);
    }
  }

  void _eraseAt(Offset point) {
    final document = _document;
    if (document == null) return;
    final updatedStrokes = StrokeGeometry.eraseStrokes(
      strokes: document.strokes,
      eraserPoints: [
        StrokePoint(offset: point, pressure: 1, time: DateTime.now()),
      ],
      radius: math.max(8, _tool.width / 2),
    );
    if (identical(updatedStrokes, document.strokes)) return;
    setState(() => _document = document.copyWith(strokes: updatedStrokes));
  }

  void _endErase() {
    final before = _eraseStartState;
    final document = _document;
    _eraseStartState = null;
    if (before == null ||
        document == null ||
        _sameStrokeList(before.strokes, document.strokes)) {
      return;
    }
    _undoStates.add(before);
    _redoStates.clear();
    unawaited(_save(document));
  }

  void _undo() {
    final document = _document;
    if (document == null || _undoStates.isEmpty) return;
    _redoStates.add(_contentState(document));
    final updated = _withContent(document, _undoStates.removeLast());
    setState(() => _document = updated);
    _selectedStrokeIds.clear();
    unawaited(_save(updated));
  }

  void _redo() {
    final document = _document;
    if (document == null || _redoStates.isEmpty) return;
    _undoStates.add(_contentState(document));
    final updated = _withContent(document, _redoStates.removeLast());
    setState(() => _document = updated);
    _selectedStrokeIds.clear();
    unawaited(_save(updated));
  }

  void _setTool(DrawingTool tool) {
    setState(() {
      final wasUsingLasso = _tool.type == ToolType.lasso;
      _tool = tool;
      _activeTextBoxId = null;
      _activeImageId = null;
      if (tool.type == ToolType.lasso) {
        if (!wasUsingLasso) {
          _fingerPanBeforeLasso = _fingerPanEnabled;
        }
        _fingerPanEnabled = false;
      } else {
        if (wasUsingLasso && _fingerPanBeforeLasso != null) {
          _fingerPanEnabled = _fingerPanBeforeLasso!;
        }
        _fingerPanBeforeLasso = null;
        _selectedStrokeIds.clear();
        _lassoPreviewStartState = null;
      }
    });
  }

  void _setFingerPanEnabled(bool enabled) {
    if (enabled && _tool.type == ToolType.lasso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish lasso editing before finger pan')),
      );
      return;
    }
    setState(() => _fingerPanEnabled = enabled);
  }

  void _addTextBoxAt(Offset position) {
    final document = _document;
    if (document == null) return;
    final textBox = NoteTextBox(
      id: 'text-${DateTime.now().microsecondsSinceEpoch}',
      position: position - const Offset(120, 24),
      width: 240,
      color: _tool.color,
    );
    _activeTextBoxId = textBox.id;
    _commitContent(
      document.copyWith(textBoxes: [...document.textBoxes, textBox]),
    );
  }

  void _updateTextBox(NoteTextBox textBox) {
    final document = _document;
    if (document == null) return;
    _activeTextBoxId = textBox.id;
    _commitContent(
      document.copyWith(
        textBoxes: [
          for (final existing in document.textBoxes)
            if (existing.id == textBox.id) textBox else existing,
        ],
      ),
    );
  }

  void _deleteTextBox(String id) {
    final document = _document;
    if (document == null) return;
    final remaining = [
      for (final textBox in document.textBoxes)
        if (textBox.id != id) textBox,
    ];
    if (remaining.length == document.textBoxes.length) return;
    _activeTextBoxId = null;
    _commitContent(document.copyWith(textBoxes: remaining));
  }

  Future<void> _insertImage() async {
    final sourceFile = await _pickImageFile();
    if (!mounted || sourceFile == null) return;
    try {
      final intrinsic = await _readImageSize(sourceFile);
      final fitScale = math.min(420 / intrinsic.width, 320 / intrinsic.height);
      final displayScale = math.min(1.0, fitScale);
      final displaySize = Size(
        math.max(96, intrinsic.width * displayScale),
        math.max(72, intrinsic.height * displayScale),
      );
      final focus =
          _viewportKey.currentState?.focus ??
          _document?.viewportFocus ??
          Offset.zero;
      final noteImage = await widget.notebookRepository.importImage(
        widget.notebook,
        sourceFile,
        position: focus - Offset(displaySize.width / 2, displaySize.height / 2),
        width: displaySize.width,
        height: displaySize.height,
      );
      if (!mounted || _document == null) return;
      _activeImageId = noteImage.id;
      _commitContent(
        _document!.copyWith(images: [..._document!.images, noteImage]),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Insert image failed: $error')));
      }
    }
  }

  Future<Size> _readImageSize(File sourceFile) async {
    final reader = widget.imageSizeReader;
    if (reader != null) return reader(sourceFile);
    final decoded = image_codec.decodeImage(await sourceFile.readAsBytes());
    return Size(
      (decoded?.width ?? 320).toDouble(),
      (decoded?.height ?? 240).toDouble(),
    );
  }

  Future<File?> _pickImageFile() async {
    final picker = widget.imageFilePicker;
    if (picker != null) return picker();
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) return null;
    if (picked.path case final path?) return File(path);
    final bytes = picked.bytes;
    if (bytes == null) return null;
    final suffix = picked.extension?.trim().isNotEmpty == true
        ? picked.extension!.trim()
        : 'png';
    final file = File(
      '${Directory.systemTemp.path}/inknest-canvas-image-'
      '${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _updateImage(NoteImage noteImage) {
    final document = _document;
    if (document == null) return;
    _activeImageId = noteImage.id;
    _commitContent(
      document.copyWith(
        images: [
          for (final existing in document.images)
            if (existing.id == noteImage.id) noteImage else existing,
        ],
      ),
    );
  }

  void _deleteImage(String id) {
    final document = _document;
    if (document == null) return;
    final remaining = [
      for (final image in document.images)
        if (image.id != id) image,
    ];
    if (remaining.length == document.images.length) return;
    _activeImageId = null;
    _commitContent(document.copyWith(images: remaining));
  }

  void _addShape(NoteShape shape) {
    final document = _document;
    if (document == null) return;
    _commitContent(document.copyWith(shapes: [...document.shapes, shape]));
  }

  List<Stroke> _selectedStrokes(InfiniteCanvasDocument document) {
    return [
      for (final stroke in document.strokes)
        if (_selectedStrokeIds.contains(stroke.id)) stroke,
    ];
  }

  void _selectStrokes(List<Offset> polygon) {
    final document = _document;
    if (document == null) return;
    final ids = LassoGeometry.selectStrokeIds(document.strokes, polygon);
    setState(() {
      _selectedStrokeIds
        ..clear()
        ..addAll(ids);
    });
    if (ids.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No strokes selected')));
    }
  }

  void _replaceSelectedStrokes(List<Stroke> strokes, {required bool commit}) {
    final document = _document;
    if (document == null || strokes.isEmpty) return;
    _lassoPreviewStartState ??= _contentState(document);
    final byId = {for (final stroke in strokes) stroke.id: stroke};
    final updated = document.copyWith(
      strokes: [
        for (final stroke in document.strokes) byId[stroke.id] ?? stroke,
      ],
    );
    setState(() => _document = updated);
    if (!commit) return;
    _undoStates.add(_lassoPreviewStartState!);
    _redoStates.clear();
    _lassoPreviewStartState = null;
    unawaited(_save(updated));
  }

  void _recolorSelectedStrokes(Color color) {
    final document = _document;
    if (document == null) return;
    final selected = _selectedStrokes(document);
    if (selected.isEmpty) return;
    _commitContent(
      document.copyWith(
        strokes: [
          for (final stroke in document.strokes)
            if (_selectedStrokeIds.contains(stroke.id))
              stroke.copyWith(color: color)
            else
              stroke,
        ],
      ),
    );
  }

  void _deleteSelectedStrokes() {
    final document = _document;
    if (document == null || _selectedStrokeIds.isEmpty) return;
    _commitContent(
      document.copyWith(
        strokes: [
          for (final stroke in document.strokes)
            if (!_selectedStrokeIds.contains(stroke.id)) stroke,
        ],
      ),
    );
    setState(_selectedStrokeIds.clear);
  }

  void _clearLassoSelection() {
    if (_selectedStrokeIds.isEmpty) return;
    setState(_selectedStrokeIds.clear);
    _lassoPreviewStartState = null;
  }

  void _changeBackground(InfiniteCanvasBackground background) {
    final document = _document;
    if (document == null || document.background == background) return;
    final updated = document.copyWith(background: background);
    setState(() => _document = updated);
    _save(updated);
  }

  void _viewportChanged(Offset focus, double scale) {
    final document = _document;
    if (document == null) return;
    final updated = document.copyWith(
      viewportFocus: focus,
      viewportScale: scale,
    );
    _document = updated;
    _save(updated);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        titleSpacing: 0,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final showIdentity = constraints.maxWidth >= 500;
            return Row(
              children: [
                if (showIdentity) ...[
                  SizedBox(
                    width: constraints.maxWidth >= 760 ? 220 : 180,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.notebook.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Infinite canvas',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Center(
                    child: EditorToolbar(
                      key: const ValueKey('infinite-canvas-top-toolbar'),
                      tool: _tool,
                      fingerPanEnabled: _fingerPanEnabled,
                      fingerWritingAssistEnabled: _fingerWritingAssistEnabled,
                      onToolChanged: _setTool,
                      onFingerPanChanged: _setFingerPanEnabled,
                      onFingerWritingAssistChanged: (enabled) =>
                          setState(() => _fingerWritingAssistEnabled = enabled),
                      onInsertImage: () => unawaited(_insertImage()),
                      showLasso: true,
                      showInsert: true,
                      embedded: true,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            key: const ValueKey('infinite-canvas-undo'),
            tooltip: 'Undo',
            onPressed: _undoStates.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const ValueKey('infinite-canvas-redo'),
            tooltip: 'Redo',
            onPressed: _redoStates.isEmpty ? null : _redo,
            icon: const Icon(Icons.redo),
          ),
          PopupMenuButton<InfiniteCanvasBackground>(
            key: const ValueKey('infinite-canvas-background'),
            tooltip: 'Canvas background',
            initialValue: document?.background,
            onSelected: _changeBackground,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: InfiniteCanvasBackground.blank,
                child: _BackgroundMenuItem(
                  icon: Icons.crop_square,
                  label: 'Blank',
                ),
              ),
              PopupMenuItem(
                value: InfiniteCanvasBackground.dotted,
                child: _BackgroundMenuItem(
                  icon: Icons.more_horiz,
                  label: 'Dotted',
                ),
              ),
              PopupMenuItem(
                value: InfiniteCanvasBackground.grid,
                child: _BackgroundMenuItem(icon: Icons.grid_4x4, label: 'Grid'),
              ),
            ],
            icon: const Icon(Icons.texture),
          ),
          IconButton(
            key: const ValueKey('infinite-canvas-recenter'),
            tooltip: 'Fit content',
            onPressed: document == null
                ? null
                : () => _viewportKey.currentState?.fitContent(document),
            icon: const Icon(Icons.center_focus_strong),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: document == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _InfiniteCanvasViewport(
                  key: _viewportKey,
                  document: document,
                  tool: _tool,
                  fingerPanEnabled: _fingerPanEnabled,
                  fingerWritingAssistEnabled: _fingerWritingAssistEnabled,
                  activeTextBoxId: _activeTextBoxId,
                  activeImageId: _activeImageId,
                  selectedStrokes: _selectedStrokes(document),
                  onStrokeComplete: _commitStroke,
                  onEraseStart: _beginErase,
                  onEraseAt: _eraseAt,
                  onEraseEnd: _endErase,
                  onTextBoxCreate: _addTextBoxAt,
                  onTextBoxChanged: _updateTextBox,
                  onTextBoxDeleted: _deleteTextBox,
                  onImageChanged: _updateImage,
                  onImageDeleted: _deleteImage,
                  onShapeComplete: _addShape,
                  onLassoSelectionComplete: _selectStrokes,
                  onSelectedStrokesPreviewChanged: (strokes) =>
                      _replaceSelectedStrokes(strokes, commit: false),
                  onSelectedStrokesChanged: (strokes) =>
                      _replaceSelectedStrokes(strokes, commit: true),
                  onClearLassoSelection: _clearLassoSelection,
                  onViewportChanged: _viewportChanged,
                ),
                if (_tool.type == ToolType.lasso &&
                    _selectedStrokeIds.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: LassoSelectionToolbar(
                        selectedStrokeCount: _selectedStrokeIds.length,
                        onSmartInk: null,
                        onColorChanged: _recolorSelectedStrokes,
                        onDelete: _deleteSelectedStrokes,
                        onClearSelection: _clearLassoSelection,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _BackgroundMenuItem extends StatelessWidget {
  const _BackgroundMenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]);
  }
}

class _InfiniteCanvasViewport extends StatefulWidget {
  const _InfiniteCanvasViewport({
    super.key,
    required this.document,
    required this.tool,
    required this.fingerPanEnabled,
    required this.fingerWritingAssistEnabled,
    required this.activeTextBoxId,
    required this.activeImageId,
    required this.selectedStrokes,
    required this.onStrokeComplete,
    required this.onEraseStart,
    required this.onEraseAt,
    required this.onEraseEnd,
    required this.onTextBoxCreate,
    required this.onTextBoxChanged,
    required this.onTextBoxDeleted,
    required this.onImageChanged,
    required this.onImageDeleted,
    required this.onShapeComplete,
    required this.onLassoSelectionComplete,
    required this.onSelectedStrokesPreviewChanged,
    required this.onSelectedStrokesChanged,
    required this.onClearLassoSelection,
    required this.onViewportChanged,
  });

  final InfiniteCanvasDocument document;
  final DrawingTool tool;
  final bool fingerPanEnabled;
  final bool fingerWritingAssistEnabled;
  final String? activeTextBoxId;
  final String? activeImageId;
  final List<Stroke> selectedStrokes;
  final ValueChanged<Stroke> onStrokeComplete;
  final VoidCallback onEraseStart;
  final ValueChanged<Offset> onEraseAt;
  final VoidCallback onEraseEnd;
  final ValueChanged<Offset> onTextBoxCreate;
  final ValueChanged<NoteTextBox> onTextBoxChanged;
  final ValueChanged<String> onTextBoxDeleted;
  final ValueChanged<NoteImage> onImageChanged;
  final ValueChanged<String> onImageDeleted;
  final ValueChanged<NoteShape> onShapeComplete;
  final ValueChanged<List<Offset>> onLassoSelectionComplete;
  final ValueChanged<List<Stroke>> onSelectedStrokesPreviewChanged;
  final ValueChanged<List<Stroke>> onSelectedStrokesChanged;
  final VoidCallback onClearLassoSelection;
  final void Function(Offset focus, double scale) onViewportChanged;

  @override
  State<_InfiniteCanvasViewport> createState() =>
      _InfiniteCanvasViewportState();
}

class _InfiniteCanvasViewportState extends State<_InfiniteCanvasViewport> {
  final Map<int, Offset> _touches = {};
  late Offset _focus = widget.document.viewportFocus;
  late double _scale = widget.document.viewportScale;
  Stroke? _activeStroke;
  int? _drawingPointer;
  PointerDeviceKind? _drawingKind;
  int? _panPointer;
  Offset? _lastPanPosition;
  Offset? _gestureFocal;
  double? _gestureDistance;
  bool _erasing = false;

  Offset get focus => _focus;

  Offset _screenToWorld(Offset point, Size size) {
    return (point - size.center(Offset.zero)) / _scale + _focus;
  }

  Offset _worldToScreen(Offset point, Size size) {
    return (point - _focus) * _scale + size.center(Offset.zero);
  }

  Size get _size => (context.findRenderObject()! as RenderBox).size;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length >= 2) {
        _cancelActiveStroke();
        _startTransformGesture();
        return;
      }
      if (widget.fingerPanEnabled) {
        _panPointer = event.pointer;
        _lastPanPosition = event.localPosition;
        return;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length >= 2) {
        _updateTransformGesture();
        return;
      }
      if (event.pointer == _panPointer) {
        final previous = _lastPanPosition;
        _lastPanPosition = event.localPosition;
        if (previous != null) {
          setState(() => _focus -= (event.localPosition - previous) / _scale);
        }
        return;
      }
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touches.remove(event.pointer);
      if (_touches.length < 2) {
        _gestureFocal = null;
        _gestureDistance = null;
      }
    }
    if (event.pointer == _panPointer) {
      _panPointer = null;
      _lastPanPosition = null;
      widget.onViewportChanged(_focus, _scale);
    }
    if (_touches.isEmpty && _gestureFocal != null) {
      widget.onViewportChanged(_focus, _scale);
    } else if (_touches.isEmpty) {
      widget.onViewportChanged(_focus, _scale);
    }
  }

  void _onDrawingPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch && widget.fingerPanEnabled) {
      return;
    }
    _startDrawing(
      event.pointer,
      event.kind,
      event.localPosition,
      event.pressure,
    );
  }

  void _onDrawingPointerMove(PointerMoveEvent event) {
    if (event.pointer == _drawingPointer) {
      _appendDrawing(event.localPosition, event.pressure);
    }
  }

  void _onDrawingPointerEnd(PointerEvent event) {
    if (event.pointer == _drawingPointer) {
      _finishDrawing();
    }
  }

  void _startDrawing(
    int pointer,
    PointerDeviceKind kind,
    Offset screenPoint,
    double pressure,
  ) {
    if (_drawingPointer != null) return;
    _drawingPointer = pointer;
    _drawingKind = kind;
    final point = _point(screenPoint, pressure);
    if (widget.tool.type == ToolType.eraser) {
      _erasing = true;
      widget.onEraseStart();
      widget.onEraseAt(point.offset);
      return;
    }
    if (widget.tool.type != ToolType.pen &&
        widget.tool.type != ToolType.highlighter) {
      _drawingPointer = null;
      return;
    }
    setState(() {
      _activeStroke = Stroke(
        id: 'stroke-${DateTime.now().microsecondsSinceEpoch}',
        tool: widget.tool.type,
        color: widget.tool.color,
        width: widget.tool.width,
        points: [point],
      );
    });
  }

  void _appendDrawing(Offset screenPoint, double pressure) {
    final point = _point(screenPoint, pressure);
    if (_erasing) {
      widget.onEraseAt(point.offset);
      return;
    }
    final stroke = _activeStroke;
    if (stroke == null ||
        !StrokeGeometry.shouldAppendPoint(
          stroke.points,
          point,
          minimumDistance: StrokeGeometry.defaultMinimumPointDistance / _scale,
        )) {
      return;
    }
    setState(
      () => _activeStroke = stroke.copyWith(points: [...stroke.points, point]),
    );
  }

  void _finishDrawing() {
    final stroke = _activeStroke;
    final kind = _drawingKind;
    _drawingPointer = null;
    _drawingKind = null;
    if (_erasing) {
      _erasing = false;
      widget.onEraseEnd();
      return;
    }
    if (stroke == null) return;
    setState(() => _activeStroke = null);
    widget.onStrokeComplete(
      applyFingerWritingAssist(
        stroke: stroke,
        pointerKind: kind,
        enabled: widget.fingerWritingAssistEnabled,
      ),
    );
  }

  void _cancelActiveStroke() {
    if (_drawingKind != PointerDeviceKind.touch) return;
    _drawingPointer = null;
    _drawingKind = null;
    if (_erasing) {
      _erasing = false;
      widget.onEraseEnd();
    }
    if (_activeStroke != null) setState(() => _activeStroke = null);
  }

  StrokePoint _point(Offset screenPoint, double pressure) {
    return StrokePoint(
      offset: _screenToWorld(screenPoint, _size),
      pressure: pressure == 0 ? 1 : pressure,
      time: DateTime.now(),
    );
  }

  void _startTransformGesture() {
    final points = _touches.values.take(2).toList();
    _gestureFocal = (points[0] + points[1]) / 2;
    _gestureDistance = (points[0] - points[1]).distance;
  }

  void _updateTransformGesture() {
    final points = _touches.values.take(2).toList();
    final focal = (points[0] + points[1]) / 2;
    final distance = (points[0] - points[1]).distance;
    final oldFocal = _gestureFocal;
    final oldDistance = _gestureDistance;
    if (oldFocal == null || oldDistance == null || oldDistance == 0) {
      _gestureFocal = focal;
      _gestureDistance = distance;
      return;
    }
    final size = _size;
    final anchor = _screenToWorld(oldFocal, size);
    final nextScale = (_scale * distance / oldDistance)
        .clamp(0.2, 6)
        .toDouble();
    setState(() {
      _scale = nextScale;
      _focus = anchor - (focal - size.center(Offset.zero)) / nextScale;
    });
    _gestureFocal = focal;
    _gestureDistance = distance;
  }

  void fitContent(InfiniteCanvasDocument document) {
    Rect? bounds = LassoGeometry.boundsForStrokes(document.strokes);
    void include(Rect rect) {
      bounds = bounds == null ? rect : bounds!.expandToInclude(rect);
    }

    for (final textBox in document.textBoxes) {
      include(
        Rect.fromLTWH(
          textBox.position.dx,
          textBox.position.dy,
          textBox.width,
          math.max(56, textBox.fontSize * 2.4),
        ),
      );
    }
    for (final noteImage in document.images) {
      include(
        Rect.fromLTWH(
          noteImage.position.dx,
          noteImage.position.dy,
          noteImage.width,
          noteImage.height,
        ),
      );
    }
    for (final shape in document.shapes) {
      include(shape.bounds.inflate(math.max(4, shape.width / 2)));
    }

    if (bounds == null) {
      setState(() {
        _focus = Offset.zero;
        _scale = 1;
      });
      widget.onViewportChanged(_focus, _scale);
      return;
    }
    final paddedBounds = bounds!.inflate(48);
    final size = _size;
    final nextScale = math
        .min(
          size.width / math.max(paddedBounds.width, 1),
          size.height / math.max(paddedBounds.height, 1),
        )
        .clamp(0.2, 2)
        .toDouble();
    setState(() {
      _focus = paddedBounds.center;
      _scale = nextScale;
    });
    widget.onViewportChanged(_focus, _scale);
  }

  Stroke _strokeToScreen(Stroke stroke, Size size) {
    return stroke.copyWith(
      width: stroke.width * _scale,
      points: [
        for (final point in stroke.points)
          StrokePoint(
            offset: _worldToScreen(point.offset, size),
            pressure: point.pressure,
            time: point.time,
          ),
      ],
    );
  }

  Stroke _strokeToWorld(Stroke stroke, Size size) {
    return stroke.copyWith(
      width: stroke.width / _scale,
      points: [
        for (final point in stroke.points)
          StrokePoint(
            offset: _screenToWorld(point.offset, size),
            pressure: point.pressure,
            time: point.time,
          ),
      ],
    );
  }

  NoteTextBox _textBoxToScreen(NoteTextBox textBox, Size size) {
    return textBox.copyWith(
      position: _worldToScreen(textBox.position, size),
      width: textBox.width * _scale,
      fontSize: textBox.fontSize * _scale,
    );
  }

  NoteTextBox _textBoxToWorld(NoteTextBox textBox, Size size) {
    return textBox.copyWith(
      position: _screenToWorld(textBox.position, size),
      width: textBox.width / _scale,
      fontSize: textBox.fontSize / _scale,
    );
  }

  NoteImage _imageToScreen(NoteImage noteImage, Size size) {
    return noteImage.copyWith(
      position: _worldToScreen(noteImage.position, size),
      width: noteImage.width * _scale,
      height: noteImage.height * _scale,
    );
  }

  NoteImage _imageToWorld(NoteImage noteImage, Size size) {
    return noteImage.copyWith(
      position: _screenToWorld(noteImage.position, size),
      width: noteImage.width / _scale,
      height: noteImage.height / _scale,
    );
  }

  NoteShape _shapeToScreen(NoteShape shape, Size size) {
    return shape.copyWith(
      start: _worldToScreen(shape.start, size),
      end: _worldToScreen(shape.end, size),
      width: shape.width * _scale,
    );
  }

  NoteShape _shapeToWorld(NoteShape shape, Size size) {
    return shape.copyWith(
      start: _screenToWorld(shape.start, size),
      end: _screenToWorld(shape.end, size),
      width: shape.width / _scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final screenStrokes = [
          for (final stroke in widget.document.strokes)
            _strokeToScreen(stroke, size),
        ];
        final screenPage = NotePage(
          id: 'infinite-canvas-viewport',
          width: size.width,
          height: size.height,
          strokes: screenStrokes,
          textBoxes: [
            for (final textBox in widget.document.textBoxes)
              _textBoxToScreen(textBox, size),
          ],
          images: [
            for (final noteImage in widget.document.images)
              _imageToScreen(noteImage, size),
          ],
          shapes: [
            for (final shape in widget.document.shapes)
              _shapeToScreen(shape, size),
          ],
        );
        final selectedIds = {
          for (final stroke in widget.selectedStrokes) stroke.id,
        };
        final selectedScreenStrokes = [
          for (final stroke in screenStrokes)
            if (selectedIds.contains(stroke.id)) stroke,
        ];

        return Listener(
          key: const ValueKey('infinite-canvas-viewport'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _InfiniteCanvasPainter(
                  strokes: const [],
                  background: widget.document.background,
                  focus: _focus,
                  scale: _scale,
                  gridColor: Theme.of(context).colorScheme.outlineVariant,
                ),
                child: const SizedBox.expand(),
              ),
              ImageLayer(
                page: screenPage,
                activeImageId: widget.activeImageId,
                showControls: false,
                onImageChanged: (_) {},
                onImageDeleted: (_) {},
              ),
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDrawingPointerDown,
                onPointerMove: _onDrawingPointerMove,
                onPointerUp: _onDrawingPointerEnd,
                onPointerCancel: _onDrawingPointerEnd,
                child: CustomPaint(
                  painter: _InfiniteCanvasPainter(
                    strokes: [...widget.document.strokes, ?_activeStroke],
                    background: widget.document.background,
                    focus: _focus,
                    scale: _scale,
                    gridColor: Theme.of(context).colorScheme.outlineVariant,
                    drawSurface: false,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              ShapeLayer(
                page: screenPage,
                tool: widget.tool.copyWith(width: widget.tool.width * _scale),
                fingerPanEnabled: widget.fingerPanEnabled,
                onShapeComplete: widget.tool.type == ToolType.shape
                    ? (shape) =>
                          widget.onShapeComplete(_shapeToWorld(shape, size))
                    : null,
              ),
              ImageLayer(
                page: screenPage,
                activeImageId: widget.activeImageId,
                showImage: false,
                onImageChanged: (noteImage) =>
                    widget.onImageChanged(_imageToWorld(noteImage, size)),
                onImageDeleted: widget.onImageDeleted,
              ),
              TextBoxLayer(
                page: screenPage,
                activeTextBoxId: widget.activeTextBoxId,
                onCreateTextBox: widget.tool.type == ToolType.text
                    ? (position) =>
                          widget.onTextBoxCreate(_screenToWorld(position, size))
                    : null,
                onTextBoxChanged: (textBox) =>
                    widget.onTextBoxChanged(_textBoxToWorld(textBox, size)),
                onTextBoxDeleted: widget.onTextBoxDeleted,
              ),
              if (widget.tool.type == ToolType.lasso)
                LassoSelectionLayer(
                  key: const ValueKey('infinite-canvas-lasso-layer'),
                  pageStrokes: screenStrokes,
                  selectedStrokes: selectedScreenStrokes,
                  onSelectionComplete: (polygon) =>
                      widget.onLassoSelectionComplete([
                        for (final point in polygon)
                          _screenToWorld(point, size),
                      ]),
                  onStrokesPreviewChanged: (strokes) =>
                      widget.onSelectedStrokesPreviewChanged([
                        for (final stroke in strokes)
                          _strokeToWorld(stroke, size),
                      ]),
                  onStrokesChanged: (strokes) =>
                      widget.onSelectedStrokesChanged([
                        for (final stroke in strokes)
                          _strokeToWorld(stroke, size),
                      ]),
                  onClearSelection: widget.onClearLassoSelection,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InfiniteCanvasPainter extends CustomPainter {
  const _InfiniteCanvasPainter({
    required this.strokes,
    required this.background,
    required this.focus,
    required this.scale,
    required this.gridColor,
    this.drawSurface = true,
  });

  final List<Stroke> strokes;
  final InfiniteCanvasBackground background;
  final Offset focus;
  final double scale;
  final Color gridColor;
  final bool drawSurface;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawSurface) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFF8F6F0),
      );
      _drawBackground(canvas, size);
    }
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size size) {
    if (background == InfiniteCanvasBackground.blank) return;
    var spacing = 32.0;
    while (spacing * scale < 16) {
      spacing *= 2;
    }
    final halfWorld = Offset(
      size.width / (2 * scale),
      size.height / (2 * scale),
    );
    final left = focus.dx - halfWorld.dx;
    final right = focus.dx + halfWorld.dx;
    final top = focus.dy - halfWorld.dy;
    final bottom = focus.dy + halfWorld.dy;
    final startX = (left / spacing).floor() * spacing;
    final startY = (top / spacing).floor() * spacing;
    final paint = Paint()..color = gridColor.withValues(alpha: 0.55);
    Offset screen(Offset world) =>
        (world - focus) * scale + size.center(Offset.zero);
    if (background == InfiniteCanvasBackground.grid) {
      paint.strokeWidth = 1;
      for (var x = startX; x <= right; x += spacing) {
        final screenX = screen(Offset(x, 0)).dx;
        canvas.drawLine(
          Offset(screenX, 0),
          Offset(screenX, size.height),
          paint,
        );
      }
      for (var y = startY; y <= bottom; y += spacing) {
        final screenY = screen(Offset(0, y)).dy;
        canvas.drawLine(Offset(0, screenY), Offset(size.width, screenY), paint);
      }
      return;
    }
    for (var x = startX; x <= right; x += spacing) {
      for (var y = startY; y <= bottom; y += spacing) {
        canvas.drawCircle(screen(Offset(x, y)), 1.25, paint);
      }
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = stroke.isHighlighter
          ? BlendMode.multiply
          : BlendMode.srcOver;
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first.offset,
        stroke.width * _pressure(stroke.points.first.pressure) / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    for (var index = 1; index < stroke.points.length; index++) {
      final previous = stroke.points[index - 1];
      final current = stroke.points[index];
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            stroke.width *
            (_pressure(previous.pressure) + _pressure(current.pressure)) /
            2;
      canvas.drawLine(previous.offset, current.offset, paint);
    }
  }

  double _pressure(double value) =>
      value <= 0 ? 1 : value.clamp(0.18, 1.35).toDouble();

  @override
  bool shouldRepaint(covariant _InfiniteCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.background != background ||
        oldDelegate.focus != focus ||
        oldDelegate.scale != scale ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.drawSurface != drawSurface;
  }
}

class _CanvasContentState {
  const _CanvasContentState({
    required this.strokes,
    required this.textBoxes,
    required this.images,
    required this.shapes,
  });

  factory _CanvasContentState.fromDocument(InfiniteCanvasDocument document) {
    return _CanvasContentState(
      strokes: document.strokes,
      textBoxes: document.textBoxes,
      images: document.images,
      shapes: document.shapes,
    );
  }

  final List<Stroke> strokes;
  final List<NoteTextBox> textBoxes;
  final List<NoteImage> images;
  final List<NoteShape> shapes;
}

bool _sameStrokeList(List<Stroke> first, List<Stroke> second) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (!identical(first[index], second[index])) return false;
  }
  return true;
}
