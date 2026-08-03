import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:inknest_notes/export/notebook_pdf_exporter.dart';
import 'package:inknest_notes/export/pdf_page_selection.dart';
import 'package:inknest_notes/features/editor/canvas/drawing_canvas.dart';
import 'package:inknest_notes/features/editor/canvas/page_viewport_model.dart';
import 'package:inknest_notes/features/editor/canvas/pdf_page_background.dart';
import 'package:inknest_notes/features/editor/images/image_layer.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_geometry.dart';
import 'package:inknest_notes/features/editor/lasso/lasso_selection_layer.dart';
import 'package:inknest_notes/features/editor/recognition/font_glyph_stroke_generator.dart';
import 'package:inknest_notes/features/editor/recognition/ink_beautify_fonts.dart';
import 'package:inknest_notes/features/editor/recognition/ink_recognition_image_renderer.dart';
import 'package:inknest_notes/features/editor/recognition/text_recognition_provider.dart';
import 'package:inknest_notes/features/editor/search/notebook_text_search_service.dart';
import 'package:inknest_notes/features/editor/search/notebook_text_search_sheet.dart';
import 'package:inknest_notes/features/editor/search/pdf_search_highlight_layer.dart';
import 'package:inknest_notes/features/editor/shapes/shape_layer.dart';
import 'package:inknest_notes/features/editor/templates/page_template_layer.dart';
import 'package:inknest_notes/features/editor/templates/page_template_sheet.dart';
import 'package:inknest_notes/features/editor/text/note_text_box_styles.dart';
import 'package:inknest_notes/features/editor/text/text_box_layer.dart';
import 'package:inknest_notes/features/editor/theme/editor_chrome.dart';
import 'package:inknest_notes/features/editor/theme/editor_workspace_tokens.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_page_template.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/note_text_box.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_audio_recording.dart';
import 'package:inknest_notes/models/pdf_outline_entry.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_geometry.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.notebook,
    required this.notebookRepository,
    this.textRecognitionProvider = const AppleVisionTextRecognitionProvider(),
    this.pdfFilePicker,
  });

  final Notebook notebook;
  final NotebookRepository notebookRepository;
  final TextRecognitionProvider textRecognitionProvider;
  final Future<List<File>> Function()? pdfFilePicker;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final InkRecognitionImageRenderer _inkRecognitionImageRenderer =
      const InkRecognitionImageRenderer();
  final FontGlyphStrokeGenerator _fontGlyphStrokeGenerator =
      const FontGlyphStrokeGenerator();
  final NotebookTextSearchService _notebookTextSearchService =
      NotebookTextSearchService();
  final GlobalKey<_ZoomablePageViewportState> _viewportKey =
      GlobalKey<_ZoomablePageViewportState>();
  final List<Stroke> _redoStack = [];
  final Set<String> _selectedStrokeIds = {};
  final Map<String, NotePage> _pagesById = {};
  final Map<String, PageViewportSessionState> _viewportStatesByPageId = {};
  DrawingTool _tool = const DrawingTool(width: 3);
  late Notebook _notebook;
  late String _currentPageId;
  bool _isPageRailOpen = false;
  bool _isExporting = false;
  bool _isImportingPdfs = false;
  bool _fingerPanEnabled = false;
  bool? _fingerPanBeforeLasso;
  bool _fingerWritingAssistEnabled = true;
  String? _activeTextBoxId;
  String? _activeImageId;
  bool _isAudioBusy = false;
  NotebookAudioRecording? _activeAudioRecording;
  DateTime? _activeAudioRecordingStartedAt;
  Duration _activeAudioElapsed = Duration.zero;
  Timer? _audioTimer;
  AudioPlayer? _audioPlayer;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<PlayerState>? _audioPlayerStateSubscription;
  NotebookAudioRecording? _audioPlaybackRecording;
  Duration _audioPlaybackPosition = Duration.zero;
  Duration _audioPlaybackDuration = Duration.zero;
  bool _isAudioPlaybackLoading = false;
  bool _isAudioPlaying = false;
  bool _followAudioPlayback = true;
  int _audioPlaybackGeneration = 0;
  String _notebookSearchQuery = '';
  NotebookTextSearchResult? _activeNotebookSearchResult;
  NotePage? _page;

  bool get _isCurrentPageWriteProtected =>
      _page?.isCoordinateSpaceWriteProtected ?? false;

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
    _currentPageId = _notebook.pageIds.first;
    _loadPage();
    unawaited(_loadPageThumbnails());
  }

  @override
  void dispose() {
    _audioTimer?.cancel();
    final positionSubscription = _audioPositionSubscription;
    final playerStateSubscription = _audioPlayerStateSubscription;
    if (positionSubscription != null) {
      unawaited(positionSubscription.cancel());
    }
    if (playerStateSubscription != null) {
      unawaited(playerStateSubscription.cancel());
    }
    unawaited(_disposeAudioRecorder());
    unawaited(_disposeAudioPlayer());
    super.dispose();
  }

  Future<void> _disposeAudioRecorder() async {
    try {
      if (_activeAudioRecording != null) {
        await _audioRecorder.cancel();
      }
      await _audioRecorder.dispose();
    } catch (_) {
      // Widget tests do not register the recorder plugin.
    }
  }

  Future<void> _disposeAudioPlayer() async {
    final player = _audioPlayer;
    if (player == null) {
      return;
    }

    try {
      await player.dispose();
    } catch (_) {
      // Widget tests do not register the player plugin.
    }
  }

  AudioPlayer _ensureAudioPlayer() {
    final existingPlayer = _audioPlayer;
    if (existingPlayer != null) {
      return existingPlayer;
    }

    final player = AudioPlayer();
    _audioPlayer = player;
    _audioPositionSubscription = player.positionStream.listen(
      _handleAudioPlaybackPosition,
    );
    _audioPlayerStateSubscription = player.playerStateStream.listen(
      _handleAudioPlayerState,
    );
    return player;
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
      _selectedStrokeIds.clear();
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

    final recording = _activeAudioRecording;
    final linkedStroke = recording == null
        ? stroke
        : stroke.copyWith(audioRecordingId: recording.id);
    final updatedPage = page.copyWith(strokes: [...page.strokes, linkedStroke]);

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

  Future<void> _importPdfsIntoNotebook() async {
    if (_isImportingPdfs) {
      return;
    }

    final sourceFiles = await _pickPdfFiles();
    if (!mounted || sourceFiles.isEmpty) {
      return;
    }

    setState(() {
      _isImportingPdfs = true;
    });
    try {
      await _savePage();
      final previousPageIds = _notebook.pageIds.toSet();
      final updatedNotebook = await widget.notebookRepository
          .importPdfsIntoNotebook(_notebook, sourceFiles);
      final importedPageIds = [
        for (final pageId in updatedNotebook.pageIds)
          if (!previousPageIds.contains(pageId)) pageId,
      ];
      if (!mounted) {
        return;
      }
      if (importedPageIds.isEmpty) {
        _showSnackBar('No PDF pages were imported');
        return;
      }

      setState(() {
        _notebook = updatedNotebook;
        _currentPageId = importedPageIds.first;
        _page = null;
        _activeTextBoxId = null;
        _activeImageId = null;
        _selectedStrokeIds.clear();
        _redoStack.clear();
      });
      await _loadPage();
      unawaited(_loadPageThumbnails());
      if (mounted) {
        _showSnackBar(
          'Imported ${sourceFiles.length} PDFs · '
          '${importedPageIds.length} pages',
        );
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('Unable to import the selected PDFs');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImportingPdfs = false;
        });
      }
    }
  }

  Future<List<File>> _pickPdfFiles() async {
    final picker = widget.pdfFilePicker;
    if (picker != null) {
      return picker();
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
    );
    return [
      for (final file in result?.files ?? const <PlatformFile>[])
        if (file.path case final path?) File(path),
    ];
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

  void _handleAudioPlaybackPosition(Duration position) {
    final recording = _audioPlaybackRecording;
    if (!mounted || recording == null) {
      return;
    }

    final clampedPosition = _clampAudioPlaybackPosition(position);
    final playbackPageId = _pageIdForAudioPlayback(recording, clampedPosition);
    final playbackPage = playbackPageId == null
        ? null
        : _pagesById[playbackPageId];

    setState(() {
      _audioPlaybackPosition = clampedPosition;
      if (_followAudioPlayback &&
          playbackPageId != null &&
          playbackPage != null &&
          playbackPageId != _currentPageId) {
        _currentPageId = playbackPageId;
        _page = playbackPage;
        _redoStack.clear();
        _activeTextBoxId = null;
        _activeImageId = null;
      }
    });
  }

  void _handleAudioPlayerState(PlayerState state) {
    if (!mounted || _audioPlaybackRecording == null) {
      return;
    }

    final isCompleted = state.processingState == ProcessingState.completed;
    setState(() {
      _isAudioPlaying = state.playing && !isCompleted;
      if (isCompleted) {
        _audioPlaybackPosition = _audioPlaybackDuration;
      }
    });
  }

  Duration _clampAudioPlaybackPosition(Duration position) {
    final maxMilliseconds = _audioPlaybackDuration.inMilliseconds;
    if (maxMilliseconds <= 0) {
      return Duration.zero;
    }

    return Duration(
      milliseconds: position.inMilliseconds.clamp(0, maxMilliseconds),
    );
  }

  String? _pageIdForAudioPlayback(
    NotebookAudioRecording recording,
    Duration position,
  ) {
    final cutoff = recording.createdAt.add(position);
    var pageId = recording.pageId;
    DateTime? latestStrokeStart;

    for (final candidatePageId in _notebook.pageIds) {
      final page = _pagesById[candidatePageId];
      if (page == null) {
        continue;
      }

      for (final stroke in page.strokes) {
        if (stroke.audioRecordingId != recording.id || stroke.points.isEmpty) {
          continue;
        }

        final strokeStartedAt = stroke.points.first.time;
        if (strokeStartedAt.isAfter(cutoff) ||
            (latestStrokeStart != null &&
                !strokeStartedAt.isAfter(latestStrokeStart))) {
          continue;
        }

        latestStrokeStart = strokeStartedAt;
        pageId = candidatePageId;
      }
    }

    return pageId;
  }

  Future<void> _playAudioRecording(NotebookAudioRecording recording) async {
    if (_activeAudioRecording != null || _isAudioPlaybackLoading) {
      _showSnackBar('Stop the current recording before playback');
      return;
    }

    final audioFile = File(recording.filePath);
    if (!await audioFile.exists()) {
      if (mounted) {
        _showSnackBar('Audio file is missing');
      }
      return;
    }

    final playbackGeneration = ++_audioPlaybackGeneration;
    setState(() {
      _isAudioPlaybackLoading = true;
      _audioPlaybackRecording = recording;
      _audioPlaybackPosition = Duration.zero;
      _audioPlaybackDuration = recording.duration;
      _isAudioPlaying = false;
      _followAudioPlayback = true;
    });

    try {
      final player = _ensureAudioPlayer();
      await player.stop();
      if (!_isCurrentAudioPlayback(playbackGeneration, recording.id)) {
        return;
      }

      final pageId = recording.pageId;
      if (pageId != null &&
          pageId != _currentPageId &&
          _notebook.pageIds.contains(pageId)) {
        await _selectPage(pageId);
      }
      if (!_isCurrentAudioPlayback(playbackGeneration, recording.id)) {
        return;
      }

      final loadedDuration = await player.setFilePath(recording.filePath);
      if (!_isCurrentAudioPlayback(playbackGeneration, recording.id)) {
        return;
      }

      setState(() {
        _audioPlaybackDuration = loadedDuration ?? recording.duration;
        _audioPlaybackPosition = Duration.zero;
      });
      _startLoadedAudioPlayback();
    } catch (error) {
      if (!_isCurrentAudioPlayback(playbackGeneration, recording.id)) {
        return;
      }

      setState(() {
        _audioPlaybackRecording = null;
        _audioPlaybackPosition = Duration.zero;
        _audioPlaybackDuration = Duration.zero;
        _isAudioPlaying = false;
      });
      _showSnackBar('Audio playback failed: $error');
    } finally {
      if (_isCurrentAudioPlayback(playbackGeneration, recording.id)) {
        setState(() {
          _isAudioPlaybackLoading = false;
        });
      }
    }
  }

  bool _isCurrentAudioPlayback(int generation, String recordingId) {
    return mounted &&
        generation == _audioPlaybackGeneration &&
        _audioPlaybackRecording?.id == recordingId;
  }

  void _startLoadedAudioPlayback() {
    final player = _audioPlayer;
    if (player == null) {
      return;
    }

    unawaited(
      player.play().catchError((Object error) {
        if (mounted) {
          _showSnackBar('Audio playback failed: $error');
        }
      }),
    );
  }

  Future<void> _toggleAudioPlayback() async {
    final player = _audioPlayer;
    if (player == null ||
        _audioPlaybackRecording == null ||
        _isAudioPlaybackLoading) {
      return;
    }

    if (_isAudioPlaying) {
      await player.pause();
      return;
    }

    if (_audioPlaybackDuration > Duration.zero &&
        _audioPlaybackPosition >= _audioPlaybackDuration) {
      await player.seek(Duration.zero);
    }
    _startLoadedAudioPlayback();
  }

  Future<void> _seekAudioPlayback(Duration position) async {
    final player = _audioPlayer;
    if (player == null ||
        _audioPlaybackRecording == null ||
        _isAudioPlaybackLoading) {
      return;
    }

    final clampedPosition = _clampAudioPlaybackPosition(position);
    _handleAudioPlaybackPosition(clampedPosition);
    await player.seek(clampedPosition);
  }

  void _toggleAudioPlaybackFollow() {
    final shouldFollow = !_followAudioPlayback;
    setState(() {
      _followAudioPlayback = shouldFollow;
    });

    if (shouldFollow) {
      _handleAudioPlaybackPosition(_audioPlaybackPosition);
    }
  }

  Future<void> _closeAudioPlayback() async {
    _audioPlaybackGeneration++;
    final player = _audioPlayer;
    try {
      await player?.stop();
    } catch (_) {
      // The player may not be registered in widget tests.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _audioPlaybackRecording = null;
      _audioPlaybackPosition = Duration.zero;
      _audioPlaybackDuration = Duration.zero;
      _isAudioPlaying = false;
      _isAudioPlaybackLoading = false;
      _followAudioPlayback = true;
    });
  }

  Future<void> _toggleAudioRecording() async {
    if (_isAudioBusy) {
      return;
    }

    if (_activeAudioRecording == null) {
      await _startAudioRecording();
    } else {
      await _stopAudioRecording();
    }
  }

  Future<void> _startAudioRecording() async {
    setState(() {
      _isAudioBusy = true;
    });

    try {
      if (_audioPlaybackRecording != null) {
        await _closeAudioPlayback();
      }

      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          _showSnackBar('Microphone permission is required');
        }
        return;
      }

      final recording = await widget.notebookRepository.prepareAudioRecording(
        _notebook,
        pageId: _currentPageId,
      );
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: recording.filePath,
      );
      final startedAt = DateTime.now();

      if (!mounted) {
        return;
      }

      _audioTimer?.cancel();
      _audioTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final recordingStartedAt = _activeAudioRecordingStartedAt;
        if (recordingStartedAt == null || !mounted) {
          return;
        }

        setState(() {
          _activeAudioElapsed = DateTime.now().difference(recordingStartedAt);
        });
      });

      setState(() {
        _activeAudioRecording = recording.copyWith(createdAt: startedAt);
        _activeAudioRecordingStartedAt = startedAt;
        _activeAudioElapsed = Duration.zero;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showSnackBar('Audio recording failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isAudioBusy = false;
        });
      }
    }
  }

  Future<void> _stopAudioRecording() async {
    final recording = _activeAudioRecording;
    final startedAt = _activeAudioRecordingStartedAt;
    if (recording == null || startedAt == null) {
      return;
    }

    setState(() {
      _isAudioBusy = true;
    });

    try {
      final recordedPath = await _audioRecorder.stop();
      final elapsed = DateTime.now().difference(startedAt);
      final savedRecording = recording.copyWith(
        duration: elapsed,
        resolvedFilePath: recordedPath ?? recording.filePath,
      );
      final updatedNotebook = await widget.notebookRepository
          .saveAudioRecording(_notebook, savedRecording);

      if (!mounted) {
        return;
      }

      _audioTimer?.cancel();
      setState(() {
        _notebook = updatedNotebook;
        _activeAudioRecording = null;
        _activeAudioRecordingStartedAt = null;
        _activeAudioElapsed = Duration.zero;
      });
      _showSnackBar('Audio recording saved');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showSnackBar('Stop recording failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isAudioBusy = false;
        });
      }
    }
  }

  void _showAudioRecordingsSheet() {
    EditorChrome.showSheet<void>(
      context: context,
      builder: (sheetContext) => _AudioRecordingsSheet(
        recordings: _notebook.audioRecordings,
        activeElapsed: _activeAudioRecording == null
            ? null
            : _activeAudioElapsed,
        selectedRecordingId: _audioPlaybackRecording?.id,
        pageIds: _notebook.pageIds,
        canPlay: _activeAudioRecording == null && !_isAudioPlaybackLoading,
        onPlay: (recording) {
          Navigator.of(sheetContext).pop();
          unawaited(_playAudioRecording(recording));
        },
      ),
    );
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
      _selectedStrokeIds.clear();
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
      _selectedStrokeIds.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  void _setTool(DrawingTool tool) {
    setState(() {
      final wasUsingLasso = _tool.type == ToolType.lasso;
      _tool = tool;
      if (tool.type == ToolType.lasso) {
        if (!wasUsingLasso) {
          _fingerPanBeforeLasso = _fingerPanEnabled;
        }
        _fingerPanEnabled = false;
      } else {
        final previousMode = _fingerPanBeforeLasso;
        if (wasUsingLasso && previousMode != null) {
          _fingerPanEnabled = previousMode;
        }
        _fingerPanBeforeLasso = null;
        _selectedStrokeIds.clear();
      }
    });
  }

  void _setFingerPanEnabled(bool value) {
    if (value && _tool.type == ToolType.lasso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish lasso editing before finger pan')),
      );
      return;
    }
    setState(() {
      _fingerPanEnabled = value;
    });
  }

  void _setFingerWritingAssistEnabled(bool value) {
    setState(() {
      _fingerWritingAssistEnabled = value;
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

  void _selectStrokesWithLasso(List<Offset> polygon) {
    final page = _page;
    if (page == null) {
      return;
    }

    final selectedStrokeIds = LassoGeometry.selectStrokeIds(
      page.strokes,
      polygon,
    );
    setState(() {
      _selectedStrokeIds
        ..clear()
        ..addAll(selectedStrokeIds);
    });
    if (selectedStrokeIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No strokes selected')));
    }
  }

  void _previewSelectedStrokes(List<Stroke> strokes) {
    _replaceSelectedStrokes(strokes, persist: false);
  }

  void _commitSelectedStrokes(List<Stroke> strokes) {
    _replaceSelectedStrokes(strokes, persist: true);
  }

  void _replaceSelectedStrokes(List<Stroke> strokes, {required bool persist}) {
    final page = _page;
    if (page == null || strokes.isEmpty) {
      return;
    }

    final strokesById = {for (final stroke in strokes) stroke.id: stroke};
    final updatedPage = page.copyWith(
      strokes: [
        for (final stroke in page.strokes) strokesById[stroke.id] ?? stroke,
      ],
    );
    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      if (persist) {
        _redoStack.clear();
      }
    });
    if (persist) {
      unawaited(_savePage(updatedPage));
    }
  }

  void _recolorSelectedStrokes(Color color) {
    final page = _page;
    if (page == null) {
      return;
    }
    final selectedStrokes = _selectedStrokesForPage(page);
    if (selectedStrokes.isEmpty) {
      return;
    }
    _commitSelectedStrokes([
      for (final stroke in selectedStrokes) stroke.copyWith(color: color),
    ]);
  }

  void _deleteSelectedStrokes() {
    final page = _page;
    if (page == null || _selectedStrokeIds.isEmpty) {
      return;
    }
    final updatedPage = page.copyWith(
      strokes: [
        for (final stroke in page.strokes)
          if (!_selectedStrokeIds.contains(stroke.id)) stroke,
      ],
    );
    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _selectedStrokeIds.clear();
      _redoStack.clear();
    });
    unawaited(_savePage(updatedPage));
  }

  void _clearLassoSelection() {
    if (_selectedStrokeIds.isEmpty) {
      return;
    }
    setState(_selectedStrokeIds.clear);
  }

  List<Stroke> _selectedStrokesForPage(NotePage page) {
    return [
      for (final stroke in page.strokes)
        if (_selectedStrokeIds.contains(stroke.id)) stroke,
    ];
  }

  Future<void> _runSmartInkForSelectedStrokes() async {
    final page = _page;
    if (page == null) {
      return;
    }
    await _runSmartInkForStrokes(_selectedStrokesForPage(page));
  }

  Future<void> _runSmartInkForStrokes(List<Stroke> selectedStrokes) async {
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
        recognition: _recognizeSelectedInk(selectedStrokes),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final page = _page;
    if (page == null) {
      return;
    }
    final text = result.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Beautify text is empty')));
      return;
    }

    final selectedStrokeIds = selectedStrokes
        .map((stroke) => stroke.id)
        .toSet();
    final selectedBounds = _boundsForStrokes(selectedStrokes).inflate(8);
    final averageWidth =
        selectedStrokes
            .map((stroke) => stroke.width)
            .fold<double>(0, (sum, width) => sum + width) /
        selectedStrokes.length;

    List<Stroke> beautifiedStrokes = const [];
    var loadingShown = false;
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Redrawing as ink...'),
              ),
            ),
          );
        },
      );
      loadingShown = true;
      beautifiedStrokes = await _fontGlyphStrokeGenerator.generate(
        text: text,
        font: result.font,
        targetBounds: selectedBounds,
        color: selectedStrokes.first.color,
        strokeWidth: averageWidth,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Beautify failed. Your ink is unchanged.'),
          ),
        );
      }
      return;
    } finally {
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) {
      return;
    }
    if (beautifiedStrokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not build ink from that text. Try again.'),
        ),
      );
      return;
    }

    final remainingStrokes = result.replaceSelectedInk
        ? [
            for (final stroke in page.strokes)
              if (!selectedStrokeIds.contains(stroke.id)) stroke,
          ]
        : page.strokes;
    final updatedPage = page.copyWith(
      strokes: [...remainingStrokes, ...beautifiedStrokes],
    );

    setState(() {
      _page = updatedPage;
      _pagesById[updatedPage.id] = updatedPage;
      _selectedStrokeIds
        ..clear()
        ..addAll(beautifiedStrokes.map((stroke) => stroke.id));
      _redoStack.clear();
    });

    unawaited(_savePage(updatedPage));
  }

  Future<TextRecognitionResult> _recognizeSelectedInk(
    List<Stroke> selectedStrokes,
  ) async {
    final pngBytes = await _inkRecognitionImageRenderer.render(selectedStrokes);
    return widget.textRecognitionProvider.recognize(
      TextRecognitionRequest(
        pngBytes: pngBytes,
        recognitionLanguages: const ['zh-Hans', 'en-US'],
      ),
    );
  }

  Rect _boundsForStrokes(List<Stroke> strokes) {
    return LassoGeometry.boundsForStrokes(strokes)!;
  }

  Future<void> _savePage([NotePage? page]) async {
    final pageToSave = page ?? _page;
    if (pageToSave == null || pageToSave.isCoordinateSpaceWriteProtected) {
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

  void _showPagesForWidth(double width) {
    if (width >= 1100) {
      setState(() {
        _isPageRailOpen = !_isPageRailOpen;
      });
      return;
    }
    _showNavigationSheet(_EditorNavigationPanel.pages);
  }

  void _showNavigationSheet(_EditorNavigationPanel panel) {
    Future<void> runNavigatorAction(
      BuildContext navigatorContext,
      Future<void> Function() action, {
      required bool dismissAfterAction,
      VoidCallback? refresh,
    }) async {
      if (dismissAfterAction) {
        Navigator.of(navigatorContext).pop();
      }
      await action();
      if (!dismissAfterAction && navigatorContext.mounted) {
        refresh?.call();
      }
    }

    Widget buildNavigator(
      BuildContext navigatorContext, {
      bool fill = false,
      required bool dismissAfterAction,
      VoidCallback? refresh,
    }) {
      void run(Future<void> Function() action) {
        unawaited(
          runNavigatorAction(
            navigatorContext,
            action,
            dismissAfterAction: dismissAfterAction,
            refresh: refresh,
          ),
        );
      }

      void selectPage(String pageId) {
        run(() => _selectPageManually(pageId));
      }

      return switch (panel) {
        _EditorNavigationPanel.pages => _PagesNavigationPanel(
          fillAvailableHeight: fill,
          notebook: _notebook,
          pagesById: _pagesById,
          currentPageId: _currentPageId,
          onSelectPage: selectPage,
          onAddPage: () => run(_chooseTemplateAndInsertPageAfterCurrent),
          onRotateCurrentPage: () =>
              run(() => _rotatePageClockwise(_currentPageId)),
          onInsertPage: (index) =>
              run(() => _chooseTemplateAndInsertPage(index)),
          onDuplicatePage: (pageId) => run(() => _duplicatePage(pageId)),
          onDeletePage: (pageId) => run(() => _deletePage(pageId)),
          onMovePage: (pageId, newIndex) =>
              run(() => _movePage(pageId, newIndex)),
          onRotatePage: (pageId) => run(() => _rotatePageClockwise(pageId)),
        ),
        _EditorNavigationPanel.outline => _OutlineNavigationPanel(
          fillAvailableHeight: fill,
          notebook: _notebook,
          currentPageId: _currentPageId,
          onSelectPage: selectPage,
        ),
        _EditorNavigationPanel.bookmarks => _BookmarksNavigationPanel(
          fillAvailableHeight: fill,
          notebook: _notebook,
          currentPageId: _currentPageId,
          onSelectPage: selectPage,
          onToggleCurrentPage: () => run(
            () => _setCurrentPageBookmarked(
              !_notebook.bookmarkedPageIds.contains(_currentPageId),
            ),
          ),
        ),
      };
    }

    final width = MediaQuery.sizeOf(context).width;
    if (width >= 720) {
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss ${panel.label} panel',
        barrierColor: Colors.black38,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (dialogContext, _, _) {
          return Align(
            alignment: Alignment.centerLeft,
            child: SafeArea(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 16,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: math.min(380, width * 0.82),
                  height: double.infinity,
                  child: StatefulBuilder(
                    builder: (navigatorContext, setNavigatorState) {
                      return buildNavigator(
                        navigatorContext,
                        fill: true,
                        dismissAfterAction: false,
                        refresh: () => setNavigatorState(() {}),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
      return;
    }

    EditorChrome.showSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return buildNavigator(sheetContext, dismissAfterAction: true);
      },
    );
  }

  Future<void> _handleEditorMenuAction(_EditorMenuAction action) async {
    final page = _page;
    switch (action) {
      case _EditorMenuAction.audioLibrary:
        _showAudioRecordingsSheet();
        break;
      case _EditorMenuAction.toggleRecording:
        if (page != null && !_isAudioBusy) {
          await _toggleAudioRecording();
        }
        break;
      case _EditorMenuAction.importPdf:
        if (page != null &&
            !_isImportingPdfs &&
            _activeAudioRecording == null) {
          await _importPdfsIntoNotebook();
        }
        break;
      case _EditorMenuAction.exportPdf:
        if (page != null && !_isExporting) {
          await _exportPdf();
        }
        break;
      case _EditorMenuAction.fitWidth:
        _viewportKey.currentState?.fitWidth();
        break;
      case _EditorMenuAction.fitPage:
        _viewportKey.currentState?.fitPage();
        break;
    }
  }

  Future<void> _chooseTemplateAndInsertPageAfterCurrent() {
    final currentIndex = _notebook.pageIds.indexOf(_currentPageId);
    final insertionIndex = currentIndex < 0
        ? _notebook.pageIds.length
        : currentIndex + 1;
    return _chooseTemplateAndInsertPage(insertionIndex);
  }

  Future<void> _chooseTemplateAndInsertPage(int index) async {
    final template = await showPageTemplateSheet(
      context: context,
      selectedTemplate: _page?.template ?? NotePageTemplate.blank,
      title: 'Add page',
      subtitle: 'Choose a paper style for the new page',
    );
    if (!mounted || template == null) {
      return;
    }

    await _insertPage(index, template: template);
  }

  Future<void> _insertPage(
    int index, {
    required NotePageTemplate template,
  }) async {
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
    final insertedPage = _page;
    if (insertedPage != null && insertedPage.template != template) {
      final styledPage = insertedPage.copyWith(template: template);
      setState(() {
        _page = styledPage;
        _pagesById[styledPage.id] = styledPage;
      });
      await _savePage(styledPage);
    }
    unawaited(_loadPageThumbnails());
  }

  Future<void> _duplicatePage(String pageId) async {
    await _savePage();

    final previousPageIds = _notebook.pageIds.toSet();
    late final Notebook updatedNotebook;
    try {
      updatedNotebook = await widget.notebookRepository.duplicatePage(
        _notebook,
        pageId,
      );
    } on PageCoordinateSpaceWriteException catch (error) {
      _showCoordinateSpaceWriteBlocked(error);
      return;
    }

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
          backgroundColor: EditorWorkspaceTokens.chrome,
          surfaceTintColor: Colors.transparent,
          shape: EditorChrome.shape,
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

  Future<void> _rotatePageClockwise(String pageId) async {
    await _savePage();

    late final NotePage rotatedPage;
    try {
      rotatedPage = await widget.notebookRepository.rotatePageClockwise(
        _notebook,
        pageId,
      );
    } on PageCoordinateSpaceWriteException catch (error) {
      _showCoordinateSpaceWriteBlocked(error);
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _pagesById[pageId] = rotatedPage;
      if (_currentPageId == pageId) {
        _page = rotatedPage;
      }
    });
    unawaited(_loadPageThumbnails());
  }

  void _showCoordinateSpaceWriteBlocked(
    PageCoordinateSpaceWriteException error,
  ) {
    if (!mounted) {
      return;
    }
    final message =
        error.reason ==
            PageCoordinateSpaceWriteBlockReason.unresolvedLegacyContent
        ? 'This legacy page is read-only until its coordinates are safely '
              'converted.'
        : 'This page was created with an unsupported coordinate version and '
              'is read-only.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        quality: selection.quality,
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

  Future<void> _showNotebookSearch() async {
    await _loadPageThumbnails();
    if (!mounted) {
      return;
    }

    final pages = _notebook.pageIds
        .map((pageId) => _pagesById[pageId])
        .whereType<NotePage>()
        .toList(growable: false);
    final result = await showNotebookTextSearchSheet(
      context: context,
      searchService: _notebookTextSearchService,
      pages: pages,
      initialQuery: _notebookSearchQuery,
      onQueryChanged: _handleNotebookSearchQueryChanged,
    );
    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _activeNotebookSearchResult = result;
      if (_audioPlaybackRecording != null &&
          _followAudioPlayback &&
          result.pageId != _currentPageId) {
        _followAudioPlayback = false;
      }
    });
    await _selectPage(result.pageId);
  }

  void _handleNotebookSearchQueryChanged(String query) {
    final queryChanged = query != _notebookSearchQuery;
    _notebookSearchQuery = query;
    if (queryChanged && _activeNotebookSearchResult != null && mounted) {
      setState(() {
        _activeNotebookSearchResult = null;
      });
    }
  }

  Future<void> _selectPage(String pageId) async {
    if (pageId == _currentPageId) {
      return;
    }

    setState(() {
      _currentPageId = pageId;
      _page = null;
      _redoStack.clear();
      _selectedStrokeIds.clear();
    });

    await _loadPage();
  }

  Future<void> _selectPageManually(String pageId) async {
    final shouldStopFollowingAudio =
        _audioPlaybackRecording != null &&
        _followAudioPlayback &&
        pageId != _currentPageId;
    if (shouldStopFollowingAudio || _activeNotebookSearchResult != null) {
      setState(() {
        if (shouldStopFollowingAudio) {
          _followAudioPlayback = false;
        }
        _activeNotebookSearchResult = null;
      });
    }

    await _selectPage(pageId);
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final isRecording = _activeAudioRecording != null;
    final playbackRecording = _audioPlaybackRecording;
    final playbackRecordingIndex = playbackRecording == null
        ? -1
        : _notebook.audioRecordings.indexWhere(
            (recording) => recording.id == playbackRecording.id,
          );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showRecordAction = screenWidth >= 720;
    final showExportAction = screenWidth >= 1000;
    final currentPageIndex = _notebook.pageIds.indexOf(_currentPageId);
    final currentPageNumber = math.max(1, currentPageIndex + 1);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 0,
        backgroundColor: EditorWorkspaceTokens.chrome,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Expanded(
              key: const ValueKey('editor-document-context'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _notebook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Page $currentPageNumber of ${_notebook.pageIds.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _EditorPagePager(
              currentPageNumber: currentPageNumber,
              pageCount: _notebook.pageIds.length,
              onPrevious: currentPageIndex > 0
                  ? () => unawaited(
                      _selectPageManually(
                        _notebook.pageIds[currentPageIndex - 1],
                      ),
                    )
                  : null,
              onOpenPages: () => _showPagesForWidth(screenWidth),
              onNext:
                  currentPageIndex >= 0 &&
                      currentPageIndex < _notebook.pageIds.length - 1
                  ? () => unawaited(
                      _selectPageManually(
                        _notebook.pageIds[currentPageIndex + 1],
                      ),
                    )
                  : null,
              onAddPage: page == null
                  ? null
                  : () => unawaited(_chooseTemplateAndInsertPageAfterCurrent()),
            ),
            IconButton(
              key: const ValueKey('editor-outline-button'),
              onPressed: () =>
                  _showNavigationSheet(_EditorNavigationPanel.outline),
              tooltip: 'PDF outline',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(Icons.format_list_bulleted, size: 20),
            ),
            IconButton(
              key: const ValueKey('editor-bookmarks-button'),
              onPressed: () =>
                  _showNavigationSheet(_EditorNavigationPanel.bookmarks),
              tooltip: 'Bookmarks',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: Icon(
                _notebook.bookmarkedPageIds.contains(_currentPageId)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                size: 20,
                color: _notebook.bookmarkedPageIds.contains(_currentPageId)
                    ? EditorWorkspaceTokens.primary
                    : null,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('editor-undo-button'),
            onPressed: page != null && page.strokes.isNotEmpty ? _undo : null,
            tooltip: 'Undo ink stroke',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const ValueKey('editor-redo-button'),
            onPressed: _redoStack.isNotEmpty ? _redo : null,
            tooltip: 'Redo ink stroke',
            icon: const Icon(Icons.redo),
          ),
          if (showRecordAction)
            IconButton(
              key: const ValueKey('editor-record-button'),
              onPressed: page == null || _isAudioBusy
                  ? null
                  : () => unawaited(_toggleAudioRecording()),
              tooltip: isRecording
                  ? 'Stop audio recording'
                  : 'Start audio recording',
              icon: _isAudioBusy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isRecording ? Icons.stop_circle : Icons.mic_none,
                      color: isRecording
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
            ),
          IconButton(
            onPressed: () => unawaited(_showNotebookSearch()),
            tooltip: 'Search notebook',
            icon: Icon(
              Icons.search,
              color: _activeNotebookSearchResult == null
                  ? null
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          if (showExportAction)
            IconButton(
              key: const ValueKey('editor-export-button'),
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
          _EditorOverflowMenu(
            page: page,
            isRecording: isRecording,
            isAudioBusy: _isAudioBusy,
            isImportingPdfs: _isImportingPdfs,
            isExporting: _isExporting,
            hasAudioRecordings: _notebook.audioRecordings.isNotEmpty,
            onSelected: (action) => unawaited(_handleEditorMenuAction(action)),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: IgnorePointer(
            ignoring: _isCurrentPageWriteProtected,
            child: AnimatedOpacity(
              opacity: _isCurrentPageWriteProtected ? 0.52 : 1,
              duration: const Duration(milliseconds: 160),
              child: EditorToolbar(
                tool: _tool,
                fingerPanEnabled: _fingerPanEnabled,
                fingerWritingAssistEnabled: _fingerWritingAssistEnabled,
                onToolChanged: _setTool,
                onFingerPanChanged: _setFingerPanEnabled,
                onFingerWritingAssistChanged: _setFingerWritingAssistEnabled,
                onInsertImage: () => unawaited(_insertImage()),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (isRecording)
            _AudioRecordingBanner(
              elapsed: _activeAudioElapsed,
              onStop: _isAudioBusy
                  ? null
                  : () => unawaited(_stopAudioRecording()),
            ),
          if (playbackRecording != null)
            _AudioPlaybackBar(
              title: playbackRecordingIndex < 0
                  ? 'Recording'
                  : 'Recording ${playbackRecordingIndex + 1}',
              position: _audioPlaybackPosition,
              duration: _audioPlaybackDuration,
              isPlaying: _isAudioPlaying,
              isLoading: _isAudioPlaybackLoading,
              isFollowingPlayback: _followAudioPlayback,
              onTogglePlayback: () => unawaited(_toggleAudioPlayback()),
              onSeek: (position) => unawaited(_seekAudioPlayback(position)),
              onToggleFollow: _toggleAudioPlaybackFollow,
              onClose: () => unawaited(_closeAudioPlayback()),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showPageRail =
                    constraints.maxWidth >= 1100 && _isPageRailOpen;
                return ColoredBox(
                  color: EditorWorkspaceTokens.workspace,
                  child: Row(
                    children: [
                      if (showPageRail) _buildPinnedNavigator(),
                      Expanded(
                        child: page == null
                            ? const Center(child: CircularProgressIndicator())
                            : _buildPageCanvas(page),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedNavigator() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 1,
      shape: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      child: SizedBox(
        width: 280,
        child: _PagesNavigationPanel(
          fillAvailableHeight: true,
          notebook: _notebook,
          pagesById: _pagesById,
          currentPageId: _currentPageId,
          onSelectPage: (pageId) => unawaited(_selectPageManually(pageId)),
          onAddPage: () =>
              unawaited(_chooseTemplateAndInsertPageAfterCurrent()),
          onRotateCurrentPage: () =>
              unawaited(_rotatePageClockwise(_currentPageId)),
          onInsertPage: (index) =>
              unawaited(_chooseTemplateAndInsertPage(index)),
          onDuplicatePage: (pageId) => unawaited(_duplicatePage(pageId)),
          onDeletePage: (pageId) => unawaited(_deletePage(pageId)),
          onMovePage: (pageId, newIndex) =>
              unawaited(_movePage(pageId, newIndex)),
          onRotatePage: (pageId) => unawaited(_rotatePageClockwise(pageId)),
        ),
      ),
    );
  }

  Widget _buildPageCanvas(NotePage page) {
    return Stack(
      children: [
        _ZoomablePageViewport(
          key: _viewportKey,
          page: page,
          fingerPanEnabled:
              _fingerPanEnabled || page.isCoordinateSpaceWriteProtected,
          initialSessionState: _viewportStatesByPageId[page.id],
          onSessionStateChanged: (state) {
            _viewportStatesByPageId[page.id] = state;
          },
          child: RotatedBox(
            key: ValueKey(
              'rotated-page-surface-${page.id}-${page.rotationQuarterTurns}',
            ),
            quarterTurns: page.rotationQuarterTurns,
            child: _buildPageSurface(page),
          ),
        ),
        if (page.isCoordinateSpaceWriteProtected)
          Positioned(
            top: 16,
            left: 16,
            right: 176,
            child: _CoordinateSpaceReadOnlyBanner(page: page),
          ),
        if (_tool.type == ToolType.lasso && _selectedStrokeIds.isNotEmpty)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: LassoSelectionToolbar(
                selectedStrokeCount: _selectedStrokesForPage(page).length,
                onSmartInk: () => unawaited(_runSmartInkForSelectedStrokes()),
                onColorChanged: _recolorSelectedStrokes,
                onDelete: _deleteSelectedStrokes,
                onClearSelection: _clearLassoSelection,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPageSurface(NotePage page) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorWorkspaceTokens.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EditorWorkspaceTokens.divider),
        boxShadow: const [
          BoxShadow(
            color: EditorWorkspaceTokens.paperShadow,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: IgnorePointer(
          ignoring: page.isCoordinateSpaceWriteProtected,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (page.pdfBackground == null &&
                  page.template != NotePageTemplate.blank)
                PageTemplateLayer(
                  key: ValueKey(
                    'page-template-layer-${page.id}-${page.template.name}',
                  ),
                  template: page.template,
                ),
              if (page.pdfBackground case final background?)
                PdfPageBackgroundView(
                  key: ValueKey(
                    '${background.filePath}-${background.pageNumber}',
                  ),
                  background: background,
                ),
              if (_activeNotebookSearchResult case final result?
                  when result.pageId == page.id &&
                      result.source == NotebookTextSearchSource.pdf)
                PdfSearchHighlightLayer(
                  rects: result.highlightRects,
                  referencePageSize: Size(page.width, page.height),
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
                fingerWritingAssistEnabled: _fingerWritingAssistEnabled,
                onStrokeComplete: _addStroke,
                onErase: _eraseAt,
                replayRecordingId: _audioPlaybackRecording?.id,
                replayStartedAt: _audioPlaybackRecording?.createdAt,
                replayPosition: _audioPlaybackRecording == null
                    ? null
                    : _audioPlaybackPosition,
              ),
              ShapeLayer(
                page: page,
                tool: _tool,
                fingerPanEnabled: _fingerPanEnabled,
                onShapeComplete: _tool.type == ToolType.shape
                    ? _addShape
                    : null,
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
                highlightedTextBoxId: _searchHighlightedTextBoxId(page),
                onCreateTextBox: _tool.type == ToolType.text
                    ? _addTextBoxAt
                    : null,
                onTextBoxChanged: _updateTextBox,
                onTextBoxDeleted: _deleteTextBox,
              ),
              if (_tool.type == ToolType.lasso)
                LassoSelectionLayer(
                  key: ValueKey('lasso-selection-${page.id}'),
                  pageStrokes: page.strokes,
                  selectedStrokes: _selectedStrokesForPage(page),
                  onSelectionComplete: _selectStrokesWithLasso,
                  onStrokesPreviewChanged: _previewSelectedStrokes,
                  onStrokesChanged: _commitSelectedStrokes,
                  onClearSelection: _clearLassoSelection,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _searchHighlightedTextBoxId(NotePage page) {
    final result = _activeNotebookSearchResult;
    if (result == null ||
        result.pageId != page.id ||
        result.source != NotebookTextSearchSource.textBox) {
      return null;
    }
    return result.textBoxId;
  }
}

class _CoordinateSpaceReadOnlyBanner extends StatelessWidget {
  const _CoordinateSpaceReadOnlyBanner({required this.page});

  final NotePage page;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLegacy =
        page.coordinateSpaceStatus == NotePageCoordinateSpaceStatus.legacy;
    return Material(
      key: const ValueKey('coordinate-space-read-only-banner'),
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.96),
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 20,
                color: colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isLegacy
                      ? 'Legacy page is read-only until its coordinates are '
                            'safely converted.'
                      : 'This page uses an unsupported coordinate version and '
                            'is open read-only.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _EditorNavigationPanel {
  pages('Pages'),
  outline('Outline'),
  bookmarks('Bookmarks');

  const _EditorNavigationPanel(this.label);

  final String label;
}

class _EditorPagePager extends StatelessWidget {
  const _EditorPagePager({
    required this.currentPageNumber,
    required this.pageCount,
    required this.onPrevious,
    required this.onOpenPages,
    required this.onNext,
    required this.onAddPage,
  });

  final int currentPageNumber;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback onOpenPages;
  final VoidCallback? onNext;
  final VoidCallback? onAddPage;

  @override
  Widget build(BuildContext context) {
    const targetSize = 44.0;
    final divider = Container(
      width: 1,
      height: 24,
      color: EditorWorkspaceTokens.divider,
    );

    return Material(
      color: EditorWorkspaceTokens.chrome,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          EditorWorkspaceTokens.controlRadius,
        ),
        side: const BorderSide(color: EditorWorkspaceTokens.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: targetSize,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('editor-previous-page-button'),
              onPressed: onPrevious,
              tooltip: 'Previous page',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: targetSize,
                height: targetSize,
              ),
              icon: const Icon(Icons.chevron_left, size: 22),
            ),
            divider,
            Tooltip(
              message: 'Open Pages; page $currentPageNumber of $pageCount',
              child: TextButton(
                key: const ValueKey('editor-pages-button'),
                onPressed: onOpenPages,
                style: TextButton.styleFrom(
                  foregroundColor: EditorWorkspaceTokens.ink,
                  minimumSize: const Size(68, targetSize),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.library_books_outlined, size: 17),
                    const SizedBox(width: 4),
                    Text(
                      '$currentPageNumber / $pageCount',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: EditorWorkspaceTokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            divider,
            IconButton(
              key: const ValueKey('editor-next-page-button'),
              onPressed: onNext,
              tooltip: 'Next page',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: targetSize,
                height: targetSize,
              ),
              icon: const Icon(Icons.chevron_right, size: 22),
            ),
            divider,
            IconButton(
              key: const ValueKey('editor-add-page-button'),
              onPressed: onAddPage,
              tooltip: 'Add page after current',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: targetSize,
                height: targetSize,
              ),
              icon: const Icon(Icons.note_add_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

enum _EditorMenuAction {
  audioLibrary,
  toggleRecording,
  importPdf,
  exportPdf,
  fitWidth,
  fitPage,
}

class _EditorOverflowMenu extends StatelessWidget {
  const _EditorOverflowMenu({
    required this.page,
    required this.isRecording,
    required this.isAudioBusy,
    required this.isImportingPdfs,
    required this.isExporting,
    required this.hasAudioRecordings,
    required this.onSelected,
  });

  final NotePage? page;
  final bool isRecording;
  final bool isAudioBusy;
  final bool isImportingPdfs;
  final bool isExporting;
  final bool hasAudioRecordings;
  final ValueChanged<_EditorMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_EditorMenuAction>(
      key: const ValueKey('editor-more-actions'),
      tooltip: 'More editor actions',
      color: EditorWorkspaceTokens.chrome,
      surfaceTintColor: Colors.transparent,
      shape: EditorChrome.shape,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          _editorMenuSection('Document'),
          _editorMenuItem(
            value: _EditorMenuAction.importPdf,
            icon: Icons.picture_as_pdf_outlined,
            label: isImportingPdfs ? 'Importing PDF…' : 'Import PDF',
            enabled: page != null && !isImportingPdfs && !isRecording,
          ),
          _editorMenuItem(
            value: _EditorMenuAction.exportPdf,
            icon: Icons.ios_share,
            label: isExporting ? 'Exporting…' : 'Export PDF',
            enabled: page != null && !isExporting,
          ),
          const PopupMenuDivider(height: 8),
          _editorMenuSection('Audio'),
          _editorMenuItem(
            value: _EditorMenuAction.audioLibrary,
            icon: Icons.library_music_outlined,
            label: hasAudioRecordings ? 'Audio recordings' : 'Audio library',
          ),
          _editorMenuItem(
            value: _EditorMenuAction.toggleRecording,
            icon: isRecording ? Icons.stop_circle_outlined : Icons.mic_none,
            label: isRecording ? 'Stop recording' : 'Start recording',
            enabled: page != null && !isAudioBusy,
          ),
          const PopupMenuDivider(height: 8),
          _editorMenuSection('View'),
          _editorMenuItem(
            value: _EditorMenuAction.fitWidth,
            icon: Icons.fit_screen_outlined,
            label: 'Fit width',
            enabled: page != null,
          ),
          _editorMenuItem(
            value: _EditorMenuAction.fitPage,
            icon: Icons.center_focus_strong,
            label: 'Fit page',
            enabled: page != null,
          ),
        ];
      },
      icon: const Icon(Icons.more_horiz),
    );
  }
}

PopupMenuItem<_EditorMenuAction> _editorMenuItem({
  required _EditorMenuAction value,
  required IconData icon,
  required String label,
  bool enabled = true,
}) {
  return PopupMenuItem<_EditorMenuAction>(
    value: value,
    enabled: enabled,
    height: 44,
    child: Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: enabled
              ? EditorWorkspaceTokens.ink
              : EditorWorkspaceTokens.ink.withValues(alpha: 0.35),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? EditorWorkspaceTokens.ink
                  : EditorWorkspaceTokens.ink.withValues(alpha: 0.35),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

PopupMenuItem<_EditorMenuAction> _editorMenuSection(String label) {
  return PopupMenuItem<_EditorMenuAction>(
    enabled: false,
    height: 32,
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: EditorWorkspaceTokens.ink.withValues(alpha: 0.58),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _AudioRecordingBanner extends StatelessWidget {
  const _AudioRecordingBanner({required this.elapsed, required this.onStop});

  final Duration elapsed;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.errorContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.mic, color: colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recording ${_formatDuration(elapsed)}',
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onStop,
                  tooltip: 'Stop audio recording',
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioPlaybackBar extends StatefulWidget {
  const _AudioPlaybackBar({
    required this.title,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isLoading,
    required this.isFollowingPlayback,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onToggleFollow,
    required this.onClose,
  });

  final String title;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isLoading;
  final bool isFollowingPlayback;
  final VoidCallback onTogglePlayback;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onToggleFollow;
  final VoidCallback onClose;

  @override
  State<_AudioPlaybackBar> createState() => _AudioPlaybackBarState();
}

class _AudioPlaybackBarState extends State<_AudioPlaybackBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxMilliseconds = math.max(1, widget.duration.inMilliseconds);
    final positionMilliseconds = widget.position.inMilliseconds
        .clamp(0, maxMilliseconds)
        .toDouble();

    return Material(
      color: colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                onPressed: widget.isLoading ? null : widget.onTogglePlayback,
                tooltip: widget.isPlaying
                    ? 'Pause audio playback'
                    : 'Play audio recording',
                icon: widget.isLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              SizedBox(
                width: 96,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      '${_formatDuration(widget.position)} / '
                      '${_formatDuration(widget.duration)}',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Slider(
                  value: _dragValue ?? positionMilliseconds,
                  max: maxMilliseconds.toDouble(),
                  onChanged: widget.isLoading
                      ? null
                      : (value) {
                          setState(() {
                            _dragValue = value;
                          });
                        },
                  onChangeEnd: widget.isLoading
                      ? null
                      : (value) {
                          setState(() {
                            _dragValue = null;
                          });
                          widget.onSeek(Duration(milliseconds: value.round()));
                        },
                ),
              ),
              IconButton(
                onPressed: widget.onToggleFollow,
                tooltip: widget.isFollowingPlayback
                    ? 'Stop following playback'
                    : 'Follow playback',
                icon: Icon(
                  widget.isFollowingPlayback
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                tooltip: 'Close audio playback',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioRecordingsSheet extends StatelessWidget {
  const _AudioRecordingsSheet({
    required this.recordings,
    required this.activeElapsed,
    required this.selectedRecordingId,
    required this.pageIds,
    required this.canPlay,
    required this.onPlay,
  });

  final List<NotebookAudioRecording> recordings;
  final Duration? activeElapsed;
  final String? selectedRecordingId;
  final List<String> pageIds;
  final bool canPlay;
  final ValueChanged<NotebookAudioRecording> onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Audio recordings',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (activeElapsed case final elapsed?)
              ListTile(
                leading: Icon(Icons.mic, color: colorScheme.error),
                title: const Text('Recording now'),
                subtitle: Text(_formatDuration(elapsed)),
              ),
            Expanded(
              child: recordings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.library_music_outlined,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No recordings yet',
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: recordings.length,
                      itemBuilder: (context, index) {
                        final recording = recordings[index];
                        final pageIndex = recording.pageId == null
                            ? -1
                            : pageIds.indexOf(recording.pageId!);
                        final isSelected = recording.id == selectedRecordingId;

                        return ListTile(
                          leading: IconButton(
                            onPressed: canPlay ? () => onPlay(recording) : null,
                            tooltip: 'Play recording ${index + 1}',
                            icon: Icon(
                              isSelected
                                  ? Icons.replay_circle_filled
                                  : Icons.play_circle_outline,
                            ),
                          ),
                          title: Text('Recording ${index + 1}'),
                          subtitle: Text(
                            '${_formatDuration(recording.duration)} - '
                            '${_formatDateTime(recording.createdAt)}'
                            '${pageIndex < 0 ? '' : ' - Page ${pageIndex + 1}'}',
                          ),
                        );
                      },
                    ),
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
    required this.font,
    required this.replaceSelectedInk,
  });

  final String text;
  final InkBeautifyFont font;
  final bool replaceSelectedInk;
}

class _SmartInkConfirmationDialog extends StatefulWidget {
  const _SmartInkConfirmationDialog({
    required this.selectedStrokeCount,
    required this.recognition,
  });

  final int selectedStrokeCount;
  final Future<TextRecognitionResult> recognition;

  @override
  State<_SmartInkConfirmationDialog> createState() =>
      _SmartInkConfirmationDialogState();
}

class _SmartInkConfirmationDialogState
    extends State<_SmartInkConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();
  InkBeautifyFont _font = InkBeautifyFonts.liuJianMaoCao;
  bool _isRecognizing = true;
  bool _userEditedText = false;
  bool _showTextEditor = false;
  String? _recognitionMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecognition());
  }

  Future<void> _loadRecognition() async {
    String? message;
    var showEditor = false;
    try {
      final result = await widget.recognition;
      final recognizedText = result.text.trim();
      if (recognizedText.isEmpty) {
        message = 'No text recognized. Enter the text to redraw.';
        showEditor = true;
      } else if (!_userEditedText && _controller.text.trim().isEmpty) {
        _controller.text = recognizedText;
      }
    } on TextRecognitionUnavailableException {
      message =
          'On-device recognition is unavailable. Enter the text to redraw.';
      showEditor = true;
    } on TextRecognitionException {
      message = 'Recognition failed. Enter the text to redraw.';
      showEditor = true;
    } catch (_) {
      message = 'Recognition failed. Enter the text to redraw.';
      showEditor = true;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isRecognizing = false;
      _recognitionMessage = message;
      _showTextEditor = showEditor;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final previewText = text.isEmpty ? _font.preview : text;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Beautify ink'),
      backgroundColor: EditorWorkspaceTokens.chrome,
      surfaceTintColor: Colors.transparent,
      shape: EditorChrome.shape,
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isRecognizing)
                const Row(
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Recognizing on device...'),
                  ],
                )
              else if (_recognitionMessage case final message?)
                Text(message)
              else
                Text(
                  'Choose a style to redraw the selected ink.',
                  style: theme.textTheme.bodyMedium,
                ),
              if (!_isRecognizing && text.isNotEmpty && !_showTextEditor) ...[
                const SizedBox(height: 12),
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: EditorWorkspaceTokens.ink,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('beautify-edit-text'),
                    onPressed: () {
                      setState(() {
                        _showTextEditor = true;
                      });
                    },
                    child: const Text('Edit text'),
                  ),
                ),
              ],
              if (_showTextEditor) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Text to redraw',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    _userEditedText = true;
                    setState(() {});
                  },
                ),
              ],
              const SizedBox(height: 12),
              Text('Handwriting style', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final font in InkBeautifyFonts.values)
                    ChoiceChip(
                      key: ValueKey('beautify-font-${font.id}'),
                      label: Text(font.label),
                      selected: _font.id == font.id,
                      onSelected: (_) {
                        setState(() {
                          _font = font;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: EditorWorkspaceTokens.paper,
                  borderRadius: BorderRadius.circular(
                    EditorWorkspaceTokens.controlRadius,
                  ),
                  border: Border.all(color: EditorWorkspaceTokens.divider),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      previewText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: _font.fontFamily,
                        fontSize: 28,
                        color: EditorWorkspaceTokens.ink,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
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
          key: const ValueKey('beautify-confirm'),
          onPressed: text.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _SmartInkConfirmation(
                    text: text,
                    font: _font,
                    replaceSelectedInk: true,
                  ),
                ),
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('Beautify'),
        ),
      ],
    );
  }
}

enum _ExportScope { fullNotebook, currentPage, selectedPages }

class _ExportSelection {
  const _ExportSelection({
    required this.pageIds,
    required this.fileNameSuffix,
    required this.quality,
  });

  final List<String> pageIds;
  final String fileNameSuffix;
  final PdfExportQuality quality;
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
  PdfExportQuality _quality = PdfExportQuality.balanced;
  late final TextEditingController _pageSelectionController;

  int get _pageCount => widget.pageIds.length;

  int get _currentPageNumber {
    final currentIndex = widget.pageIds.indexOf(widget.currentPageId);
    return currentIndex == -1 ? 1 : currentIndex + 1;
  }

  @override
  void initState() {
    super.initState();
    _pageSelectionController = TextEditingController(
      text: _currentPageNumber.toString(),
    );
  }

  @override
  void dispose() {
    _pageSelectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionError = _scope == _ExportScope.selectedPages
        ? _parsedPageSelection.errorMessage
        : null;
    final selection = _selectionOrNull;

    return AlertDialog(
      title: const Text('Export PDF'),
      backgroundColor: EditorWorkspaceTokens.chrome,
      surfaceTintColor: Colors.transparent,
      shape: EditorChrome.shape,
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
                    value: _ExportScope.selectedPages,
                    icon: Icon(Icons.playlist_add_check),
                    label: Text('Pages'),
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
              if (_scope == _ExportScope.selectedPages) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _pageSelectionController,
                  decoration: const InputDecoration(
                    labelText: 'Pages to export',
                    hintText: '1,3,5-7',
                    helperText: 'Separate pages or ranges with commas.',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                ),
                if (selectionError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    selectionError,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              Text('Export quality', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<PdfExportQuality>(
                showSelectedIcon: false,
                selected: {_quality},
                segments: [
                  for (final quality in PdfExportQuality.values)
                    ButtonSegment(value: quality, label: Text(quality.label)),
                ],
                onSelectionChanged: (selected) {
                  setState(() {
                    _quality = selected.single;
                  });
                },
              ),
              const SizedBox(height: 8),
              Text(
                _quality.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
      _ExportScope.selectedPages => 'Choose individual pages or page ranges',
    };
  }

  PdfPageSelectionParseResult get _parsedPageSelection {
    return parsePdfPageSelection(
      _pageSelectionController.text,
      pageCount: _pageCount,
    );
  }

  _ExportSelection? get _selectionOrNull {
    if (widget.pageIds.isEmpty) {
      return null;
    }

    return switch (_scope) {
      _ExportScope.fullNotebook => _ExportSelection(
        pageIds: List.unmodifiable(widget.pageIds),
        fileNameSuffix: '',
        quality: _quality,
      ),
      _ExportScope.currentPage => _currentPageSelection,
      _ExportScope.selectedPages => _selectedPagesSelection,
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
      quality: _quality,
    );
  }

  _ExportSelection? get _selectedPagesSelection {
    final parsedSelection = _parsedPageSelection;
    if (!parsedSelection.isValid) {
      return null;
    }

    final pageNumbers = parsedSelection.pageNumbers;
    final isContiguous = pageNumbers.indexed.every((entry) {
      final (index, pageNumber) = entry;
      return index == 0 || pageNumber == pageNumbers[index - 1] + 1;
    });
    final suffix = switch (pageNumbers) {
      [final pageNumber] => '-page-$pageNumber',
      [final first, ..., final last] when isContiguous => '-pages-$first-$last',
      _ => '-selected-pages',
    };

    return _ExportSelection(
      pageIds: List.unmodifiable(
        pageNumbers.map((pageNumber) => widget.pageIds[pageNumber - 1]),
      ),
      fileNameSuffix: suffix,
      quality: _quality,
    );
  }
}

class _NavigationPanelFrame extends StatelessWidget {
  const _NavigationPanelFrame({
    required this.label,
    required this.icon,
    required this.fillAvailableHeight,
    required this.child,
  });

  final String label;
  final IconData icon;
  final bool fillAvailableHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        key: ValueKey('editor-${label.toLowerCase()}-panel'),
        height: fillAvailableHeight
            ? double.infinity
            : MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Material(
              color: EditorWorkspaceTokens.chrome,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: EditorWorkspaceTokens.divider),
                  ),
                ),
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(icon, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _PagesNavigationPanel extends StatelessWidget {
  const _PagesNavigationPanel({
    this.fillAvailableHeight = false,
    required this.notebook,
    required this.pagesById,
    required this.currentPageId,
    required this.onSelectPage,
    required this.onAddPage,
    required this.onRotateCurrentPage,
    required this.onInsertPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
    required this.onMovePage,
    required this.onRotatePage,
  });

  final bool fillAvailableHeight;
  final Notebook notebook;
  final Map<String, NotePage> pagesById;
  final String currentPageId;
  final ValueChanged<String> onSelectPage;
  final VoidCallback onAddPage;
  final VoidCallback onRotateCurrentPage;
  final ValueChanged<int> onInsertPage;
  final ValueChanged<String> onDuplicatePage;
  final ValueChanged<String> onDeletePage;
  final void Function(String pageId, int newIndex) onMovePage;
  final ValueChanged<String> onRotatePage;

  @override
  Widget build(BuildContext context) {
    return _NavigationPanelFrame(
      label: 'Pages',
      icon: Icons.layers_outlined,
      fillAvailableHeight: fillAvailableHeight,
      child: _PagesTab(
        pageIds: notebook.pageIds,
        pagesById: pagesById,
        currentPageId: currentPageId,
        bookmarkedPageIds: notebook.bookmarkedPageIds.toSet(),
        onSelectPage: onSelectPage,
        onAddPage: onAddPage,
        onRotateCurrentPage: onRotateCurrentPage,
        onInsertPage: onInsertPage,
        onDuplicatePage: onDuplicatePage,
        onDeletePage: onDeletePage,
        onMovePage: onMovePage,
        onRotatePage: onRotatePage,
      ),
    );
  }
}

class _PagesTab extends StatelessWidget {
  const _PagesTab({
    required this.pageIds,
    required this.pagesById,
    required this.currentPageId,
    required this.bookmarkedPageIds,
    required this.onSelectPage,
    required this.onAddPage,
    required this.onRotateCurrentPage,
    required this.onInsertPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
    required this.onMovePage,
    required this.onRotatePage,
  });

  final List<String> pageIds;
  final Map<String, NotePage> pagesById;
  final String currentPageId;
  final Set<String> bookmarkedPageIds;
  final ValueChanged<String> onSelectPage;
  final VoidCallback onAddPage;
  final VoidCallback onRotateCurrentPage;
  final ValueChanged<int> onInsertPage;
  final ValueChanged<String> onDuplicatePage;
  final ValueChanged<String> onDeletePage;
  final void Function(String pageId, int newIndex) onMovePage;
  final ValueChanged<String> onRotatePage;

  @override
  Widget build(BuildContext context) {
    final currentIndex = pageIds.indexOf(currentPageId);
    final currentPage = pagesById[currentPageId];
    final canRotate =
        currentPage != null && !currentPage.isCoordinateSpaceWriteProtected;
    const actionConstraints = BoxConstraints.tightFor(width: 44, height: 44);

    return Column(
      children: [
        Material(
          color: EditorWorkspaceTokens.chrome,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EditorWorkspaceTokens.divider),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Page ${currentIndex < 0 ? 1 : currentIndex + 1} of ${pageIds.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: EditorWorkspaceTokens.ink,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('pages-add-page-button'),
                    onPressed: onAddPage,
                    tooltip: 'Add page after current',
                    visualDensity: VisualDensity.compact,
                    constraints: actionConstraints,
                    icon: const Icon(Icons.note_add_outlined, size: 20),
                  ),
                  IconButton(
                    key: const ValueKey('pages-rotate-button'),
                    onPressed: canRotate ? onRotateCurrentPage : null,
                    tooltip: canRotate
                        ? 'Rotate current page clockwise'
                        : 'Rotate page unavailable',
                    visualDensity: VisualDensity.compact,
                    constraints: actionConstraints,
                    icon: const Icon(Icons.rotate_right),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = math.max(
                3,
                (constraints.maxWidth / 112).floor(),
              );
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: 118,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: pageIds.length,
                itemBuilder: (context, index) {
                  final pageId = pageIds[index];
                  return Center(
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
                      onRotate: () => onRotatePage(pageId),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OutlineNavigationPanel extends StatelessWidget {
  const _OutlineNavigationPanel({
    required this.fillAvailableHeight,
    required this.notebook,
    required this.currentPageId,
    required this.onSelectPage,
  });

  final bool fillAvailableHeight;
  final Notebook notebook;
  final String currentPageId;
  final ValueChanged<String> onSelectPage;

  @override
  Widget build(BuildContext context) {
    return _NavigationPanelFrame(
      label: 'Outline',
      icon: Icons.format_list_bulleted,
      fillAvailableHeight: fillAvailableHeight,
      child: _OutlineTab(
        notebook: notebook,
        currentPageId: currentPageId,
        onSelectPage: onSelectPage,
      ),
    );
  }
}

class _BookmarksNavigationPanel extends StatelessWidget {
  const _BookmarksNavigationPanel({
    required this.fillAvailableHeight,
    required this.notebook,
    required this.currentPageId,
    required this.onSelectPage,
    required this.onToggleCurrentPage,
  });

  final bool fillAvailableHeight;
  final Notebook notebook;
  final String currentPageId;
  final ValueChanged<String> onSelectPage;
  final VoidCallback onToggleCurrentPage;

  @override
  Widget build(BuildContext context) {
    final isBookmarked = notebook.bookmarkedPageIds.contains(currentPageId);
    final currentPageIndex = notebook.pageIds.indexOf(currentPageId);
    return _NavigationPanelFrame(
      label: 'Bookmarks',
      icon: Icons.bookmark_border,
      fillAvailableHeight: fillAvailableHeight,
      child: Column(
        children: [
          Material(
            color: EditorWorkspaceTokens.chrome,
            child: ListTile(
              key: const ValueKey('bookmarks-toggle-current-page'),
              leading: Icon(
                isBookmarked
                    ? Icons.bookmark_remove
                    : Icons.bookmark_add_outlined,
                color: isBookmarked ? EditorWorkspaceTokens.primary : null,
              ),
              title: Text(
                isBookmarked
                    ? 'Remove current page bookmark'
                    : 'Bookmark current page',
              ),
              subtitle: currentPageIndex < 0
                  ? null
                  : Text('Page ${currentPageIndex + 1}'),
              onTap: currentPageIndex < 0 ? null : onToggleCurrentPage,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _BookmarksTab(
              notebook: notebook,
              currentPageId: currentPageId,
              onSelectPage: onSelectPage,
            ),
          ),
        ],
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

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime dateTime) {
  return '${dateTime.year}-'
      '${dateTime.month.toString().padLeft(2, '0')}-'
      '${dateTime.day.toString().padLeft(2, '0')} '
      '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}';
}

class _ZoomablePageViewport extends StatefulWidget {
  const _ZoomablePageViewport({
    super.key,
    required this.page,
    required this.fingerPanEnabled,
    required this.initialSessionState,
    required this.onSessionStateChanged,
    required this.child,
  });

  final NotePage page;
  final bool fingerPanEnabled;
  final PageViewportSessionState? initialSessionState;
  final ValueChanged<PageViewportSessionState> onSessionStateChanged;
  final Widget child;

  @override
  State<_ZoomablePageViewport> createState() => _ZoomablePageViewportState();
}

class _ZoomablePageViewportState extends State<_ZoomablePageViewport> {
  final Map<int, Offset> _activePointers = {};
  Offset? _lastFocalPoint;
  double? _lastPointerDistance;
  PageViewportTransform? _transform;
  bool _zoomChromeExpanded = false;
  bool _showZoomBadge = false;
  Timer? _zoomIdleTimer;

  @override
  void dispose() {
    _zoomIdleTimer?.cancel();
    super.dispose();
  }

  void fitWidth() => _fit(PageViewportMode.fitWidth);

  void fitPage() => _fit(PageViewportMode.fitPage);

  @override
  void didUpdateWidget(covariant _ZoomablePageViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page.id != oldWidget.page.id) {
      _transform = null;
      _zoomChromeExpanded = false;
      _showZoomBadge = false;
      _zoomIdleTimer?.cancel();
    } else if (_transform case final transform?
        when widget.page.width != oldWidget.page.width ||
            widget.page.height != oldWidget.page.height ||
            widget.page.rotationQuarterTurns !=
                oldWidget.page.rotationQuarterTurns) {
      _transform = PageViewportTransform.restore(
        documentSize: Size(widget.page.width, widget.page.height),
        rotationQuarterTurns: widget.page.rotationQuarterTurns,
        usableRect: transform.usableRect,
        state: transform.sessionState,
      );
      widget.onSessionStateChanged(_transform!.sessionState);
    }
    if (widget.fingerPanEnabled != oldWidget.fingerPanEnabled) {
      _resetPointerTracking();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    final transform = _transform;
    if (transform != null &&
        transform.mode != PageViewportMode.custom &&
        (event.kind != PointerDeviceKind.touch || !widget.fingerPanEnabled)) {
      _setTransform(transform.enterCustom(), announceZoom: false);
    }

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
      final transform = _transform;
      if (transform != null) {
        _setTransform(
          transform.applyViewportGesture(
            previousFocalPoint: previousFocalPoint,
            focalPoint: focalPoint,
            scaleFactor: distance / previousDistance,
          ),
        );
      }
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
    final transform = _transform;
    if (previousFocalPoint != null && transform != null) {
      _setTransform(
        transform.panBy(focalPoint - previousFocalPoint),
        announceZoom: false,
      );
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

  void _setTransform(
    PageViewportTransform transform, {
    bool announceZoom = true,
  }) {
    setState(() {
      _transform = transform;
      if (announceZoom) {
        _showZoomBadge = true;
        _zoomChromeExpanded = true;
      }
    });
    widget.onSessionStateChanged(transform.sessionState);
    if (announceZoom) {
      _scheduleZoomIdleCollapse();
    }
  }

  void _scheduleZoomIdleCollapse() {
    _zoomIdleTimer?.cancel();
    _zoomIdleTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showZoomBadge = false;
        _zoomChromeExpanded = false;
      });
    });
  }

  void _expandZoomChrome() {
    setState(() {
      _zoomChromeExpanded = true;
    });
    _scheduleZoomIdleCollapse();
  }

  void _zoomBy(double scaleFactor) {
    final transform = _transform;
    if (transform != null) {
      _setTransform(transform.zoomBy(scaleFactor: scaleFactor));
    }
  }

  void _fit(PageViewportMode mode) {
    final transform = _transform;
    if (transform == null || mode == PageViewportMode.custom) {
      return;
    }
    _setTransform(transform.fit(mode));
    _resetPointerTracking();
  }

  void _resetPointerTracking() {
    _activePointers.clear();
    _lastFocalPoint = null;
    _lastPointerDistance = null;
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

  PageViewportTransform? _resolveTransform(BoxConstraints constraints) {
    final viewportSize = constraints.biggest;
    if (!viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return null;
    }

    final usableRect = Offset.zero & viewportSize;
    final documentSize = Size(widget.page.width, widget.page.height);
    var transform = _transform;

    if (transform == null) {
      final restoredState = widget.initialSessionState;
      transform = restoredState == null
          ? PageViewportTransform.firstVisit(
              documentSize: documentSize,
              rotationQuarterTurns: widget.page.rotationQuarterTurns,
              usableRect: usableRect,
            )
          : PageViewportTransform.restore(
              documentSize: documentSize,
              rotationQuarterTurns: widget.page.rotationQuarterTurns,
              usableRect: usableRect,
              state: restoredState,
            );
    } else if (transform.usableRect != usableRect) {
      transform = transform.reflow(usableRect);
    }

    _transform = transform;
    widget.onSessionStateChanged(transform.sessionState);
    return transform;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final transform = _resolveTransform(constraints);
        if (transform == null) {
          return const SizedBox.shrink();
        }
        final pageSize = transform.rotatedPageSize;
        final zoomPercent = transform.fitWidthRelativePercent;

        return Listener(
          key: ValueKey('viewport-${widget.page.id}'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: transform.pageOriginInViewport.dx,
                  top: transform.pageOriginInViewport.dy,
                  width: pageSize.width,
                  height: pageSize.height,
                  child: Transform.scale(
                    key: ValueKey(
                      'page-transform-${widget.page.id}-'
                      '${widget.page.rotationQuarterTurns}',
                    ),
                    scale: transform.effectiveScale,
                    alignment: Alignment.topLeft,
                    child: SizedBox.fromSize(
                      size: pageSize,
                      child: widget.child,
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _ZoomControls(
                    expanded: _zoomChromeExpanded,
                    mode: transform.mode,
                    zoomPercent: zoomPercent,
                    canZoomOut:
                        transform.effectiveScale > transform.minimumCustomScale,
                    canZoomIn:
                        transform.effectiveScale < transform.maximumCustomScale,
                    onExpand: _expandZoomChrome,
                    onZoomOut: () => _zoomBy(0.8),
                    onZoomIn: () => _zoomBy(1.25),
                    onFitWidth: () => _fit(PageViewportMode.fitWidth),
                    onFitPage: () => _fit(PageViewportMode.fitPage),
                  ),
                ),
                if (_showZoomBadge)
                  IgnorePointer(
                    child: Center(
                      child: _ZoomStatusBadge(percent: zoomPercent),
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
    required this.expanded,
    required this.mode,
    required this.zoomPercent,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onExpand,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitWidth,
    required this.onFitPage,
  });

  final bool expanded;
  final PageViewportMode mode;
  final int zoomPercent;
  final bool canZoomOut;
  final bool canZoomIn;
  final VoidCallback onExpand;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFitWidth;
  final VoidCallback onFitPage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorWorkspaceTokens.chrome,
      elevation: expanded ? 3 : 1,
      shadowColor: EditorWorkspaceTokens.paperShadow,
      borderRadius: BorderRadius.circular(EditorWorkspaceTokens.chromeRadius),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerRight,
        child: expanded
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: canZoomOut ? onZoomOut : null,
                      tooltip: 'Zoom out',
                      icon: const Icon(Icons.zoom_out),
                    ),
                    PopupMenuButton<PageViewportMode>(
                      tooltip: 'Zoom and fit',
                      color: EditorWorkspaceTokens.chrome,
                      surfaceTintColor: Colors.transparent,
                      shape: EditorChrome.shape,
                      initialValue: mode == PageViewportMode.custom
                          ? null
                          : mode,
                      onSelected: (selectedMode) {
                        switch (selectedMode) {
                          case PageViewportMode.fitWidth:
                            onFitWidth();
                          case PageViewportMode.fitPage:
                            onFitPage();
                          case PageViewportMode.custom:
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: PageViewportMode.fitWidth,
                          height: 48,
                          child: Row(
                            children: [
                              Icon(Icons.fit_screen_outlined),
                              SizedBox(width: 12),
                              Text('Fit width'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: PageViewportMode.fitPage,
                          height: 48,
                          child: Row(
                            children: [
                              Icon(Icons.center_focus_strong),
                              SizedBox(width: 12),
                              Text('Fit page'),
                            ],
                          ),
                        ),
                      ],
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 68,
                          minHeight: 44,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$zoomPercent%',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 18),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: canZoomIn ? onZoomIn : null,
                      tooltip: 'Zoom in',
                      icon: const Icon(Icons.zoom_in),
                    ),
                  ],
                ),
              )
            : Tooltip(
                message: 'Zoom and fit',
                child: InkWell(
                  key: const ValueKey('editor-zoom-chip'),
                  onTap: onExpand,
                  borderRadius: BorderRadius.circular(
                    EditorWorkspaceTokens.chromeRadius,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 64,
                      minHeight: 44,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$zoomPercent%',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.unfold_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ZoomStatusBadge extends StatelessWidget {
  const _ZoomStatusBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorWorkspaceTokens.ink.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(EditorWorkspaceTokens.chromeRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          '$percent%',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: EditorWorkspaceTokens.chrome,
            fontWeight: FontWeight.w700,
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
    required this.onRotate,
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
  final VoidCallback onRotate;

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
      case _PageAction.rotateClockwise:
        onRotate();
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
                      canDuplicateOrRotate:
                          !(page?.isCoordinateSpaceWriteProtected ?? false),
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
  rotateClockwise,
}

class _PageActionMenu extends StatelessWidget {
  const _PageActionMenu({
    required this.pageNumber,
    required this.canDuplicateOrRotate,
    required this.canDelete,
    required this.canMoveLeft,
    required this.canMoveRight,
    required this.onSelected,
  });

  final int pageNumber;
  final bool canDuplicateOrRotate;
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
      color: EditorWorkspaceTokens.chrome,
      surfaceTintColor: Colors.transparent,
      shape: EditorChrome.shape,
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
            enabled: canDuplicateOrRotate,
          ),
          _pageActionItem(
            value: _PageAction.rotateClockwise,
            icon: Icons.rotate_right,
            label: 'Rotate page clockwise',
            enabled: canDuplicateOrRotate,
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

    return Center(
      child: AspectRatio(
        aspectRatio: page.displayWidth / page.displayHeight,
        child: RotatedBox(
          quarterTurns: page.rotationQuarterTurns,
          child: Stack(
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
          ),
        ),
      ),
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

    if (page.pdfBackground == null) {
      paintPageTemplate(
        canvas,
        Size(page.width, page.height),
        page.template,
        minimumStrokeWidth: 1 / scale,
      );
    }

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
