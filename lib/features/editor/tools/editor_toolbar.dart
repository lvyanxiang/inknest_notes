import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/theme/editor_chrome.dart';
import 'package:inknest_notes/features/editor/theme/editor_workspace_tokens.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/tool.dart';

/// The writing-first editor dock.
///
/// The dock deliberately uses a fixed [Row] instead of a horizontally
/// scrolling toolbar. Primary tools remain visible at every supported iPad
/// width, while presets and properties progressively disclose into menus.
class EditorToolbar extends StatefulWidget {
  const EditorToolbar({
    super.key,
    required this.tool,
    required this.fingerPanEnabled,
    required this.fingerWritingAssistEnabled,
    required this.onToolChanged,
    required this.onFingerPanChanged,
    required this.onFingerWritingAssistChanged,
    required this.onInsertImage,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
  });

  final DrawingTool tool;
  final bool fingerPanEnabled;
  final bool fingerWritingAssistEnabled;
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<bool> onFingerPanChanged;
  final ValueChanged<bool> onFingerWritingAssistChanged;
  final VoidCallback onInsertImage;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  static const _favoritePresets = [
    _FavoriteToolPreset(
      label: 'Black pen, 3 pt',
      tool: DrawingTool(type: ToolType.pen, color: Color(0xFF1E2526), width: 3),
      icon: Icons.edit,
    ),
    _FavoriteToolPreset(
      label: 'Teal pen, 5 pt',
      tool: DrawingTool(type: ToolType.pen, color: Color(0xFF2F6F73), width: 5),
      icon: Icons.edit,
    ),
    _FavoriteToolPreset(
      label: 'Red pen, 5 pt',
      tool: DrawingTool(type: ToolType.pen, color: Color(0xFFC24B3A), width: 5),
      icon: Icons.edit,
    ),
    _FavoriteToolPreset(
      label: 'Yellow highlighter, 12 pt',
      tool: DrawingTool(
        type: ToolType.highlighter,
        color: Color(0xFFB98A16),
        width: 12,
      ),
      icon: Icons.border_color,
    ),
  ];

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  late final Map<ToolType, DrawingTool> _lastToolSettings = {
    ToolType.pen: EditorToolbar._favoritePresets[0].tool,
    ToolType.highlighter: EditorToolbar._favoritePresets[3].tool,
    ToolType.eraser: const DrawingTool(
      type: ToolType.eraser,
      color: Color(0xFF1E2526),
      width: 24,
    ),
    ToolType.shape: const DrawingTool(
      type: ToolType.shape,
      color: Color(0xFF1E2526),
      width: 3,
    ),
  };
  ToolType _lastWritingToolType = ToolType.pen;

  @override
  void initState() {
    super.initState();
    _rememberTool(widget.tool);
  }

  @override
  void didUpdateWidget(covariant EditorToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberTool(widget.tool);
  }

  void _rememberTool(DrawingTool tool) {
    if (_lastToolSettings.containsKey(tool.type)) {
      _lastToolSettings[tool.type] = tool;
    }
    if (_isWritingTool(tool.type)) {
      _lastWritingToolType = tool.type;
    }
  }

  void _applyTool(DrawingTool tool) {
    _rememberTool(tool);
    widget.onToolChanged(tool);
  }

  void _selectWritingTool() {
    if (_isWritingTool(widget.tool.type)) {
      return;
    }
    final remembered = _lastToolSettings[_lastWritingToolType];
    _applyTool(remembered ?? EditorToolbar._favoritePresets.first.tool);
  }

  bool _isWritingTool(ToolType type) =>
      type == ToolType.pen || type == ToolType.highlighter;

  void _selectTool(ToolType type) {
    final rememberedTool = _lastToolSettings[type];
    if (rememberedTool != null) {
      _applyTool(rememberedTool);
      return;
    }
    _applyTool(widget.tool.copyWith(type: type));
  }

  void _selectInsertAction(_InsertAction action) {
    switch (action) {
      case _InsertAction.text:
        _selectTool(ToolType.text);
      case _InsertAction.image:
        widget.onInsertImage();
      case _InsertAction.shape:
        _selectTool(ToolType.shape);
    }
  }

  Future<void> _showToolProperties(BuildContext anchorContext) async {
    final panel = _ToolPropertiesSheet(
      initialTool: widget.tool,
      presets: EditorToolbar._favoritePresets,
      onToolChanged: _applyTool,
    );
    final width = MediaQuery.sizeOf(context).width;
    Future<void> showCompactSheet() {
      return EditorChrome.showSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: panel,
        ),
      );
    }

    if (width < 720) {
      await showCompactSheet();
      return;
    }

    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      await showCompactSheet();
      return;
    }

    await EditorChrome.showAnchoredPopover<void>(
      anchorContext: anchorContext,
      width: 300,
      estimatedHeight: 320,
      builder: (_) => panel,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorWorkspaceTokens.chrome,
      elevation: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: EditorWorkspaceTokens.divider, width: 0.5),
            bottom: BorderSide(color: EditorWorkspaceTokens.divider),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: SizedBox(
            height: 52,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final density = switch (constraints.maxWidth) {
                  >= 1100 => _ToolbarDensity.wide,
                  >= 720 => _ToolbarDensity.standard,
                  _ => _ToolbarDensity.compact,
                };
                // Four presets remain visible from the wide breakpoint, but
                // text labels on all five primary tools need more room than a
                // typical 11-inch iPad landscape window provides.
                final showPrimaryLabels = constraints.maxWidth >= 1320;
                final showFingerLabel = density == _ToolbarDensity.wide;
                final showPropertyLabel = density == _ToolbarDensity.wide;
                final horizontalPadding = density == _ToolbarDensity.compact
                    ? 4.0
                    : 10.0;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Align(
                    alignment: density == _ToolbarDensity.compact
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Builder(
                          builder: (buttonContext) {
                            final isWriting = _isWritingTool(widget.tool.type);
                            final writingLabel =
                                widget.tool.type == ToolType.highlighter
                                ? 'Highlighter'
                                : 'Pen';
                            final writingIcon =
                                widget.tool.type == ToolType.highlighter
                                ? Icons.border_color
                                : Icons.edit;
                            return _PrimaryToolButton(
                              key: const ValueKey('editor-writing-tool'),
                              icon: writingIcon,
                              label: writingLabel,
                              isSelected: isWriting,
                              showLabel: showPrimaryLabels,
                              onPressed: () {
                                if (isWriting) {
                                  unawaited(
                                    _showToolProperties(buttonContext),
                                  );
                                  return;
                                }
                                _selectWritingTool();
                              },
                            );
                          },
                        ),
                        _PrimaryToolButton(
                          icon: Icons.cleaning_services_outlined,
                          label: 'Eraser',
                          isSelected: widget.tool.type == ToolType.eraser,
                          showLabel: showPrimaryLabels,
                          onPressed: () => _selectTool(ToolType.eraser),
                        ),
                        _PrimaryToolButton(
                          icon: Icons.select_all,
                          label: 'Lasso',
                          isSelected: widget.tool.type == ToolType.lasso,
                          showLabel: showPrimaryLabels,
                          onPressed: () => _selectTool(ToolType.lasso),
                        ),
                        _InsertMenuButton(
                          isSelected:
                              widget.tool.type == ToolType.text ||
                              widget.tool.type == ToolType.shape,
                          showLabel: showPrimaryLabels,
                          onSelected: _selectInsertAction,
                        ),
                        const _ToolbarDivider(),
                        _PropertyButton(
                          tool: widget.tool,
                          compact: !showPropertyLabel,
                          onPressed: _showToolProperties,
                        ),
                        if (density == _ToolbarDensity.wide)
                          for (final preset in EditorToolbar._favoritePresets)
                            _PresetButton(
                              preset: preset,
                              isSelected: _toolMatches(
                                widget.tool,
                                preset.tool,
                              ),
                              onPressed: () => _applyTool(preset.tool),
                            )
                        else if (density == _ToolbarDensity.standard)
                          _PresetMenuButton(
                            tool: widget.tool,
                            presets: EditorToolbar._favoritePresets,
                            onSelected: _applyTool,
                          ),
                        if (widget.onUndo != null || widget.onRedo != null) ...[
                          const _ToolbarDivider(),
                          IconButton(
                            onPressed: widget.canUndo ? widget.onUndo : null,
                            tooltip: 'Undo ink stroke',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: EditorWorkspaceTokens.controlSize,
                              height: EditorWorkspaceTokens.controlSize,
                            ),
                            icon: const Icon(Icons.undo, size: 21),
                          ),
                          IconButton(
                            onPressed: widget.canRedo ? widget.onRedo : null,
                            tooltip: 'Redo ink stroke',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: EditorWorkspaceTokens.controlSize,
                              height: EditorWorkspaceTokens.controlSize,
                            ),
                            icon: const Icon(Icons.redo, size: 21),
                          ),
                        ],
                        const _ToolbarDivider(),
                        _FingerModeMenuButton(
                          fingerPanEnabled: widget.fingerPanEnabled,
                          fingerWritingAssistEnabled:
                              widget.fingerWritingAssistEnabled,
                          showLabel: showFingerLabel,
                          onFingerPanChanged: widget.onFingerPanChanged,
                          onFingerWritingAssistChanged:
                              widget.onFingerWritingAssistChanged,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

enum _ToolbarDensity { wide, standard, compact }

enum _InsertAction { text, image, shape }

enum _SelectionEmphasis { primary, preset, quiet }

class _PrimaryToolButton extends StatelessWidget {
  const _PrimaryToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.showLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final bool showLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: isSelected,
          label: '$label${isSelected ? ', selected' : ''}',
          excludeSemantics: true,
          child: _DockControlSurface(
            isSelected: isSelected,
            emphasis: _SelectionEmphasis.primary,
            onTap: onPressed,
            square: !showLabel,
            minWidth: showLabel ? null : EditorWorkspaceTokens.controlSize,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21),
                if (showLabel) ...[
                  const SizedBox(width: 6),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InsertMenuButton extends StatelessWidget {
  const _InsertMenuButton({
    required this.isSelected,
    required this.showLabel,
    required this.onSelected,
  });

  final bool isSelected;
  final bool showLabel;
  final ValueChanged<_InsertAction> onSelected;

  Future<void> _showInsertPicker(BuildContext anchorContext) async {
    final action = await EditorChrome.showAnchoredPopover<_InsertAction>(
      anchorContext: anchorContext,
      width: 268,
      estimatedHeight: 168,
      builder: (dialogContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EditorChromeHeader(
                title: 'Insert',
                subtitle: 'Add content to this page',
                onClose: () => Navigator.of(dialogContext).pop(),
                closeTooltip: 'Close insert',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: EditorChromeIconTile(
                      icon: Icons.text_fields,
                      label: 'Text',
                      onTap: () => Navigator.of(
                        dialogContext,
                      ).pop(_InsertAction.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: EditorChromeIconTile(
                      icon: Icons.add_photo_alternate_outlined,
                      label: 'Image',
                      onTap: () => Navigator.of(
                        dialogContext,
                      ).pop(_InsertAction.image),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: EditorChromeIconTile(
                      icon: Icons.category_outlined,
                      label: 'Shape',
                      onTap: () => Navigator.of(
                        dialogContext,
                      ).pop(_InsertAction.shape),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (action != null) {
      onSelected(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Insert',
      child: Semantics(
        button: true,
        selected: isSelected,
        label: 'Insert${isSelected ? ', selected' : ''}',
        excludeSemantics: true,
        child: _DockPopupControl(
          child: Builder(
            builder: (buttonContext) {
              return Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(
                  EditorWorkspaceTokens.controlRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('editor-insert-menu'),
                  onTap: () => unawaited(_showInsertPicker(buttonContext)),
                  borderRadius: BorderRadius.circular(
                    EditorWorkspaceTokens.controlRadius,
                  ),
                  child: _DockControlVisual(
                    isSelected: isSelected,
                    minWidth: showLabel ? null : 48,
                    horizontalPadding: showLabel ? 10 : 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_circle_outline, size: 21),
                        if (showLabel) ...[
                          const SizedBox(width: 6),
                          const Text('Insert'),
                        ],
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PropertyButton extends StatelessWidget {
  const _PropertyButton({
    required this.tool,
    required this.compact,
    required this.onPressed,
  });

  final DrawingTool tool;
  final bool compact;
  final ValueChanged<BuildContext> onPressed;

  @override
  Widget build(BuildContext context) {
    final preset = _matchingPreset(tool);
    final label = _dockPropertySummary(tool, preset);
    final tooltip = '${_toolLabel(tool.type)} properties';

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: '$label. Open ${_toolLabel(tool.type)} properties',
        excludeSemantics: true,
        child: _DockControlSurface(
          key: const ValueKey('editor-tool-properties'),
          isSelected: false,
          onTap: () => onPressed(context),
          minWidth: compact ? 48 : 72,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolPreview(tool: tool),
              if (!compact) ...[
                const SizedBox(width: 7),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(width: 2),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.isSelected,
    required this.onPressed,
  });

  final _FavoriteToolPreset preset;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: preset.label,
        child: Semantics(
          button: true,
          selected: isSelected,
          label: '${preset.label} preset${isSelected ? ', selected' : ''}',
          excludeSemantics: true,
          child: _DockControlSurface(
            key: ValueKey('editor-preset-${preset.label}'),
            isSelected: isSelected,
            emphasis: _SelectionEmphasis.preset,
            onTap: onPressed,
            square: true,
            child: _ToolPreview(tool: preset.tool),
          ),
        ),
      ),
    );
  }
}

class _PresetMenuButton extends StatelessWidget {
  const _PresetMenuButton({
    required this.tool,
    required this.presets,
    required this.onSelected,
  });

  final DrawingTool tool;
  final List<_FavoriteToolPreset> presets;
  final ValueChanged<DrawingTool> onSelected;

  Future<void> _showPresetPicker(BuildContext anchorContext) async {
    await EditorChrome.showAnchoredPopover<void>(
      anchorContext: anchorContext,
      width: 260,
      estimatedHeight: 220,
      builder: (dialogContext) {
        return _PresetPickerPanel(
          tool: tool,
          presets: presets,
          onSelected: (presetTool) {
            onSelected(presetTool);
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePreset = _matchingPreset(tool);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'Presets',
        child: _DockPopupControl(
          child: Builder(
            builder: (buttonContext) {
              return Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(
                  EditorWorkspaceTokens.controlRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('editor-presets-menu'),
                  onTap: () => unawaited(_showPresetPicker(buttonContext)),
                  borderRadius: BorderRadius.circular(
                    EditorWorkspaceTokens.controlRadius,
                  ),
                  child: _DockControlVisual(
                    isSelected: activePreset != null,
                    emphasis: _SelectionEmphasis.preset,
                    minWidth: 48,
                    horizontalPadding: 7,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (activePreset == null)
                          const Icon(Icons.palette_outlined, size: 21)
                        else
                          _ToolPreview(tool: activePreset.tool),
                        const Icon(Icons.arrow_drop_down, size: 17),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PresetPickerPanel extends StatelessWidget {
  const _PresetPickerPanel({
    required this.tool,
    required this.presets,
    required this.onSelected,
  });

  final DrawingTool tool;
  final List<_FavoriteToolPreset> presets;
  final ValueChanged<DrawingTool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorChromeHeader(
            title: 'Presets',
            subtitle: 'Tap a complete pen or highlighter style',
            onClose: () => Navigator.of(context).pop(),
            closeTooltip: 'Close presets',
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: presets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.35,
            ),
            itemBuilder: (context, index) {
              final preset = presets[index];
              final isSelected = _toolMatches(tool, preset.tool);
              return _PresetPickerCard(
                preset: preset,
                isSelected: isSelected,
                onPressed: () => onSelected(preset.tool),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PresetPickerCard extends StatelessWidget {
  const _PresetPickerCard({
    required this.preset,
    required this.isSelected,
    required this.onPressed,
  });

  final _FavoriteToolPreset preset;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final shortLabel = switch (preset.tool.type) {
      ToolType.highlighter => 'Highlighter',
      _ => 'Pen',
    };
    final detail =
        '${_namedColorLabel(preset.tool.color)} · '
        '${_formatWidth(preset.tool.width)} pt';

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${preset.label}${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: Material(
        color: isSelected
            ? EditorWorkspaceTokens.selectedFill
            : EditorWorkspaceTokens.paper,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? EditorWorkspaceTokens.primary
                    : EditorWorkspaceTokens.divider,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ToolPreview(tool: preset.tool),
                    const Spacer(),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: EditorWorkspaceTokens.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: EditorWorkspaceTokens.ink,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

String _namedColorLabel(Color color) {
  const known = <int, String>{
    0xFF1E2526: 'Black',
    0xFF2F6F73: 'Teal',
    0xFFC24B3A: 'Red',
    0xFFB98A16: 'Yellow',
  };
  return known[color.toARGB32()] ?? 'Custom';
}

class _FingerModeMenuButton extends StatelessWidget {
  const _FingerModeMenuButton({
    required this.fingerPanEnabled,
    required this.fingerWritingAssistEnabled,
    required this.showLabel,
    required this.onFingerPanChanged,
    required this.onFingerWritingAssistChanged,
  });

  final bool fingerPanEnabled;
  final bool fingerWritingAssistEnabled;
  final bool showLabel;
  final ValueChanged<bool> onFingerPanChanged;
  final ValueChanged<bool> onFingerWritingAssistChanged;

  Future<void> _showFingerPicker(BuildContext anchorContext) async {
    await EditorChrome.showAnchoredPopover<void>(
      anchorContext: anchorContext,
      width: 280,
      estimatedHeight: fingerPanEnabled ? 168 : 236,
      builder: (dialogContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EditorChromeHeader(
                title: 'Finger',
                subtitle: 'Choose how touch interacts with the page',
                onClose: () => Navigator.of(dialogContext).pop(),
                closeTooltip: 'Close finger mode',
              ),
              const SizedBox(height: 8),
              EditorChromeActionTile(
                icon: Icons.gesture,
                label: 'Finger writes',
                isSelected: !fingerPanEnabled,
                onTap: () {
                  onFingerPanChanged(false);
                  Navigator.of(dialogContext).pop();
                },
              ),
              const SizedBox(height: 4),
              EditorChromeActionTile(
                icon: Icons.pan_tool_alt,
                label: 'Finger moves',
                isSelected: fingerPanEnabled,
                onTap: () {
                  onFingerPanChanged(true);
                  Navigator.of(dialogContext).pop();
                },
              ),
              if (!fingerPanEnabled) ...[
                const SizedBox(height: 8),
                const Divider(height: 1, color: EditorWorkspaceTokens.divider),
                const SizedBox(height: 4),
                EditorChromeActionTile(
                  icon: fingerWritingAssistEnabled
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  label: 'Writing assist',
                  subtitle: 'Used for completed finger strokes',
                  isSelected: fingerWritingAssistEnabled,
                  onTap: () {
                    onFingerWritingAssistChanged(!fingerWritingAssistEnabled);
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = fingerPanEnabled ? 'Finger moves' : 'Finger writes';
    final icon = fingerPanEnabled ? Icons.pan_tool_alt : Icons.gesture;

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: fingerPanEnabled,
        label: fingerPanEnabled
            ? 'Finger moves, selected'
            : 'Finger writes, default',
        excludeSemantics: true,
        child: _DockPopupControl(
          child: Builder(
            builder: (buttonContext) {
              return Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(
                  EditorWorkspaceTokens.controlRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('editor-finger-mode-menu'),
                  onTap: () => unawaited(_showFingerPicker(buttonContext)),
                  borderRadius: BorderRadius.circular(
                    EditorWorkspaceTokens.controlRadius,
                  ),
                  child: _DockControlVisual(
                    isSelected: fingerPanEnabled,
                    emphasis: fingerPanEnabled
                        ? _SelectionEmphasis.primary
                        : _SelectionEmphasis.quiet,
                    minWidth: showLabel ? null : 48,
                    horizontalPadding: showLabel ? 10 : 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 21),
                        if (showLabel) ...[
                          const SizedBox(width: 6),
                          Text(label),
                        ],
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 12),
      child: VerticalDivider(width: 1),
    );
  }
}

class _DockControlSurface extends StatelessWidget {
  const _DockControlSurface({
    super.key,
    required this.isSelected,
    required this.onTap,
    required this.child,
    this.emphasis = _SelectionEmphasis.primary,
    this.minWidth,
    this.horizontalPadding = 10,
    this.square = false,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;
  final _SelectionEmphasis emphasis;
  final double? minWidth;
  final double horizontalPadding;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(EditorWorkspaceTokens.controlRadius);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: EditorWorkspaceTokens.controlInset,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: _DockControlVisual(
            isSelected: isSelected,
            emphasis: emphasis,
            minWidth: minWidth,
            horizontalPadding: horizontalPadding,
            square: square,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DockControlVisual extends StatelessWidget {
  const _DockControlVisual({
    required this.isSelected,
    required this.child,
    this.emphasis = _SelectionEmphasis.primary,
    this.minWidth,
    this.horizontalPadding = 10,
    this.square = false,
  });

  final bool isSelected;
  final Widget child;
  final _SelectionEmphasis emphasis;
  final double? minWidth;
  final double horizontalPadding;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = isSelected && emphasis != _SelectionEmphasis.quiet;
    final fill = switch (emphasis) {
      _SelectionEmphasis.primary when selected =>
        EditorWorkspaceTokens.selectedFill,
      _SelectionEmphasis.preset when selected =>
        EditorWorkspaceTokens.selectedFill.withValues(alpha: 0.45),
      _ => Colors.transparent,
    };
    const size = EditorWorkspaceTokens.controlSize;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: square ? size : null,
      height: size,
      constraints: BoxConstraints(
        minWidth: square ? size : (minWidth ?? size),
        maxWidth: square ? size : double.infinity,
        minHeight: size,
        maxHeight: size,
      ),
      padding: EdgeInsets.symmetric(horizontal: square ? 0 : horizontalPadding),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(
          EditorWorkspaceTokens.controlRadius,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
        child: IconTheme(
          data: IconThemeData(
            color: selected
                ? EditorWorkspaceTokens.primary
                : colorScheme.onSurface,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Keeps popup-menu dock controls the same 40px tile height as ink buttons.
class _DockPopupControl extends StatelessWidget {
  const _DockPopupControl({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: EditorWorkspaceTokens.controlInset,
      ),
      child: child,
    );
  }
}

class _ToolPropertiesSheet extends StatefulWidget {
  const _ToolPropertiesSheet({
    required this.initialTool,
    required this.presets,
    required this.onToolChanged,
  });

  final DrawingTool initialTool;
  final List<_FavoriteToolPreset> presets;
  final ValueChanged<DrawingTool> onToolChanged;

  @override
  State<_ToolPropertiesSheet> createState() => _ToolPropertiesSheetState();
}

class _ToolPropertiesSheetState extends State<_ToolPropertiesSheet> {
  static const _colors = [
    _NamedColor('Black', Color(0xFF1E2526)),
    _NamedColor('Teal', Color(0xFF2F6F73)),
    _NamedColor('Red', Color(0xFFC24B3A)),
    _NamedColor('Yellow', Color(0xFFB98A16)),
  ];

  late DrawingTool _tool = widget.initialTool;
  late DrawingTool _penTool = widget.presets
      .firstWhere((preset) => preset.tool.type == ToolType.pen)
      .tool;
  late DrawingTool _highlighterTool = widget.presets
      .firstWhere((preset) => preset.tool.type == ToolType.highlighter)
      .tool;

  @override
  void initState() {
    super.initState();
    if (_tool.type == ToolType.pen) {
      _penTool = _tool;
    } else if (_tool.type == ToolType.highlighter) {
      _highlighterTool = _tool;
    }
  }

  void _apply(DrawingTool tool) {
    setState(() {
      _tool = tool;
      if (tool.type == ToolType.pen) {
        _penTool = tool;
      } else if (tool.type == ToolType.highlighter) {
        _highlighterTool = tool;
      }
    });
    widget.onToolChanged(tool);
  }

  void _selectWritingStyle(ToolType type) {
    if (type == ToolType.pen) {
      _apply(_penTool);
      return;
    }
    if (type == ToolType.highlighter) {
      _apply(_highlighterTool);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = '${_toolLabel(_tool.type)} settings';
    final supportsColor = switch (_tool.type) {
      ToolType.pen ||
      ToolType.highlighter ||
      ToolType.text ||
      ToolType.shape => true,
      _ => false,
    };
    final widths = _widthChoices(_tool.type);
    final isWriting =
        _tool.type == ToolType.pen || _tool.type == ToolType.highlighter;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _InkSamplePreview(tool: _tool),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: EditorWorkspaceTokens.ink,
                          ),
                        ),
                        Text(
                          _propertySummary(_tool, _matchingPreset(_tool)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close tool properties',
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_tool.type == ToolType.lasso)
                const _LassoProperties()
              else ...[
                if (isWriting) ...[
                  const _PanelSectionLabel('Style'),
                  const SizedBox(height: 6),
                  _StyleSegmentedControl(
                    isPenSelected: _tool.type == ToolType.pen,
                    onPen: () => _selectWritingStyle(ToolType.pen),
                    onHighlighter: () =>
                        _selectWritingStyle(ToolType.highlighter),
                  ),
                  const SizedBox(height: 12),
                  const _PanelSectionLabel('Presets'),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.presets.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.35,
                        ),
                    itemBuilder: (context, index) {
                      final preset = widget.presets[index];
                      return _PresetPickerCard(
                        preset: preset,
                        isSelected: _toolMatches(_tool, preset.tool),
                        onPressed: () => _apply(preset.tool),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_tool.type == ToolType.eraser) ...[
                  const _PanelSectionLabel('Eraser'),
                  const SizedBox(height: 6),
                  const _SelectedSettingRow(
                    icon: Icons.auto_fix_off_outlined,
                    title: 'Whole-stroke eraser',
                    subtitle: 'Removes a complete stroke when touched',
                  ),
                  const SizedBox(height: 12),
                ],
                if (_tool.type == ToolType.shape) ...[
                  const _PanelSectionLabel('Shape'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final shapeType in NoteShapeType.values)
                        _CompactChoiceChip(
                          key: ValueKey('shape-${shapeType.name}'),
                          label: _shapeLabel(shapeType),
                          icon: _shapeIcon(shapeType),
                          isSelected: _tool.shapeType == shapeType,
                          onPressed: () =>
                              _apply(_tool.copyWith(shapeType: shapeType)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (supportsColor) ...[
                  const _PanelSectionLabel('Color'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final color in _colors)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _ColorSwatchButton(
                            namedColor: color,
                            isSelected: _tool.color == color.color,
                            onPressed: () =>
                                _apply(_tool.copyWith(color: color.color)),
                          ),
                        ),
                    ],
                  ),
                ],
                if (widths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PanelSectionLabel(
                    _tool.type == ToolType.eraser ? 'Size' : 'Width',
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var index = 0; index < widths.length; index++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: index == 0 ? 0 : 3,
                              right: index == widths.length - 1 ? 0 : 3,
                            ),
                            child: _WidthChoiceTile(
                              key: ValueKey('tool-width-${widths[index]}'),
                              width: widths[index],
                              color: _tool.type == ToolType.eraser
                                  ? EditorWorkspaceTokens.ink
                                  : _tool.color,
                              isSelected: _tool.width == widths[index],
                              onPressed: () =>
                                  _apply(_tool.copyWith(width: widths[index])),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelSectionLabel extends StatelessWidget {
  const _PanelSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _InkSamplePreview extends StatelessWidget {
  const _InkSamplePreview({required this.tool});

  final DrawingTool tool;

  @override
  Widget build(BuildContext context) {
    final strokeColor = _toolUsesColor(tool.type)
        ? tool.color
        : EditorWorkspaceTokens.ink;
    final strokeWidth = _toolUsesWidth(tool.type)
        ? tool.width.clamp(2, 10).toDouble()
        : 3.0;

    return Container(
      width: 44,
      height: 36,
      decoration: BoxDecoration(
        color: EditorWorkspaceTokens.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EditorWorkspaceTokens.divider),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size(28, 16),
        painter: _InkSamplePainter(
          color: strokeColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _InkSamplePainter extends CustomPainter {
  const _InkSamplePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(1, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.1,
        size.width * 0.55,
        size.height * 0.55,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.95,
        size.width - 1,
        size.height * 0.35,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InkSamplePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

class _StyleSegmentedControl extends StatelessWidget {
  const _StyleSegmentedControl({
    required this.isPenSelected,
    required this.onPen,
    required this.onHighlighter,
  });

  final bool isPenSelected;
  final VoidCallback onPen;
  final VoidCallback onHighlighter;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorWorkspaceTokens.workspace,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EditorWorkspaceTokens.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(
              child: _SegmentButton(
                key: const ValueKey('writing-style-pen'),
                label: 'Pen',
                icon: Icons.edit,
                isSelected: isPenSelected,
                onPressed: onPen,
              ),
            ),
            Expanded(
              child: _SegmentButton(
                key: const ValueKey('writing-style-highlighter'),
                label: 'Highlighter',
                icon: Icons.border_color,
                isSelected: !isPenSelected,
                onPressed: onHighlighter,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: Material(
        color: isSelected ? EditorWorkspaceTokens.paper : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        elevation: isSelected ? 1 : 0,
        shadowColor: EditorWorkspaceTokens.paperShadow,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? EditorWorkspaceTokens.primary
                        : EditorWorkspaceTokens.ink,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isSelected
                            ? EditorWorkspaceTokens.primary
                            : EditorWorkspaceTokens.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.namedColor,
    required this.isSelected,
    required this.onPressed,
  });

  final _NamedColor namedColor;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${namedColor.name}${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: Tooltip(
        message: namedColor.name,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? EditorWorkspaceTokens.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: namedColor.color,
                shape: BoxShape.circle,
                border: Border.all(color: EditorWorkspaceTokens.divider),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: namedColor.color.computeLuminance() > 0.55
                          ? EditorWorkspaceTokens.ink
                          : Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthChoiceTile extends StatelessWidget {
  const _WidthChoiceTile({
    super.key,
    required this.width,
    required this.color,
    required this.isSelected,
    required this.onPressed,
  });

  final double width;
  final Color color;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = '${_formatWidth(width)} pt';
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: isSelected
              ? EditorWorkspaceTokens.selectedFill
              : EditorWorkspaceTokens.paper,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? EditorWorkspaceTokens.primary
                      : EditorWorkspaceTokens.divider,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 22,
                height: width.clamp(2, 12).toDouble(),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactChoiceChip extends StatelessWidget {
  const _CompactChoiceChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      label: '$label${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: Material(
        color: isSelected
            ? EditorWorkspaceTokens.selectedFill
            : EditorWorkspaceTokens.paper,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? EditorWorkspaceTokens.primary
                    : EditorWorkspaceTokens.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LassoProperties extends StatelessWidget {
  const _LassoProperties();

  @override
  Widget build(BuildContext context) {
    return const _SelectedSettingRow(
      icon: Icons.crop_free,
      title: 'Select ink',
      subtitle: 'Drag a box around ink, or tap a stroke, then Beautify.',
    );
  }
}

class _SelectedSettingRow extends StatelessWidget {
  const _SelectedSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: EditorWorkspaceTokens.selectedFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EditorWorkspaceTokens.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: EditorWorkspaceTokens.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolPreview extends StatelessWidget {
  const _ToolPreview({required this.tool});

  final DrawingTool tool;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(_toolIcon(tool), size: 19),
          ),
          if (_toolUsesColor(tool.type))
            Positioned(
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tool.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: const SizedBox.square(dimension: 12),
              ),
            ),
          if (_toolUsesWidth(tool.type))
            Positioned(
              left: 1,
              right: 12,
              bottom: 2,
              child: _StrokeWidthPreview(color: tool.color, width: tool.width),
            ),
        ],
      ),
    );
  }
}

class _StrokeWidthPreview extends StatelessWidget {
  const _StrokeWidthPreview({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: width.clamp(2, 6).toDouble(),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _FavoriteToolPreset {
  const _FavoriteToolPreset({
    required this.label,
    required this.tool,
    required this.icon,
  });

  final String label;
  final DrawingTool tool;
  final IconData icon;
}

class _NamedColor {
  const _NamedColor(this.name, this.color);

  final String name;
  final Color color;
}

bool _toolMatches(DrawingTool a, DrawingTool b) {
  return a.type == b.type &&
      a.color == b.color &&
      a.width == b.width &&
      a.shapeType == b.shapeType;
}

_FavoriteToolPreset? _matchingPreset(DrawingTool tool) {
  for (final preset in EditorToolbar._favoritePresets) {
    if (_toolMatches(tool, preset.tool)) {
      return preset;
    }
  }
  return null;
}

String _propertySummary(DrawingTool tool, _FavoriteToolPreset? matchingPreset) {
  if (matchingPreset != null) {
    return matchingPreset.label;
  }
  return switch (tool.type) {
    ToolType.pen ||
    ToolType.highlighter => 'Custom · ${_formatWidth(tool.width)} pt',
    ToolType.eraser => '${_formatWidth(tool.width)} pt',
    ToolType.text => 'Text style',
    ToolType.lasso => 'Ink only',
    ToolType.shape =>
      '${_shapeLabel(tool.shapeType)} · ${_formatWidth(tool.width)} pt',
  };
}

/// Compact dock label: color + width instead of long preset phrases.
String _dockPropertySummary(
  DrawingTool tool,
  _FavoriteToolPreset? matchingPreset,
) {
  if (_toolUsesColor(tool.type) && _toolUsesWidth(tool.type)) {
    return '${_namedColorLabel(tool.color)} · ${_formatWidth(tool.width)}';
  }
  return _propertySummary(tool, matchingPreset);
}

String _toolLabel(ToolType type) {
  return switch (type) {
    ToolType.pen => 'Pen',
    ToolType.highlighter => 'Highlighter',
    ToolType.eraser => 'Eraser',
    ToolType.text => 'Text',
    ToolType.lasso => 'Lasso',
    ToolType.shape => 'Shape',
  };
}

IconData _toolIcon(DrawingTool tool) {
  return switch (tool.type) {
    ToolType.pen => Icons.edit,
    ToolType.highlighter => Icons.border_color,
    ToolType.eraser => Icons.cleaning_services_outlined,
    ToolType.text => Icons.text_fields,
    ToolType.lasso => Icons.select_all,
    ToolType.shape => _shapeIcon(tool.shapeType),
  };
}

bool _toolUsesColor(ToolType type) {
  return switch (type) {
    ToolType.pen ||
    ToolType.highlighter ||
    ToolType.text ||
    ToolType.shape => true,
    _ => false,
  };
}

bool _toolUsesWidth(ToolType type) {
  return switch (type) {
    ToolType.pen ||
    ToolType.highlighter ||
    ToolType.eraser ||
    ToolType.shape => true,
    _ => false,
  };
}

List<double> _widthChoices(ToolType type) {
  return switch (type) {
    ToolType.pen => const [1, 3, 5, 8],
    ToolType.highlighter => const [8, 12, 16, 24],
    ToolType.eraser => const [16, 24, 36, 48],
    ToolType.shape => const [2, 3, 5, 8],
    _ => const [],
  };
}

IconData _shapeIcon(NoteShapeType shapeType) {
  return switch (shapeType) {
    NoteShapeType.line => Icons.horizontal_rule,
    NoteShapeType.arrow => Icons.north_east,
    NoteShapeType.rectangle => Icons.check_box_outline_blank,
    NoteShapeType.ellipse => Icons.radio_button_unchecked,
  };
}

String _shapeLabel(NoteShapeType shapeType) {
  return switch (shapeType) {
    NoteShapeType.line => 'Line',
    NoteShapeType.arrow => 'Arrow',
    NoteShapeType.rectangle => 'Rectangle',
    NoteShapeType.ellipse => 'Ellipse',
  };
}

String _formatWidth(double width) {
  return width == width.roundToDouble()
      ? width.toInt().toString()
      : width.toStringAsFixed(1);
}
