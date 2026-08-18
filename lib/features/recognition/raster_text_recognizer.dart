import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

@immutable
class RasterTextRecognitionRequest {
  const RasterTextRecognitionRequest({
    required this.rgbaBytes,
    required this.width,
    required this.height,
  });

  final Uint8List rgbaBytes;
  final int width;
  final int height;
}

@immutable
class RasterTextLine {
  const RasterTextLine({
    required this.text,
    required this.bounds,
    this.languages = const [],
  });

  final String text;
  final Rect bounds;
  final List<String> languages;
}

@immutable
class RasterTextRecognitionResult {
  const RasterTextRecognitionResult({
    required this.text,
    required this.lines,
    required this.engineIdentifier,
  });

  final String text;
  final List<RasterTextLine> lines;
  final String engineIdentifier;
}

abstract interface class RasterTextRecognizer {
  Future<RasterTextRecognitionResult> recognize(
    RasterTextRecognitionRequest request,
  );
}

class RasterTextRecognitionUnavailableException implements Exception {
  const RasterTextRecognitionUnavailableException([
    this.message = 'Local text recognition is unavailable.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class RasterTextRecognitionException implements Exception {
  const RasterTextRecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cross-platform raster OCR backed by the native ML Kit Chinese-script model.
///
/// The Chinese model is the InkNest default because the product prioritizes
/// simplified Chinese plus Latin note content. Native dependencies are added
/// explicitly on both iOS and Android.
class MlKitRasterTextRecognizer implements RasterTextRecognizer {
  const MlKitRasterTextRecognizer();

  static const engineIdentifier = 'google-mlkit-text-chinese-v1';

  @override
  Future<RasterTextRecognitionResult> recognize(
    RasterTextRecognitionRequest request,
  ) async {
    if (request.width <= 0 ||
        request.height <= 0 ||
        request.rgbaBytes.lengthInBytes != request.width * request.height * 4) {
      throw const RasterTextRecognitionException(
        'The OCR input bitmap is invalid.',
      );
    }

    final recognizer = mlkit.TextRecognizer(
      script: mlkit.TextRecognitionScript.chinese,
    );
    try {
      final recognized = await recognizer.processImage(
        mlkit.InputImage.fromBitmap(
          bitmap: request.rgbaBytes,
          width: request.width,
          height: request.height,
        ),
      );
      final lines = <RasterTextLine>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty)
              RasterTextLine(
                text: line.text,
                bounds: line.boundingBox,
                languages: List.unmodifiable(line.recognizedLanguages),
              ),
      ]..sort(_compareLines);
      return RasterTextRecognitionResult(
        text: recognized.text,
        lines: List.unmodifiable(lines),
        engineIdentifier: engineIdentifier,
      );
    } on MissingPluginException catch (error) {
      throw RasterTextRecognitionUnavailableException(
        error.message ?? 'Local text recognition is unavailable.',
      );
    } on PlatformException catch (error) {
      throw RasterTextRecognitionException(
        error.message ?? 'ML Kit text recognition failed.',
      );
    } finally {
      await recognizer.close();
    }
  }
}

int _compareLines(RasterTextLine first, RasterTextLine second) {
  final verticalDifference = first.bounds.top - second.bounds.top;
  if (verticalDifference.abs() > 4) {
    return verticalDifference.sign.toInt();
  }
  return first.bounds.left.compareTo(second.bounds.left);
}
