import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/features/editor/tools/editor_toolbar.dart';
import 'package:inknest_notes/models/tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpToolbar(
    WidgetTester tester, {
    required Size size,
    required DrawingTool tool,
    required ValueChanged<DrawingTool> onToolChanged,
    bool fingerPanEnabled = false,
    bool fingerWritingAssistEnabled = true,
    ValueChanged<bool>? onFingerPanChanged,
    ValueChanged<bool>? onFingerWritingAssistChanged,
    VoidCallback? onInsertImage,
  }) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: EditorToolbar(
              tool: tool,
              fingerPanEnabled: fingerPanEnabled,
              fingerWritingAssistEnabled: fingerWritingAssistEnabled,
              onToolChanged: onToolChanged,
              onFingerPanChanged: onFingerPanChanged ?? (_) {},
              onFingerWritingAssistChanged:
                  onFingerWritingAssistChanged ?? (_) {},
              onInsertImage: onInsertImage ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('keeps core tools visible without horizontal scrolling', (
    tester,
  ) async {
    for (final size in const [
      Size(600, 800),
      Size(834, 1194),
      Size(1194, 834),
    ]) {
      await pumpToolbar(
        tester,
        size: size,
        tool: const DrawingTool(
          type: ToolType.pen,
          color: Color(0xFF1E2526),
          width: 3,
        ),
        onToolChanged: (_) {},
      );

      expect(tester.takeException(), isNull);
      for (final label in const [
        'Pen',
        'Highlighter',
        'Eraser',
        'Lasso',
        'Insert',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
        expect(
          tester.getSize(find.byTooltip(label)).height,
          greaterThanOrEqualTo(44),
        );
      }
      expect(
        find.descendant(
          of: find.byType(EditorToolbar),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(find.byTooltip('Smart Ink'), findsNothing);
    }
  });

  testWidgets('Insert exposes text, image, and shape actions', (tester) async {
    var tool = const DrawingTool(
      type: ToolType.pen,
      color: Color(0xFF1E2526),
      width: 3,
    );
    var imageInsertCount = 0;

    Future<void> rebuild() async {
      await pumpToolbar(
        tester,
        size: const Size(834, 1194),
        tool: tool,
        onToolChanged: (value) {
          tool = value;
        },
        onInsertImage: () {
          imageInsertCount += 1;
        },
      );
    }

    await rebuild();
    await tester.tap(find.byKey(const ValueKey('editor-insert-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Shape'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(tool.type, ToolType.text);

    await rebuild();
    await tester.tap(find.byKey(const ValueKey('editor-insert-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image'));
    await tester.pumpAndSettle();
    expect(imageInsertCount, 1);
    expect(tool.type, ToolType.text);
  });

  testWidgets('wide preset applies a complete tool configuration', (
    tester,
  ) async {
    var tool = const DrawingTool(
      type: ToolType.pen,
      color: Color(0xFF1E2526),
      width: 3,
    );

    await pumpToolbar(
      tester,
      size: const Size(1194, 834),
      tool: tool,
      onToolChanged: (value) {
        tool = value;
      },
    );
    await tester.tap(
      find.byKey(const ValueKey('editor-preset-Teal pen, 5 pt')),
    );
    await tester.pump();

    expect(tool.type, ToolType.pen);
    expect(tool.color, const Color(0xFF2F6F73));
    expect(tool.width, 5);
  });

  testWidgets('properties sheet changes only contextual settings', (
    tester,
  ) async {
    var tool = const DrawingTool(
      type: ToolType.pen,
      color: Color(0xFF1E2526),
      width: 3,
    );

    await pumpToolbar(
      tester,
      size: const Size(600, 800),
      tool: tool,
      onToolChanged: (value) {
        tool = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('editor-tool-properties')));
    await tester.pumpAndSettle();

    expect(find.text('Pen settings'), findsOneWidget);
    expect(find.text('Eraser mode'), findsNothing);
    expect(find.byKey(const ValueKey('tool-width-5.0')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('tool-width-5.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tool-width-5.0')));
    await tester.pump();
    expect(tool.width, 5);
  });

  testWidgets('finger mode menu separates movement and writing assist', (
    tester,
  ) async {
    var fingerPanEnabled = false;
    var writingAssistEnabled = true;

    await pumpToolbar(
      tester,
      size: const Size(834, 1194),
      tool: const DrawingTool(
        type: ToolType.pen,
        color: Color(0xFF1E2526),
        width: 3,
      ),
      onToolChanged: (_) {},
      fingerPanEnabled: fingerPanEnabled,
      fingerWritingAssistEnabled: writingAssistEnabled,
      onFingerPanChanged: (value) {
        fingerPanEnabled = value;
      },
      onFingerWritingAssistChanged: (value) {
        writingAssistEnabled = value;
      },
    );

    expect(find.byTooltip('Finger writes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-finger-mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finger moves'));
    await tester.pumpAndSettle();
    expect(fingerPanEnabled, isTrue);
    expect(writingAssistEnabled, isTrue);
  });
}
