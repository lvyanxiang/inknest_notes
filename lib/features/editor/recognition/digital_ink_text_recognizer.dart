import 'dart:math' as math;
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;
import 'package:inknest_notes/models/stroke.dart' as note;

@immutable
class DigitalInkPoint {
  const DigitalInkPoint({
    required this.x,
    required this.y,
    required this.timeMs,
  });

  final double x;
  final double y;
  final int timeMs;
}

@immutable
class DigitalInkStroke {
  const DigitalInkStroke({required this.points});

  final List<DigitalInkPoint> points;
}

@immutable
class DigitalInkRecognitionCandidate {
  const DigitalInkRecognitionCandidate({
    required this.text,
    required this.score,
  });

  final String text;
  final double score;
}

@immutable
class DigitalInkRecognitionResult {
  const DigitalInkRecognitionResult({
    required this.text,
    required this.candidates,
    required this.languageTag,
    required this.engineIdentifier,
  });

  final String text;
  final List<DigitalInkRecognitionCandidate> candidates;
  final String languageTag;
  final String engineIdentifier;
}

abstract interface class DigitalInkTextRecognizer {
  Future<DigitalInkRecognitionResult> recognize({
    required List<note.Stroke> strokes,
    required Size writingArea,
    required List<String> languageTags,
  });
}

class DigitalInkRecognitionUnavailableException implements Exception {
  const DigitalInkRecognitionUnavailableException([
    this.message = 'Handwriting recognition is unavailable.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class DigitalInkRecognitionException implements Exception {
  const DigitalInkRecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class DigitalInkRecognitionBackend {
  Future<void> ensureModel(String languageTag);

  Future<List<DigitalInkRecognitionCandidate>> recognize({
    required String languageTag,
    required List<DigitalInkStroke> strokes,
    required Size writingArea,
  });
}

class MlKitDigitalInkRecognitionBackend
    implements DigitalInkRecognitionBackend {
  MlKitDigitalInkRecognitionBackend();

  static const MethodChannel _recognitionChannel = MethodChannel(
    'google_mlkit_digital_ink_recognizer',
  );
  static int _recognizerSequence = 0;

  final mlkit.DigitalInkRecognizerModelManager _modelManager =
      mlkit.DigitalInkRecognizerModelManager();

  @override
  Future<void> ensureModel(String languageTag) async {
    final stopwatch = Stopwatch()..start();
    _smartInkLog('model check started language=$languageTag');
    try {
      final isDownloaded = await _modelManager.isModelDownloaded(languageTag);
      _smartInkLog(
        'model check finished language=$languageTag '
        'downloaded=$isDownloaded elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      if (isDownloaded) return;

      _smartInkLog(
        'model download started language=$languageTag wifiOnly=false',
      );
      final downloaded = await _modelManager.downloadModel(
        languageTag,
        isWifiRequired: false,
      );
      _smartInkLog(
        'model download finished language=$languageTag success=$downloaded '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      if (!downloaded) {
        throw DigitalInkRecognitionUnavailableException(
          'Unable to download the $languageTag handwriting model.',
        );
      }
    } catch (error, stackTrace) {
      _smartInkLogError(
        'model preparation failed language=$languageTag',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<List<DigitalInkRecognitionCandidate>> recognize({
    required String languageTag,
    required List<DigitalInkStroke> strokes,
    required Size writingArea,
  }) async {
    final pointCount = strokes.fold<int>(
      0,
      (count, stroke) => count + stroke.points.length,
    );
    final stopwatch = Stopwatch()..start();
    _smartInkLog(
      'native recognition started language=$languageTag '
      'strokes=${strokes.length} points=$pointCount '
      'writingArea=${_formatSize(writingArea)}',
    );
    final recognizerId =
        '${DateTime.now().microsecondsSinceEpoch}-${_recognizerSequence++}';
    try {
      // google_mlkit_digital_ink_recognition 0.16.1 casts `score` directly to
      // double. The native codec may return the valid numeric value 0 as an
      // int, which crashes candidate decoding. Invoke the same plugin channel
      // and decode numeric scores through num.toDouble() until upstream fixes
      // its parser.
      final rawResult = await _recognitionChannel.invokeMethod<Object?>(
        'vision#startDigitalInkRecognizer',
        <String, Object?>{
          'id': recognizerId,
          'model': languageTag,
          'ink': <String, Object?>{
            'strokes': [
              for (final stroke in strokes)
                <String, Object?>{
                  'points': [
                    for (final point in stroke.points)
                      <String, Object?>{
                        'x': point.x,
                        'y': point.y,
                        't': point.timeMs,
                      },
                  ],
                },
            ],
          },
          'context': <String, Object?>{
            'preContext': null,
            'writingArea': <String, Object?>{
              'width': writingArea.width,
              'height': writingArea.height,
            },
          },
        },
      );
      if (rawResult is! List<Object?>) {
        throw DigitalInkRecognitionException(
          'ML Kit returned an invalid candidate response.',
        );
      }
      final candidates = <DigitalInkRecognitionCandidate>[
        for (final rawCandidate in rawResult)
          if (rawCandidate is Map<Object?, Object?> &&
              rawCandidate['text'] is String)
            DigitalInkRecognitionCandidate(
              text: rawCandidate['text']! as String,
              score: switch (rawCandidate['score']) {
                final num score => score.toDouble(),
                _ => 0.0,
              },
            ),
      ];
      _smartInkLog(
        'native recognition finished language=$languageTag '
        'candidates=${candidates.length} '
        'scores=${candidates.map((candidate) => candidate.score).toList()} '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return candidates;
    } catch (error, stackTrace) {
      _smartInkLogError(
        'native recognition failed language=$languageTag '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      // On some Android devices ML Kit's close call never completes. Do not
      // await it unboundedly or Beautify stays on the loading spinner forever
      // even after candidates are already available.
      await _closeRecognizer(recognizerId);
    }
  }

  Future<void> _closeRecognizer(String recognizerId) async {
    _smartInkLog('native recognizer close started id=$recognizerId');
    try {
      await _recognitionChannel
          .invokeMethod<void>(
            'vision#closeDigitalInkRecognizer',
            <String, Object?>{'id': recognizerId},
          )
          .timeout(const Duration(milliseconds: 800));
      _smartInkLog('native recognizer close finished id=$recognizerId');
    } catch (error, stackTrace) {
      _smartInkLogError(
        'native recognizer close skipped id=$recognizerId',
        error,
        stackTrace,
      );
    }
  }
}

class MlKitDigitalInkTextRecognizer implements DigitalInkTextRecognizer {
  MlKitDigitalInkTextRecognizer({DigitalInkRecognitionBackend? backend})
    : backend = backend ?? MlKitDigitalInkRecognitionBackend();

  static const engineIdentifier = 'google-mlkit-digital-ink-v1';

  final DigitalInkRecognitionBackend backend;

  @override
  Future<DigitalInkRecognitionResult> recognize({
    required List<note.Stroke> strokes,
    required Size writingArea,
    required List<String> languageTags,
  }) async {
    final stopwatch = Stopwatch()..start();
    final inputPointCount = strokes.fold<int>(
      0,
      (count, stroke) => count + stroke.points.length,
    );
    _smartInkLog(
      'request started languages=$languageTags inputStrokes=${strokes.length} '
      'inputPoints=$inputPointCount pageArea=${_formatSize(writingArea)}',
    );
    final preparedInk = _prepareDigitalInk(strokes, writingArea);
    final preparedPointCount = preparedInk.strokes.fold<int>(
      0,
      (count, stroke) => count + stroke.points.length,
    );
    _smartInkLog(
      'ink prepared strokes=${preparedInk.strokes.length} '
      'points=$preparedPointCount '
      'writingArea=${_formatSize(preparedInk.writingArea)}',
    );
    if (preparedInk.strokes.isEmpty) {
      throw const DigitalInkRecognitionException(
        'No drawable handwriting was selected.',
      );
    }
    final languages = languageTags
        .map((language) => language.trim())
        .where((language) => language.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (languages.isEmpty) {
      throw const DigitalInkRecognitionException(
        'No handwriting recognition language was selected.',
      );
    }

    Object? lastError;
    for (final languageTag in languages) {
      _smartInkLog('language attempt started language=$languageTag');
      try {
        await backend.ensureModel(languageTag);
        final candidates = await backend.recognize(
          languageTag: languageTag,
          strokes: preparedInk.strokes,
          writingArea: preparedInk.writingArea,
        );
        // ML Kit already returns candidates in likelihood order. Preserve that
        // order because models without scores legitimately report 0 for every
        // candidate, and sorting equal scores could move the native best match.
        final usable = candidates
            .where((candidate) => candidate.text.trim().isNotEmpty)
            .toList(growable: false);
        if (usable.isNotEmpty) {
          _smartInkLog(
            'request succeeded language=$languageTag candidates=${usable.length} '
            'bestScore=${usable.first.score} '
            'elapsedMs=${stopwatch.elapsedMilliseconds}',
          );
          return DigitalInkRecognitionResult(
            text: usable.first.text,
            candidates: List.unmodifiable(usable),
            languageTag: languageTag,
            engineIdentifier: '$engineIdentifier-$languageTag',
          );
        }
      } on MissingPluginException catch (error, stackTrace) {
        _smartInkLogError(
          'plugin unavailable language=$languageTag',
          error,
          stackTrace,
        );
        throw DigitalInkRecognitionUnavailableException(
          error.message ?? 'Handwriting recognition is unavailable.',
        );
      } on PlatformException catch (error, stackTrace) {
        _smartInkLogError(
          'platform failure language=$languageTag',
          error,
          stackTrace,
        );
        lastError = error;
      } on DigitalInkRecognitionUnavailableException catch (error, stackTrace) {
        _smartInkLogError(
          'model unavailable language=$languageTag',
          error,
          stackTrace,
        );
        lastError = error;
      } catch (error, stackTrace) {
        _smartInkLogError(
          'unexpected failure language=$languageTag',
          error,
          stackTrace,
        );
        lastError = error;
      }
    }
    _smartInkLog(
      'request failed languages=$languages '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    if (lastError case final DigitalInkRecognitionUnavailableException error) {
      throw error;
    }
    throw DigitalInkRecognitionException(
      lastError is PlatformException
          ? lastError.message ?? 'ML Kit handwriting recognition failed.'
          : 'ML Kit handwriting recognition returned no text.',
    );
  }
}

@immutable
class _PreparedDigitalInk {
  const _PreparedDigitalInk({required this.strokes, required this.writingArea});

  final List<DigitalInkStroke> strokes;
  final Size writingArea;
}

_PreparedDigitalInk _prepareDigitalInk(
  List<note.Stroke> strokes,
  Size fallbackWritingArea,
) {
  final drawable =
      [
        for (final stroke in strokes)
          if (stroke.points.any(
            (point) => point.offset.dx.isFinite && point.offset.dy.isFinite,
          ))
            stroke,
      ]..sort((first, second) {
        return first.points.first.time.compareTo(second.points.first.time);
      });
  if (drawable.isEmpty) {
    return _PreparedDigitalInk(
      strokes: const [],
      writingArea: fallbackWritingArea,
    );
  }

  final offsets = [
    for (final stroke in drawable)
      for (final point in stroke.points)
        if (point.offset.dx.isFinite && point.offset.dy.isFinite) point.offset,
  ];
  final minX = offsets.map((offset) => offset.dx).reduce(math.min);
  final maxX = offsets.map((offset) => offset.dx).reduce(math.max);
  final minY = offsets.map((offset) => offset.dy).reduce(math.min);
  final maxY = offsets.map((offset) => offset.dy).reduce(math.max);
  final inkHeight = maxY - minY;
  final padding = math.max(12.0, inkHeight * 0.2);
  final origin = Offset(minX - padding, minY - padding);
  final localWritingArea = Size(
    math.max(1, maxX - minX + padding * 2),
    math.max(1, inkHeight + padding * 2),
  );

  var previousTime = 0;
  return _PreparedDigitalInk(
    writingArea: localWritingArea,
    strokes: [
      for (final stroke in drawable)
        DigitalInkStroke(
          points: [
            for (final point in stroke.points)
              if (point.offset.dx.isFinite && point.offset.dy.isFinite)
                DigitalInkPoint(
                  x: point.offset.dx - origin.dx,
                  y: point.offset.dy - origin.dy,
                  timeMs: previousTime = math.max(
                    point.time.millisecondsSinceEpoch,
                    previousTime + 1,
                  ),
                ),
          ],
        ),
    ],
  );
}

List<String> digitalInkLanguageTagsForLocale(Locale locale) {
  if (locale.languageCode.toLowerCase() != 'zh') {
    return const ['en-US', 'zh-Hani-CN'];
  }

  final region = locale.countryCode?.toUpperCase();
  final script = locale.scriptCode?.toLowerCase();
  if (region == 'HK' || region == 'MO') {
    return const ['zh-Hani-HK', 'en-US'];
  }
  if (region == 'TW' || script == 'hant') {
    return const ['zh-Hani-TW', 'en-US'];
  }
  return const ['zh-Hani-CN', 'en-US'];
}

void _smartInkLog(String message) {
  if (kDebugMode) {
    debugPrint('[SmartInk] $message');
  }
}

void _smartInkLogError(String message, Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  if (error is PlatformException) {
    debugPrint(
      '[SmartInk] $message '
      'code=${error.code} message=${error.message} details=${error.details}',
    );
  } else {
    debugPrint(
      '[SmartInk] $message errorType=${error.runtimeType} error=$error',
    );
  }
  debugPrintStack(
    label: '[SmartInk] stack',
    stackTrace: stackTrace,
    maxFrames: 12,
  );
}

String _formatSize(Size size) {
  return '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
}
