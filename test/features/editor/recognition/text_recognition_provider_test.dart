import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/recognition/text_recognition_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends OCR options and maps Apple Vision regions', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      AppleVisionTextRecognitionProvider.channel,
      (call) async {
        expect(call.method, 'recognizeText');
        final arguments = call.arguments! as Map<Object?, Object?>;
        expect(arguments['pngBytes'], isA<Uint8List>());
        expect(arguments['recognitionLanguages'], ['zh-Hans', 'en-US']);
        expect(arguments['usesLanguageCorrection'], isTrue);
        return <String, Object?>{
          'text': '课堂笔记',
          'confidence': 0.92,
          'engineIdentifier': 'apple-vision-text-v3',
          'regions': <Object?>[
            <String, Object?>{
              'text': '课堂笔记',
              'confidence': 0.92,
              'left': 0.1,
              'top': 0.2,
              'width': 0.5,
              'height': 0.12,
            },
          ],
        };
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AppleVisionTextRecognitionProvider.channel,
        null,
      ),
    );

    final result = await const AppleVisionTextRecognitionProvider().recognize(
      TextRecognitionRequest(
        pngBytes: Uint8List.fromList(const [137, 80, 78, 71]),
        recognitionLanguages: const ['zh-Hans', 'en-US'],
      ),
    );

    expect(result.text, '课堂笔记');
    expect(result.confidence, closeTo(0.92, 0.001));
    expect(result.engineIdentifier, 'apple-vision-text-v3');
    expect(result.regions, hasLength(1));
    expect(
      result.regions.single.normalizedBounds,
      const Rect.fromLTWH(0.1, 0.2, 0.5, 0.12),
    );
  });

  test('reports a missing native recognizer as unavailable', () async {
    await expectLater(
      const AppleVisionTextRecognitionProvider().recognize(
        TextRecognitionRequest(pngBytes: Uint8List(1)),
      ),
      throwsA(isA<TextRecognitionUnavailableException>()),
    );
  });
}
