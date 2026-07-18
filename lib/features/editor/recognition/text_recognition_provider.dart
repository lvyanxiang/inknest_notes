import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class TextRecognitionRequest {
  const TextRecognitionRequest({
    required this.pngBytes,
    this.recognitionLanguages = const [],
    this.usesLanguageCorrection = true,
  });

  final Uint8List pngBytes;
  final List<String> recognitionLanguages;
  final bool usesLanguageCorrection;
}

@immutable
class TextRecognitionRegion {
  const TextRecognitionRegion({
    required this.text,
    required this.confidence,
    required this.normalizedBounds,
  });

  final String text;
  final double confidence;

  /// Top-left-origin bounds normalized to the recognition image.
  final Rect normalizedBounds;
}

@immutable
class TextRecognitionResult {
  const TextRecognitionResult({
    required this.text,
    required this.confidence,
    required this.regions,
    required this.engineIdentifier,
  });

  final String text;
  final double confidence;
  final List<TextRecognitionRegion> regions;
  final String engineIdentifier;
}

abstract class TextRecognitionProvider {
  Future<TextRecognitionResult> recognize(TextRecognitionRequest request);
}

class TextRecognitionUnavailableException implements Exception {
  const TextRecognitionUnavailableException([
    this.message = 'Text recognition is unavailable on this device.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class TextRecognitionException implements Exception {
  const TextRecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppleVisionTextRecognitionProvider implements TextRecognitionProvider {
  const AppleVisionTextRecognitionProvider();

  @visibleForTesting
  static const channel = MethodChannel('inknest_notes/text_recognition');

  @override
  Future<TextRecognitionResult> recognize(
    TextRecognitionRequest request,
  ) async {
    try {
      final response = await channel
          .invokeMethod<Object?>('recognizeText', <String, Object?>{
            'pngBytes': request.pngBytes,
            'recognitionLanguages': request.recognitionLanguages,
            'usesLanguageCorrection': request.usesLanguageCorrection,
          });
      if (response is! Map<Object?, Object?>) {
        throw const TextRecognitionException(
          'The recognition provider returned an invalid response.',
        );
      }

      return _resultFromMap(response);
    } on MissingPluginException {
      throw const TextRecognitionUnavailableException();
    } on PlatformException catch (error) {
      if (error.code == 'recognition_unavailable') {
        throw TextRecognitionUnavailableException(
          error.message ?? 'Text recognition is unavailable on this device.',
        );
      }
      throw TextRecognitionException(
        error.message ?? 'Text recognition failed.',
      );
    }
  }
}

TextRecognitionResult _resultFromMap(Map<Object?, Object?> map) {
  final regions = <TextRecognitionRegion>[];
  final rawRegions = map['regions'];
  if (rawRegions is List<Object?>) {
    for (final rawRegion in rawRegions) {
      if (rawRegion is! Map<Object?, Object?>) {
        continue;
      }
      final left = _doubleValue(rawRegion['left']);
      final top = _doubleValue(rawRegion['top']);
      final width = _doubleValue(rawRegion['width']);
      final height = _doubleValue(rawRegion['height']);
      regions.add(
        TextRecognitionRegion(
          text: rawRegion['text'] as String? ?? '',
          confidence: _doubleValue(rawRegion['confidence']).clamp(0, 1),
          normalizedBounds: Rect.fromLTWH(left, top, width, height),
        ),
      );
    }
  }

  return TextRecognitionResult(
    text: map['text'] as String? ?? '',
    confidence: _doubleValue(map['confidence']).clamp(0, 1),
    regions: List.unmodifiable(regions),
    engineIdentifier: map['engineIdentifier'] as String? ?? 'unknown',
  );
}

double _doubleValue(Object? value) {
  return value is num ? value.toDouble() : 0;
}
