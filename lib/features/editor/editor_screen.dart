import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;
import 'package:inknest_notes/export/notebook_pdf_exporter.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/canvas/pdf_page_background.dart';
import 'package:inknest_notes/features/editor/images/image_layer.dart';
import 'package:inknest_notes/features/editor/shapes/shape_layer.dart';
import 'package:inknest_notes/features/editor/smart_ink/smart_ink_selection_layer.dart';
import 'package:inknest_notes/features/editor/text/note_text_box_styles.dart';
import 'package:inknest_notes/features/editor/text/text_box_layer.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/pdf_outline_entry.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.notebook,
    required this.notebookRepository,
  });

  final Notebook notebook;
  final NotebookRepository notebookRepository;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final List<Stroke> _redoStack = [];
  final Map<String, NotePage> _pagesById = {};
  DrawingTool _tool = const DrawingTool();
  late Notebook _notebook;
  late String _currentPageId;
  bool _isExporting = false;
  bool _fingerPanEnabled = false;
  String? _activeTextBoxId;
  String? _activeImageId;
  NotePage? _page;

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
    _currentPageId = _notebook.pageIds.first;
    _loadPage();
    unawaited(_loadPageThumbnails());
  }

  Future<void> _loadPage() async {
    final page = await widget.notebookRepository.loadPage(
      _notebook,
      _currentPageId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _page = page;
      _pagesById[page.id] = page;
      _redoStack.clear();
      _activeTextBoxId = null;
      _activeImageId = null;
    });
  }

  Future<void> _loadPageThumbnails() async {
    final notebook = _notebook;
    final missingPageIds = [
      for (final pageId in notebook.pageIds)
        if (!_pagesById.containsKey(pageId)) pageId,
    ];

    if (missingPageIds.isEmpty) {
      return;
    }

    final loadedPages = <String, NotePage>{};
    for (final pageId in missingPageIds) {
      loadedPages[pageId] = await widget.notebookRepository.loadPage(
        notebook,
        pageId,
      );
    }

    if (!mounted || notebook.id != _notebook.id) {
      return;
    }

    setState(() {
      for (final entry in loadedPages.entries) {
        if (_notebook.pageIds.contains(entry.key) &&
            !_pagesById.containsKey(entry.key)) {
          _pagesById[entry.key] = entry.value;
        }
      }
      if (_page case final currentPage?) {
        _pagesById[currentPage.id] = currentPage;
      }
    });
  }

  void _addStroke(Stroke stroke) {
    final page = _page;
    if (page == null) {
      return;
    }

    final updatedPage = page.copyWith(strokes: [...page.strokes, stroke]);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  void _addShape(NoteShape shape) {
    final page = _page;
    if (page == null) {
      return;
    }

    final updatedPage = page.copyWith(shapes: [...page.shapes, shape]);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  void _addTextBoxAt(Offset position) {
    final page = _page;
    if (page == null) {
      return;
    }

    final width = math.min(240.0, math.max(120.0, page.width - 32));
    final textBox = NoteTextBox(
      id: 'text-${DateTime.now().microsecondsSinceEpoch}',
      position: _clampTextBoxPosition(
        page: page,
        position: position - Offset(width / 2, 24),
        width: width,
      ),
      width: width,
      color: _tool.color,
    );
    final updatedPage = page.copyWith(textBoxes: [...page.textBoxes, textBox]);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _activeTextBoxId = textBox.id;
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  void _updateTextBox(NoteTextBox textBox) {
    final page = _page;
    if (page == null) {
      return;
    }

    final updatedTextBoxes = [
      for (final existingTextBox in page.textBoxes)
        if (existingTextBox.id == textBox.id) textBox else existingTextBox,
    ];
    final updatedPage = page.copyWith(textBoxes: updatedTextBoxes);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _activeTextBoxId = textBox.id;
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  void _deleteTextBox(String textBoxId) {
    final page = _page;
    if (page == null) {
      return;
    }

    final updatedTextBoxes = [
      for (final textBox in page.textBoxes)
        if (textBox.id != textBoxId) textBox,
    ];
    if (updatedTextBoxes.length == page.textBoxes.length) {
      return;
    }

    final updatedPage = page.copyWith(textBoxes: updatedTextBoxes);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      if (_activeTextBoxId == textBoxId) {
        _activeTextBoxId = null;
      }
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  Future<void> _insertImage() async {
    final page = _page;
    if (page == null) {
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || result == null) {
      return;
    }

    final sourceFile = await _sourceFileForPickedImage(result.files.single);
    if (!mounted || sourceFile == null) {
      _showSnackBar('Image file is unavailable');
      return;
    }

    try {
      final pixelSize = await _imagePixelSize(sourceFile);
      final displaySize = _displaySizeForImage(page, pixelSize);
      final position = Offset(
        (page.width - displaySize.width) / 2,
        (page.height - displaySize.height) / 2,
      );
      final noteImage = await widget.notebookRepository.importImage(
        _notebook,
        sourceFile,
        position: _clampImagePosition(
          page: page,
          position: position,
          width: displaySize.width,
          height: displaySize.height,
        ),
        width: displaySize.width,
        height: displaySize.height,
      );

      if (!mounted) {
        return;
      }

      final latestPage = _page;
      if (latestPage == null) {
        return;
      }

      final updatedPage = latestPage.copyWith(
        images: [...latestPage.images, noteImage],
      );

      setState(() {
        _page = updatedPage;
        _pagesById[updatedPage.id] = updatedPage;
        _activeImageId = noteImage.id;
        _redoStack.clear();
      });

      unawaited(_savePage(updatedPage));
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showSnackBar('Insert image failed: $error');
    }
  }

  Future<File?> _sourceFileForPickedImage(PlatformFile pickedFile) async {
    if (pickedFile.path case final path?) {
      return File(path);
    }

    final bytes = pickedFile.bytes;
    if (bytes == null) {
      return null;
    }

    final extension = pickedFile.extension?.trim();
    final suffix = extension == null || extension.isEmpty ? 'png' : extension;
    final tempFile = File(
      '${Directory.systemTemp.path}/inknest-picked-image-'
      '${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile;
  }

  Future<Size> _imagePixelSize(File file) async {
    final decodedImage = image.decodeImage(await file.readAsBytes());
    if (decodedImage == null) {
      return const Size(320, 240);
    }

    return Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
  }

  Size _displaySizeForImage(NotePage page, Size pixelSize) {
    final intrinsicWidth = math.max(1.0, pixelSize.width);
    final intrinsicHeight = math.max(1.0, pixelSize.height);
    final maxWidth = math.max(120.0, page.width * 0.62);
    final maxHeight = math.max(120.0, page.height * 0.46);
    var scale = math.min(
      maxWidth / intrinsicWidth,
      maxHeight / intrinsicHeight,
    );

    if (scale > 1) {
      final smallestSide = math.min(intrinsicWidth, intrinsicHeight);
      scale = math.min(scale, 96 / smallestSide);
      scale = math.max(1.0, scale);
    }

    return Size(intrinsicWidth * scale, intrinsicHeight * scale);
  }

  void _updateImage(NoteImage noteImage) {
    final page = _page;
    if (page == null) {
      return;
    }

    final updatedImages = [
      for (final existingImage in page.images)
        if (existingImage.id == noteImage.id) noteImage else existingImage,
    ];
    final updatedPage = page.copyWith(images: updatedImages);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _activeImageId = noteImage.id;
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  void _deleteImage(String imageId) {
    final page = _page;
    if (page == null) {
      return;
    }

    final updatedImages = [
      for (final image in page.images)
        if (image.id != imageId) image,
    ];
    if (updatedImages.length == page.images.length) {
      return;
    }

    final updatedPage = page.copyWith(images: updatedImages);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      if (_activeImageId == imageId) {
        _activeImageId = null;
      }
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  Offset _clampImagePosition({
    required NotePage page,
    required Offset position,
    required double width,
    required double height,
  }) {
    final maxX = math.max(0.0, page.width - width);
    final maxY = math.max(0.0, page.height - height);
    return Offset(
      position.dx.clamp(0, maxX).toDouble(),
      position.dy.clamp(0, maxY).toDouble(),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Offset _clampTextBoxPosition({
    required NotePage page,
    required Offset position,
    required double width,
  }) {
    final maxX = math.max(0.0, page.width - width);
    final maxY = math.max(0.0, page.height - 64);
    return Offset(
      position.dx.clamp(0, maxX).toDouble(),
      position.dy.clamp(0, maxY).toDouble(),
    );
  }

  void _undo() {
    final page = _page;
    if (page == null || page.strokes.isEmpty) {
      return;
    }

    final updatedStrokes = page.strokes.toList();
    _redoStack.add(updatedStrokes.removeLast());
    final updatedPage = page.copyWith(strokes: updatedStrokes);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
    });

    unawaited(_savePage(updatedPage));
  }

  void _redo() {
    final page = _page;
    if (page == null || _redoStack.isEmpty) {
      return;
    }

    final stroke = _redoStack.removeLast();
    final updatedPage = page.copyWith(strokes: [...page.strokes, stroke]);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
    });

    unawaited(_savePage(updatedPage));
  }

  void _setTool(DrawingTool tool) {
    setState(() {
      _tool = tool;
    });
  }

  void _setFingerPanEnabled(bool value) {
    setState(() {
      _fingerPanEnabled = value;
    });
  }

  void _eraseAt(List<StrokePoint> points) {
    final page = _page;
    if (page == null) {
      return;
    }

    final remainingStrokes = StrokeGeometry.eraseStrokes(
      strokes: page.strokes,
      eraserPoints: points,
      radius: _tool.width / 2,
    );

    if (identical(remainingStrokes, page.strokes)) {
      return;
    }

    final updatedPage = page.copyWith(strokes: remainingStrokes);

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  Future<void> _runSmartInk(Rect selectionRect) async {
    final page = _page;
    if (page == null) {
      return;
    }

    final selectedStrokes = [
      for (final stroke in page.strokes)
        if (_strokeOverlapsRect(stroke, selectionRect)) stroke,
    ];

    if (selectedStrokes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No handwriting selected')));
      return;
    }

    final result = await showDialog<_SmartInkConfirmation>(
      context: context,
      builder: (context) => _SmartInkConfirmationDialog(
        selectedStrokeCount: selectedStrokes.length,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final text = result.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Smart Ink text is empty')));
      return;
    }

    final selectedStrokeIds = selectedStrokes
        .map((stroke) => stroke.id)
        .toSet();
    final selectedBounds = _boundsForStrokes(selectedStrokes).inflate(8);
    final textWidth = math.min(
      math.max(180.0, selectedBounds.width + 48),
      page.width,
    );
    final textBox = NoteTextBox(
      id: 'smart-ink-${DateTime.now().microsecondsSinceEpoch}',
      position: _clampTextBoxPosition(
        page: page,
        position: selectedBounds.topLeft,
        width: textWidth,
      ),
      text: text,
      width: textWidth,
      color: selectedStrokes.first.color,
      fontSize: math.min(math.max(22.0, selectedBounds.height * 0.45), 34.0),
      style: NoteTextBoxStyle.handwriting,
    );
    final updatedPage = page.copyWith(
      strokes: result.replaceSelectedInk
          ? [
              for (final stroke in page.strokes)
                if (!selectedStrokeIds.contains(stroke.id)) stroke,
            ]
          : page.strokes,
      textBoxes: [...page.textBoxes, textBox],
    );

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _activeTextBoxId = textBox.id;
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  bool _strokeOverlapsRect(Stroke stroke, Rect rect) {
    final bounds = _boundsForStroke(stroke);
    if (bounds == null) {
      return false;
    }

    return bounds.overlaps(rect) || rect.contains(bounds.center);
  }

  Rect _boundsForStrokes(List<Stroke> strokes) {
    final bounds = [for (final stroke in strokes) ?_boundsForStroke(stroke)];

    return bounds.reduce((value, element) => value.expandToInclude(element));
  }

  Rect? _boundsForStroke(Stroke stroke) {
    if (stroke.points.isEmpty) {
      return null;
    }

    var left = stroke.points.first.offset.dx;
    var top = stroke.points.first.offset.dy;
    var right = left;
    var bottom = top;
    for (final point in stroke.points.skip(1)) {
      left = math.min(left, point.offset.dx);
      top = math.min(top, point.offset.dy);
      right = math.max(right, point.offset.dx);
      bottom = math.max(bottom, point.offset.dy);
    }

    final padding = math.max(stroke.width / 2, 4.0);
    return Rect.fromLTRB(left, top, right, bottom).inflate(padding);
  }

  Future<void> _savePage([NotePage? page]) async {
    final pageToSave = page ?? _page;
    if (pageToSave == null) {
      return;
    }

    await widget.notebookRepository.savePage(_notebook, pageToSave);
  }

  Future<void> _setCurrentPageBookmarked(bool isBookmarked) async {
    final updatedNotebook = await widget.notebookRepository.setPageBookmarked(
      _notebook,
      _currentPageId,
      isBookmarked,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _notebook = updatedNotebook;
    });
  }

  void _showNavigationSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return _PdfNavigationSheet(
          notebook: _notebook,
          currentPageId: _currentPageId,
          onSelectPage: (pageId) {
            Navigator.of(sheetContext).pop();
            unawaited(_selectPage(pageId));
          },
        );
      },
    );
  }

  Future<void> _addPage() async {
    final updatedNotebook = await widget.notebookRepository.addPage(_notebook);

    if (!mounted) {
      return;
    }

    setState(() {
      _notebook = updatedNotebook;
      _currentPageId = updatedNotebook.pageIds.last;
      _page = null;
      _redoStack.clear();
    });

    await _loadPage();
    unawaited(_loadPageThumbnails());
  }

  Future<void> _insertPage(int index) async {
    await _savePage();

    final previousPageIds = _notebook.pageIds.toSet();
    final updatedNotebook = await widget.notebookRepository.insertPage(
      _notebook,
      index,
    );

    if (!mounted) {
      return;
    }

    final insertedPageId = updatedNotebook.pageIds.firstWhere(
      (updatedPageId) => !previousPageIds.contains(updatedPageId),
      orElse: () =>
          updatedNotebook.pageIds[index
              .clamp(0, updatedNotebook.pageIds.length - 1)
              .toInt()],
    );

    setState(() {
      _notebook = updatedNotebook;
      _currentPageId = insertedPageId;
      _page = null;
      _redoStack.clear();
    });

    await _loadPage();
    unawaited(_loadPageThumbnails());
  }

  Future<void> _duplicatePage(String pageId) async {
    await _savePage();

    final previousPageIds = _notebook.pageIds.toSet();
    final updatedNotebook = await widget.notebookRepository.duplicatePage(
      _notebook,
      pageId,
    );

    if (!mounted) {
      return;
    }

    final duplicatedPageId = updatedNotebook.pageIds.firstWhere(
      (updatedPageId) => !previousPageIds.contains(updatedPageId),
      orElse: () => pageId,
    );

    setState(() {
      _notebook = updatedNotebook;
      _currentPageId = duplicatedPageId;
      _page = null;
      _redoStack.clear();
    });

    await _loadPage();
    unawaited(_loadPageThumbnails());
  }

  Future<void> _deletePage(String pageId) async {
    if (_notebook.pageIds.length <= 1) {
      return;
    }

    final pageNumber = _notebook.pageIds.indexOf(pageId) + 1;
    final shouldDelete = await _confirmDeletePage(pageNumber);
    if (!shouldDelete || !mounted) {
      return;
    }

    await _savePage();

    final previousIndex = _notebook.pageIds.indexOf(pageId);
    final isDeletingCurrentPage = pageId == _currentPageId;
    final updatedNotebook = await widget.notebookRepository.deletePage(
      _notebook,
      pageId,
    );

    if (!mounted) {
      return;
    }

    final nextPageId = isDeletingCurrentPage
        ? updatedNotebook.pageIds[math.min(
            previousIndex,
            updatedNotebook.pageIds.length - 1,
          )]
        : _currentPageId;

    setState(() {
      _notebook = updatedNotebook;
      _currentPageId = nextPageId;
      _pagesById.remove(pageId);
      if (isDeletingCurrentPage) {
        _page = null;
        _redoStack.clear();
      }
    });

    if (isDeletingCurrentPage) {
      await _loadPage();
    }
    unawaited(_loadPageThumbnails());
  }

  Future<bool> _confirmDeletePage(int pageNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete page?'),
          content: Text('Page $pageNumber will be removed from this notebook.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _movePage(String pageId, int newIndex) async {
    await _savePage();

    final updatedNotebook = await widget.notebookRepository.movePage(
      _notebook,
      pageId,
      newIndex,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _notebook = updatedNotebook;
    });
    unawaited(_loadPageThumbnails());
  }

  Future<void> _exportPdf() async {
    if (_isExporting) {
      return;
    }

    final selection = await showDialog<_ExportSelection>(
      context: context,
      builder: (context) {
        return _ExportOptionsDialog(
          pageIds: _notebook.pageIds,
          currentPageId: _currentPageId,
        );
      },
    );

    if (!mounted || selection == null) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      await _savePage();
      final bytes = await NotebookPdfExporter(
        notebookRepository: widget.notebookRepository,
      ).exportNotebook(_notebook, pageIds: selection.pageIds);
      final fileName = _exportFileName(selection);
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Export notebook',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null ? 'Export canceled' : 'Exported $fileName',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  String _exportFileName(_ExportSelection selection) {
    final sanitizedTitle = _notebook.title.trim().replaceAll(
      RegExp(r'[\\/:*?"<>|]+'),
      '-',
    );
    final title = sanitizedTitle.isEmpty ? 'InkNest Notes' : sanitizedTitle;
    final baseName = title.toLowerCase().endsWith('.pdf')
        ? title.substring(0, title.length - 4)
        : title;

    return '$baseName${selection.fileNameSuffix}.pdf';
  }

  Future<void> _selectPage(String pageId) async {
    if (pageId == _currentPageId) {
      return;
    }

    setState(() {
      _currentPageId = pageId;
      _page = null;
      _redoStack.clear();
    });

    await _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final isCurrentPageBookmarked = _notebook.bookmarkedPageIds.contains(
      _currentPageId,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_notebook.title),
        actions: [
          IconButton(
            onPressed: _showNavigationSheet,
            tooltip: 'Outline and bookmarks',
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            onPressed: page == null
                ? null
                : () => unawaited(
                    _setCurrentPageBookmarked(!isCurrentPageBookmarked),
                  ),
            tooltip: isCurrentPageBookmarked
                ? 'Remove bookmark'
                : 'Bookmark page',
            icon: Icon(
              isCurrentPageBookmarked ? Icons.bookmark : Icons.bookmark_border,
            ),
          ),
          IconButton(
            onPressed: page == null || _isExporting
                ? null
                : () => unawaited(_exportPdf()),
            tooltip: 'Export PDF',
            icon: _isExporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
          ),
          IconButton(
            onPressed: page == null || page.strokes.isEmpty ? null : _undo,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: _redoStack.isEmpty ? null : _redo,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      body: Column(
        children: [
          EditorToolbar(
            tool: _tool,
            fingerPanEnabled: _fingerPanEnabled,
            onToolChanged: _setTool,
            onFingerPanChanged: _setFingerPanEnabled,
            onInsertImage: () => unawaited(_insertImage()),
          ),
          Expanded(
            child: page == null
                ? const Center(child: CircularProgressIndicator())
                : _buildPageCanvas(page),
          ),
          _PageNavigator(
            pageIds: _notebook.pageIds,
            pagesById: _pagesById,
            currentPageId: _currentPageId,
            bookmarkedPageIds: _notebook.bookmarkedPageIds.toSet(),
            onSelectPage: (pageId) => unawaited(_selectPage(pageId)),
            onAddPage: () => unawaited(_addPage()),
            onInsertPage: (index) => unawaited(_insertPage(index)),
            onDuplicatePage: (pageId) => unawaited(_duplicatePage(pageId)),
            onDeletePage: (pageId) => unawaited(_deletePage(pageId)),
            onMovePage: (pageId, newIndex) =>
                unawaited(_movePage(pageId, newIndex)),
          ),
        ],
      ),
    );
  }

  Widget _buildPageCanvas(NotePage page) {
    return _ZoomablePageViewport(
      key: ValueKey('viewport-${page.id}'),
      page: page,
      fingerPanEnabled: _fingerPanEnabled,
      child: _buildPageSurface(page),
    );
  }

  Widget _buildPageSurface(NotePage page) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4DED1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1E2526),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (page.pdfBackground case final background?)
              PdfPageBackgroundView(
                key: ValueKey(
                  '${background.filePath}-${background.pageNumber}',
                ),
                background: background,
              ),
            ImageLayer(
              page: page,
              activeImageId: _activeImageId,
              showControls: false,
              onImageChanged: _updateImage,
              onImageDeleted: _deleteImage,
            ),
            DrawingCanvas(
              page: page,
              tool: _tool,
              fingerPanEnabled: _fingerPanEnabled,
              onStrokeComplete: _addStroke,
              onErase: _eraseAt,
            ),
            ShapeLayer(
              page: page,
              tool: _tool,
              fingerPanEnabled: _fingerPanEnabled,
              onShapeComplete: _tool.type == ToolType.shape ? _addShape : null,
            ),
            ImageLayer(
              page: page,
              activeImageId: _activeImageId,
              showImage: false,
              onImageChanged: _updateImage,
              onImageDeleted: _deleteImage,
            ),
            TextBoxLayer(
              page: page,
              activeTextBoxId: _activeTextBoxId,
              onCreateTextBox: _tool.type == ToolType.text
                  ? _addTextBoxAt
                  : null,
              onTextBoxChanged: _updateTextBox,
              onTextBoxDeleted: _deleteTextBox,
            ),
            if (_tool.type == ToolType.smartInk)
              SmartInkSelectionLayer(
                onSelectionComplete: (rect) => unawaited(_runSmartInk(rect)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmartInkConfirmation {
  const _SmartInkConfirmation({
    required this.text,
    required this.replaceSelectedInk,
  });

  final String text;
  final bool replaceSelectedInk;
}

class _SmartInkConfirmationDialog extends StatefulWidget {
  const _SmartInkConfirmationDialog({required this.selectedStrokeCount});

  final int selectedStrokeCount;

  @override
  State<_SmartInkConfirmationDialog> createState() =>
      _SmartInkConfirmationDialogState();
}

class _SmartInkConfirmationDialogState
    extends State<_SmartInkConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _replaceSelectedInk = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();

    return AlertDialog(
      title: const Text('Smart Ink'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selected ${widget.selectedStrokeCount} strokes'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Recognized text',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _replaceSelectedInk,
              onChanged: (value) {
                setState(() {
                  _replaceSelectedInk = value ?? true;
                });
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Replace selected ink'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: text.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _SmartInkConfirmation(
                    text: text,
                    replaceSelectedInk: _replaceSelectedInk,
                  ),
                ),
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('Beautify'),
        ),
      ],
    );
  }
}

enum _ExportScope { fullNotebook, currentPage, pageRange }

class _ExportSelection {
  const _ExportSelection({required this.pageIds, required this.fileNameSuffix});

  final List<String> pageIds;
  final String fileNameSuffix;
}

class _ExportOptionsDialog extends StatefulWidget {
  const _ExportOptionsDialog({
    required this.pageIds,
    required this.currentPageId,
  });

  final List<String> pageIds;
  final String currentPageId;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  _ExportScope _scope = _ExportScope.fullNotebook;
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  int get _pageCount => widget.pageIds.length;

  int get _currentPageNumber {
    final currentIndex = widget.pageIds.indexOf(widget.currentPageId);
    return currentIndex == -1 ? 1 : currentIndex + 1;
  }

  @override
  void initState() {
    super.initState();
    final currentPageNumber = _currentPageNumber.toString();
    _startController = TextEditingController(text: currentPageNumber);
    _endController = TextEditingController(text: currentPageNumber);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rangeError = _scope == _ExportScope.pageRange ? _rangeError : null;
    final selection = _selectionOrNull;

    return AlertDialog(
      title: const Text('Export PDF'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<_ExportScope>(
                showSelectedIcon: false,
                selected: {_scope},
                segments: const [
                  ButtonSegment(
                    value: _ExportScope.fullNotebook,
                    icon: Icon(Icons.library_books_outlined),
                    label: Text('Full'),
                  ),
                  ButtonSegment(
                    value: _ExportScope.currentPage,
                    icon: Icon(Icons.description_outlined),
                    label: Text('Current'),
                  ),
                  ButtonSegment(
                    value: _ExportScope.pageRange,
                    icon: Icon(Icons.view_agenda_outlined),
                    label: Text('Range'),
                  ),
                ],
                onSelectionChanged: (selected) {
                  setState(() {
                    _scope = selected.single;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text(
                _scopeSummary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_scope == _ExportScope.pageRange) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startController,
                        decoration: const InputDecoration(
                          labelText: 'From',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endController,
                        decoration: const InputDecoration(
                          labelText: 'To',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (rangeError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    rangeError,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: selection == null
              ? null
              : () => Navigator.of(context).pop(selection),
          icon: const Icon(Icons.ios_share),
          label: const Text('Export'),
        ),
      ],
    );
  }

  String get _scopeSummary {
    return switch (_scope) {
      _ExportScope.fullNotebook => 'All $_pageCount pages',
      _ExportScope.currentPage => 'Page $_currentPageNumber',
      _ExportScope.pageRange => 'Pages 1-$_pageCount',
    };
  }

  String? get _rangeError {
    final start = int.tryParse(_startController.text.trim());
    final end = int.tryParse(_endController.text.trim());

    if (start == null || end == null) {
      return 'Enter page numbers.';
    }
    if (start < 1 || end < 1 || start > _pageCount || end > _pageCount) {
      return 'Pages must be between 1 and $_pageCount.';
    }
    if (start > end) {
      return 'From must be before To.';
    }

    return null;
  }

  _ExportSelection? get _selectionOrNull {
    if (widget.pageIds.isEmpty) {
      return null;
    }

    return switch (_scope) {
      _ExportScope.fullNotebook => _ExportSelection(
        pageIds: List.unmodifiable(widget.pageIds),
        fileNameSuffix: '',
      ),
      _ExportScope.currentPage => _currentPageSelection,
      _ExportScope.pageRange => _rangeSelection,
    };
  }

  _ExportSelection? get _currentPageSelection {
    final currentIndex = widget.pageIds.indexOf(widget.currentPageId);
    if (currentIndex == -1) {
      return null;
    }

    return _ExportSelection(
      pageIds: [widget.currentPageId],
      fileNameSuffix: '-page-${currentIndex + 1}',
    );
  }

  _ExportSelection? get _rangeSelection {
    if (_rangeError != null) {
      return null;
    }

    final start = int.parse(_startController.text.trim());
    final end = int.parse(_endController.text.trim());
    final suffix = start == end ? '-page-$start' : '-pages-$start-$end';

    return _ExportSelection(
      pageIds: List.unmodifiable(widget.pageIds.sublist(start - 1, end)),
      fileNameSuffix: suffix,
    );
  }
}

class _PdfNavigationSheet extends StatelessWidget {
  const _PdfNavigationSheet({
    required this.notebook,
    required this.currentPageId,
    required this.onSelectPage,
  });

  final Notebook notebook;
  final String currentPageId;
  final ValueChanged<String> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final initialIndex =
        notebook.pdfOutlines.isEmpty && notebook.bookmarkedPageIds.isNotEmpty
        ? 1
        : 0;

    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.format_list_bulleted), text: 'Outline'),
                  Tab(icon: Icon(Icons.bookmark_border), text: 'Bookmarks'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _OutlineTab(
                      notebook: notebook,
                      currentPageId: currentPageId,
                      onSelectPage: onSelectPage,
                    ),
                    _BookmarksTab(
                      notebook: notebook,
                      currentPageId: currentPageId,
                      onSelectPage: onSelectPage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineTab extends StatelessWidget {
  const _OutlineTab({
    required this.notebook,
    required this.currentPageId,
    required this.onSelectPage,
  });

  final Notebook notebook;
  final String currentPageId;
  final ValueChanged<String> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final entries = _flattenOutlineEntries(notebook.pdfOutlines);
    if (entries.isEmpty) {
      return const _NavigationEmptyState(
        icon: Icons.format_list_bulleted,
        title: 'No PDF outline',
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final pageId = entry.outline.pageId;
        final canOpen = pageId != null && notebook.pageIds.contains(pageId);
        final isSelected = pageId == currentPageId;

        return ListTile(
          enabled: canOpen,
          contentPadding: EdgeInsets.only(
            left: 16 + entry.depth * 20,
            right: 16,
          ),
          leading: Icon(
            isSelected ? Icons.radio_button_checked : Icons.article_outlined,
          ),
          title: Text(
            entry.outline.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: pageId == null ? null : Text(_pageLabel(notebook, pageId)),
          onTap: canOpen ? () => onSelectPage(pageId) : null,
        );
      },
    );
  }
}

class _BookmarksTab extends StatelessWidget {
  const _BookmarksTab({
    required this.notebook,
    required this.currentPageId,
    required this.onSelectPage,
  });

  final Notebook notebook;
  final String currentPageId;
  final ValueChanged<String> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final bookmarkedPageIds = [
      for (final pageId in notebook.bookmarkedPageIds)
        if (notebook.pageIds.contains(pageId)) pageId,
    ];

    if (bookmarkedPageIds.isEmpty) {
      return const _NavigationEmptyState(
        icon: Icons.bookmark_border,
        title: 'No bookmarks',
      );
    }

    return ListView.builder(
      itemCount: bookmarkedPageIds.length,
      itemBuilder: (context, index) {
        final pageId = bookmarkedPageIds[index];
        final isSelected = pageId == currentPageId;

        return ListTile(
          leading: Icon(isSelected ? Icons.bookmark : Icons.bookmark_border),
          title: Text(_pageLabel(notebook, pageId)),
          onTap: () => onSelectPage(pageId),
        );
      },
    );
  }
}

class _NavigationEmptyState extends StatelessWidget {
  const _NavigationEmptyState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlattenedOutlineEntry {
  const _FlattenedOutlineEntry({required this.outline, required this.depth});

  final PdfOutlineEntry outline;
  final int depth;
}

List<_FlattenedOutlineEntry> _flattenOutlineEntries(
  List<PdfOutlineEntry> outlines, [
  int depth = 0,
]) {
  return [
    for (final outline in outlines) ...[
      _FlattenedOutlineEntry(outline: outline, depth: depth),
      ..._flattenOutlineEntries(outline.children, depth + 1),
    ],
  ];
}

String _pageLabel(Notebook notebook, String pageId) {
  final pageIndex = notebook.pageIds.indexOf(pageId);
  return pageIndex == -1 ? 'Missing page' : 'Page ${pageIndex + 1}';
}

class _ZoomablePageViewport extends StatefulWidget {
  const _ZoomablePageViewport({
    super.key,
    required this.page,
    required this.fingerPanEnabled,
    required this.child,
  });

  final NotePage page;
  final bool fingerPanEnabled;
  final Widget child;

  @override
  State<_ZoomablePageViewport> createState() => _ZoomablePageViewportState();
}

class _ZoomablePageViewportState extends State<_ZoomablePageViewport> {
  static const _padding = 24.0;
  static const _minScale = 1.0;
  static const _maxScale = 4.0;
  static const _minimumVisiblePageExtent = 96.0;

  final Map<int, Offset> _activePointers = {};
  double _scale = 1.0;
  Offset _pan = Offset.zero;
  Offset? _lastFocalPoint;
  double? _lastPointerDistance;
  Size _viewportSize = Size.zero;
  Size _pageSize = Size.zero;
  Offset _pageOrigin = Offset.zero;

  @override
  void didUpdateWidget(covariant _ZoomablePageViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page.id != oldWidget.page.id) {
      _resetZoom();
    }
    if (widget.fingerPanEnabled != oldWidget.fingerPanEnabled) {
      _activePointers.clear();
      _lastFocalPoint = null;
      _lastPointerDistance = null;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }

    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length >= 2) {
      _primePinchGesture();
    } else if (widget.fingerPanEnabled) {
      _lastFocalPoint = event.localPosition;
      _lastPointerDistance = null;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) {
      return;
    }

    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 1) {
      if (widget.fingerPanEnabled) {
        _handleSingleFingerPan(event.localPosition);
      }
      return;
    }

    final focalPoint = _pinchFocalPoint();
    final distance = _pinchDistance();
    final previousFocalPoint = _lastFocalPoint;
    final previousDistance = _lastPointerDistance;

    if (previousFocalPoint != null &&
        previousDistance != null &&
        previousDistance > 0 &&
        distance > 0) {
      _applyPinchUpdate(
        previousFocalPoint: previousFocalPoint,
        focalPoint: focalPoint,
        scaleFactor: distance / previousDistance,
      );
    }

    _lastFocalPoint = focalPoint;
    _lastPointerDistance = distance;
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }

    _activePointers.remove(event.pointer);
    if (_activePointers.length >= 2) {
      _primePinchGesture();
    } else if (_activePointers.length == 1 && widget.fingerPanEnabled) {
      _lastFocalPoint = _activePointers.values.single;
      _lastPointerDistance = null;
    } else {
      _lastFocalPoint = null;
      _lastPointerDistance = null;
    }
  }

  void _handleSingleFingerPan(Offset focalPoint) {
    final previousFocalPoint = _lastFocalPoint;
    if (previousFocalPoint != null) {
      final delta = focalPoint - previousFocalPoint;
      setState(() {
        _pan = _clampPan(_pan + delta);
      });
    }

    _lastFocalPoint = focalPoint;
  }

  void _primePinchGesture() {
    if (_activePointers.length < 2) {
      return;
    }

    _lastFocalPoint = _pinchFocalPoint();
    _lastPointerDistance = _pinchDistance();
  }

  void _applyPinchUpdate({
    required Offset previousFocalPoint,
    required Offset focalPoint,
    required double scaleFactor,
  }) {
    final pagePoint = _viewportToPage(previousFocalPoint);
    final nextScale = (_scale * scaleFactor).clamp(_minScale, _maxScale);
    final nextPan = _panForPagePoint(
      pagePoint: pagePoint,
      focalPoint: focalPoint,
      scale: nextScale,
    );

    setState(() {
      _scale = nextScale.toDouble();
      _pan = _clampPan(nextPan, scale: _scale);
    });
  }

  void _zoomBy(double scaleFactor) {
    final focalPoint = Offset(
      _viewportSize.width / 2,
      _viewportSize.height / 2,
    );
    _applyPinchUpdate(
      previousFocalPoint: focalPoint,
      focalPoint: focalPoint,
      scaleFactor: scaleFactor,
    );
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
      _pan = Offset.zero;
      _lastFocalPoint = null;
      _lastPointerDistance = null;
    });
  }

  Offset _pinchFocalPoint() {
    final points = _activePointers.values.take(2).toList();
    return Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
  }

  double _pinchDistance() {
    final points = _activePointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  Offset _viewportToPage(Offset viewportPoint) {
    final center = _pageCenter;
    return (viewportPoint - _pageOrigin - _pan - center) / _scale + center;
  }

  Offset _panForPagePoint({
    required Offset pagePoint,
    required Offset focalPoint,
    required double scale,
  }) {
    final center = _pageCenter;
    return focalPoint - _pageOrigin - center - (pagePoint - center) * scale;
  }

  Offset _clampPan(Offset pan, {double? scale}) {
    if (_pageSize == Size.zero || _viewportSize == Size.zero) {
      return pan;
    }

    final effectiveScale = scale ?? _scale;
    final scaledSize = Size(
      _pageSize.width * effectiveScale,
      _pageSize.height * effectiveScale,
    );
    final centerShift = _pageCenter - _pageCenter * effectiveScale;
    final minimumVisibleX = math.min(
      _minimumVisiblePageExtent,
      math.min(_viewportSize.width, scaledSize.width) / 2,
    );
    final minimumVisibleY = math.min(
      _minimumVisiblePageExtent,
      math.min(_viewportSize.height, scaledSize.height) / 2,
    );

    final minX =
        minimumVisibleX - scaledSize.width - _pageOrigin.dx - centerShift.dx;
    final maxX =
        _viewportSize.width - minimumVisibleX - _pageOrigin.dx - centerShift.dx;
    final minY =
        minimumVisibleY - scaledSize.height - _pageOrigin.dy - centerShift.dy;
    final maxY =
        _viewportSize.height -
        minimumVisibleY -
        _pageOrigin.dy -
        centerShift.dy;

    return Offset(
      pan.dx.clamp(minX, maxX).toDouble(),
      pan.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset get _pageCenter => Offset(_pageSize.width / 2, _pageSize.height / 2);

  Size _fittedPageSize(BoxConstraints constraints) {
    final availableWidth = math.max(0.0, constraints.maxWidth - _padding * 2);
    final availableHeight = math.max(0.0, constraints.maxHeight - _padding * 2);
    final scale = math.min(
      availableWidth / widget.page.width,
      availableHeight / widget.page.height,
    );

    return Size(widget.page.width * scale, widget.page.height * scale);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        _pageSize = _fittedPageSize(constraints);
        _pageOrigin = Offset(
          (constraints.maxWidth - _pageSize.width) / 2,
          (constraints.maxHeight - _pageSize.height) / 2,
        );
        _pan = _clampPan(_pan);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: _pageOrigin.dx,
                  top: _pageOrigin.dy,
                  width: _pageSize.width,
                  height: _pageSize.height,
                  child: Transform.translate(
                    offset: _pan,
                    child: Transform.scale(
                      scale: _scale,
                      alignment: Alignment.center,
                      child: widget.child,
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _ZoomControls(
                    canZoomOut: _scale > _minScale,
                    canZoomIn: _scale < _maxScale,
                    onZoomOut: () => _zoomBy(0.8),
                    onReset: _resetZoom,
                    onZoomIn: () => _zoomBy(1.25),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final bool canZoomOut;
  final bool canZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: canZoomOut ? onZoomOut : null,
              tooltip: 'Zoom out',
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton(
              onPressed: onReset,
              tooltip: 'Reset zoom',
              icon: const Icon(Icons.center_focus_strong),
            ),
            IconButton(
              onPressed: canZoomIn ? onZoomIn : null,
              tooltip: 'Zoom in',
              icon: const Icon(Icons.zoom_in),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageNavigator extends StatelessWidget {
  const _PageNavigator({
    required this.pageIds,
    required this.pagesById,
    required this.currentPageId,
    required this.bookmarkedPageIds,
    required this.onSelectPage,
    required this.onAddPage,
    required this.onInsertPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
    required this.onMovePage,
  });

  final List<String> pageIds;
  final Map<String, NotePage> pagesById;
  final String currentPageId;
  final Set<String> bookmarkedPageIds;
  final ValueChanged<String> onSelectPage;
  final VoidCallback onAddPage;
  final ValueChanged<int> onInsertPage;
  final ValueChanged<String> onDuplicatePage;
  final ValueChanged<String> onDeletePage;
  final void Function(String pageId, int newIndex) onMovePage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 1,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 118,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final (index, pageId) in pageIds.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PageThumbnailButton(
                    pageId: pageId,
                    pageNumber: index + 1,
                    page: pagesById[pageId],
                    isSelected: pageId == currentPageId,
                    isBookmarked: bookmarkedPageIds.contains(pageId),
                    canDelete: pageIds.length > 1,
                    canMoveLeft: index > 0,
                    canMoveRight: index < pageIds.length - 1,
                    onPressed: () => onSelectPage(pageId),
                    onInsertBefore: () => onInsertPage(index),
                    onInsertAfter: () => onInsertPage(index + 1),
                    onDuplicate: () => onDuplicatePage(pageId),
                    onDelete: () => onDeletePage(pageId),
                    onMoveLeft: () => onMovePage(pageId, index - 1),
                    onMoveRight: () => onMovePage(pageId, index + 1),
                  ),
                ),
              Center(
                child: IconButton.filledTonal(
                  onPressed: onAddPage,
                  tooltip: 'Add page',
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageThumbnailButton extends StatelessWidget {
  const _PageThumbnailButton({
    required this.pageId,
    required this.pageNumber,
    required this.page,
    required this.isSelected,
    required this.isBookmarked,
    required this.canDelete,
    required this.canMoveLeft,
    required this.canMoveRight,
    required this.onPressed,
    required this.onInsertBefore,
    required this.onInsertAfter,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  final String pageId;
  final int pageNumber;
  final NotePage? page;
  final bool isSelected;
  final bool isBookmarked;
  final bool canDelete;
  final bool canMoveLeft;
  final bool canMoveRight;
  final VoidCallback onPressed;
  final VoidCallback onInsertBefore;
  final VoidCallback onInsertAfter;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;

  void _handleAction(_PageAction action) {
    switch (action) {
      case _PageAction.insertBefore:
        onInsertBefore();
        break;
      case _PageAction.insertAfter:
        onInsertAfter();
        break;
      case _PageAction.duplicate:
        onDuplicate();
        break;
      case _PageAction.delete:
        onDelete();
        break;
      case _PageAction.moveLeft:
        onMoveLeft();
        break;
      case _PageAction.moveRight:
        onMoveRight();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isSelected
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return Tooltip(
      message: 'Page $pageNumber',
      child: InkWell(
        key: ValueKey('page-thumbnail-$pageId'),
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 58,
                    height: 78,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: borderColor,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x171E2526),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: page == null
                          ? Icon(
                              Icons.description_outlined,
                              color: colorScheme.outline,
                              size: 22,
                            )
                          : _PageThumbnailPreview(page: page!),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: _PageActionMenu(
                      pageNumber: pageNumber,
                      canDelete: canDelete,
                      canMoveLeft: canMoveLeft,
                      canMoveRight: canMoveRight,
                      onSelected: _handleAction,
                    ),
                  ),
                  if (isBookmarked)
                    Positioned(
                      left: 3,
                      top: 3,
                      child: Icon(
                        Icons.bookmark,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$pageNumber',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PageAction {
  insertBefore,
  insertAfter,
  duplicate,
  delete,
  moveLeft,
  moveRight,
}

class _PageActionMenu extends StatelessWidget {
  const _PageActionMenu({
    required this.pageNumber,
    required this.canDelete,
    required this.canMoveLeft,
    required this.canMoveRight,
    required this.onSelected,
  });

  final int pageNumber;
  final bool canDelete;
  final bool canMoveLeft;
  final bool canMoveRight;
  final ValueChanged<_PageAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_PageAction>(
      tooltip: 'Page $pageNumber actions',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          _pageActionItem(
            value: _PageAction.insertBefore,
            icon: Icons.add,
            label: 'Insert page before',
          ),
          _pageActionItem(
            value: _PageAction.insertAfter,
            icon: Icons.add,
            label: 'Insert page after',
          ),
          _pageActionItem(
            value: _PageAction.duplicate,
            icon: Icons.copy,
            label: 'Duplicate page',
          ),
          _pageActionItem(
            value: _PageAction.delete,
            icon: Icons.delete_outline,
            label: 'Delete page',
            enabled: canDelete,
          ),
          _pageActionItem(
            value: _PageAction.moveLeft,
            icon: Icons.arrow_back,
            label: 'Move page left',
            enabled: canMoveLeft,
          ),
          _pageActionItem(
            value: _PageAction.moveRight,
            icon: Icons.arrow_forward,
            label: 'Move page right',
            enabled: canMoveRight,
          ),
        ];
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: const SizedBox.square(
          dimension: 24,
          child: Icon(Icons.more_horiz, size: 18),
        ),
      ),
    );
  }
}

PopupMenuItem<_PageAction> _pageActionItem({
  required _PageAction value,
  required IconData icon,
  required String label,
  bool enabled = true,
}) {
  return PopupMenuItem<_PageAction>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

class _PageThumbnailPreview extends StatelessWidget {
  const _PageThumbnailPreview({required this.page});

  final NotePage page;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (page.pdfBackground case final background?)
          PdfPageBackgroundView(
            key: ValueKey(
              'page-thumbnail-background-${background.filePath}-${background.pageNumber}',
            ),
            background: background,
          )
        else
          ColoredBox(color: colorScheme.surface),
        CustomPaint(painter: _PageThumbnailPainter(page: page)),
      ],
    );
  }
}

class _PageThumbnailPainter extends CustomPainter {
  const _PageThumbnailPainter({required this.page});

  final NotePage page;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / page.width, size.height / page.height);
    final scaledPageSize = Size(page.width * scale, page.height * scale);
    final offset = Offset(
      (size.width - scaledPageSize.width) / 2,
      (size.height - scaledPageSize.height) / 2,
    );

    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);

    for (final noteImage in page.images) {
      final rect = Rect.fromLTWH(
        noteImage.position.dx,
        noteImage.position.dy,
        noteImage.width,
        noteImage.height,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      final fillPaint = Paint()
        ..color = const Color(0xFFE7F0F0)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = const Color(0x802F6F73)
        ..strokeWidth = math.max(1.0, 1.2 / scale)
        ..style = PaintingStyle.stroke;
      final linePaint = Paint()
        ..color = const Color(0x662F6F73)
        ..strokeWidth = math.max(1.0, 1 / scale)
        ..style = PaintingStyle.stroke;

      canvas
        ..drawRRect(rrect, fillPaint)
        ..drawLine(rect.bottomLeft, rect.topRight, linePaint)
        ..drawLine(
          rect.bottomLeft + Offset(rect.width * 0.35, 0),
          rect.topRight + Offset(0, rect.height * 0.35),
          linePaint,
        )
        ..drawRRect(rrect, borderPaint);
    }

    for (final stroke in page.strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = math.max(stroke.width, 1.4 / scale)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = stroke.isHighlighter
            ? BlendMode.multiply
            : BlendMode.srcOver
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first.offset,
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }

      canvas.drawPath(StrokeGeometry.buildSmoothPath(stroke.points), paint);
    }

    for (final shape in page.shapes) {
      paintNoteShape(canvas, shape, minimumStrokeWidth: 1.4 / scale);
    }

    for (final textBox in page.textBoxes) {
      if (textBox.text.trim().isEmpty) {
        continue;
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: textBox.text,
          style: noteTextBoxTextStyle(textBox),
        ),
        maxLines: 3,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textBox.width);

      textPainter.paint(canvas, textBox.position);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PageThumbnailPainter oldDelegate) {
    return oldDelegate.page != page;
  }
}
