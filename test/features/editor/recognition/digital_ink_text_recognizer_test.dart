import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/recognition/digital_ink_text_recognizer.dart';
import 'package:inknest_notes/models/stroke.dart';
import 'package:inknest_notes/models/stroke_point.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'passes vector strokes with monotonic timestamps and language fallback',
    () async {
      final backend = _FakeDigitalInkBackend();
      final recognizer = MlKitDigitalInkTextRecognizer(backend: backend);
      final time = DateTime.utc(2026, 8, 18);
      final result = await recognizer.recognize(
        strokes: [
          _stroke('later', time.add(const Duration(seconds: 2))),
          _stroke('earlier', time),
        ],
        writingArea: const Size(768, 1024),
        languageTags: const ['zh-Hani-CN', 'en-US'],
      );

      expect(backend.ensuredLanguages, ['zh-Hani-CN', 'en-US']);
      expect(backend.recognizedLanguages, ['zh-Hani-CN', 'en-US']);
      final points = backend.lastStrokes
          .expand((stroke) => stroke.points)
          .toList();
      expect(
        points.map((point) => point.timeMs),
        orderedEquals([...points.map((point) => point.timeMs)]..sort()),
      );
      expect(backend.lastWritingArea, const Size(34, 34));
      expect(points.first.x, 12);
      expect(points.first.y, 12);
      expect(points.last.x, 22);
      expect(points.last.y, 22);
      expect(result.text, 'Class notes');
      expect(result.languageTag, 'en-US');
      expect(result.engineIdentifier, contains('en-US'));
    },
  );

  test('rejects an empty selection before requesting a model', () async {
    final backend = _FakeDigitalInkBackend();

    await expectLater(
      MlKitDigitalInkTextRecognizer(backend: backend).recognize(
        strokes: const [],
        writingArea: const Size(100, 100),
        languageTags: const ['zh-Hani-CN'],
      ),
      throwsA(isA<DigitalInkRecognitionException>()),
    );
    expect(backend.ensuredLanguages, isEmpty);
  });

  test('uses supported ML Kit model identifiers for Chinese locales', () {
    expect(digitalInkLanguageTagsForLocale(const Locale('zh', 'CN')), [
      'zh-Hani-CN',
      'en-US',
    ]);
    expect(
      digitalInkLanguageTagsForLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      ['zh-Hani-TW', 'en-US'],
    );
    expect(digitalInkLanguageTagsForLocale(const Locale('zh', 'HK')), [
      'zh-Hani-HK',
      'en-US',
    ]);
  });

  test(
    'accepts an integer score returned by the native ML Kit channel',
    () async {
      const channel = MethodChannel('google_mlkit_digital_ink_recognizer');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'vision#startDigitalInkRecognizer') {
              return <Object?>[
                <Object?, Object?>{'text': '中', 'score': 0},
              ];
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final candidates = await MlKitDigitalInkRecognitionBackend().recognize(
        languageTag: 'zh-Hani-CN',
        strokes: const [
          DigitalInkStroke(points: [DigitalInkPoint(x: 12, y: 12, timeMs: 1)]),
        ],
        writingArea: const Size(36, 36),
      );

      expect(candidates.single.score, 0.0);
      expect(candidates.single.text, '中');
      expect(calls.map((call) => call.method), [
        'vision#startDigitalInkRecognizer',
        'vision#closeDigitalInkRecognizer',
      ]);
    },
  );

  test('does not hang when native recognizer close never completes', () async {
    const channel = MethodChannel('google_mlkit_digital_ink_recognizer');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'vision#startDigitalInkRecognizer') {
            return <Object?>[
              <Object?, Object?>{'text': '美化', 'score': 0},
            ];
          }
          if (call.method == 'vision#closeDigitalInkRecognizer') {
            return Completer<Object?>().future;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final candidates = await MlKitDigitalInkRecognitionBackend()
        .recognize(
          languageTag: 'zh-Hani-CN',
          strokes: const [
            DigitalInkStroke(
              points: [DigitalInkPoint(x: 12, y: 12, timeMs: 1)],
            ),
          ],
          writingArea: const Size(36, 36),
        )
        .timeout(const Duration(seconds: 2));

    expect(candidates.single.text, '美化');
  });
}

Stroke _stroke(String id, DateTime time) {
  return Stroke(
    id: id,
    tool: ToolType.pen,
    color: Colors.black,
    width: 3,
    points: [
      StrokePoint(offset: const Offset(10, 20), pressure: 1, time: time),
      StrokePoint(offset: const Offset(20, 30), pressure: 1, time: time),
    ],
  );
}

class _FakeDigitalInkBackend implements DigitalInkRecognitionBackend {
  final List<String> ensuredLanguages = [];
  final List<String> recognizedLanguages = [];
  List<DigitalInkStroke> lastStrokes = const [];
  Size? lastWritingArea;

  @override
  Future<void> ensureModel(String languageTag) async {
    ensuredLanguages.add(languageTag);
  }

  @override
  Future<List<DigitalInkRecognitionCandidate>> recognize({
    required String languageTag,
    required List<DigitalInkStroke> strokes,
    required Size writingArea,
  }) async {
    recognizedLanguages.add(languageTag);
    lastStrokes = strokes;
    lastWritingArea = writingArea;
    if (languageTag == 'zh-Hani-CN') return const [];
    return const [
      DigitalInkRecognitionCandidate(text: 'Class notes', score: -2),
      DigitalInkRecognitionCandidate(text: 'Class note', score: -1),
    ];
  }
}
