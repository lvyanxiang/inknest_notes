import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
  });

  final DrawingTool tool;
  final bool fingerPanEnabled;
  final bool fingerWritingAssistEnabled;
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<bool> onFingerPanChanged;
  final ValueChanged<bool> onFingerWritingAssistChanged;
  final VoidCallback onInsertImage;

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
    if (width < 720) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 560),
        backgroundColor: EditorWorkspaceTokens.chrome,
        builder: (context) => panel,
      );
      return;
    }

    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 560),
        backgroundColor: EditorWorkspaceTokens.chrome,
        builder: (context) => panel,
      );
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = renderObject.localToGlobal(Offset.zero, ancestor: overlay);
    final size = renderObject.size;
    const panelWidth = 360.0;
    final left = offset.dx
        .clamp(16.0, math.max(16.0, overlay.size.width - panelWidth - 16))
        .toDouble();
    final top = (offset.dy + size.height + 8)
        .clamp(16.0, math.max(16.0, overlay.size.height - 240))
        .toDouble();

    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x331E2526),
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: EditorWorkspaceTokens.chrome,
                elevation: 8,
                shadowColor: EditorWorkspaceTokens.paperShadow,
                borderRadius: BorderRadius.circular(
                  EditorWorkspaceTokens.chromeRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(width: panelWidth, child: panel),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorWorkspaceTokens.chrome,
      elevation: 1,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 56,
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
              final horizontalPadding = density == _ToolbarDensity.compact
                  ? 4.0
                  : 12.0;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
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
                              unawaited(_showToolProperties(buttonContext));
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
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _PropertyButton(
                          tool: widget.tool,
                          compact: density == _ToolbarDensity.compact,
                          onPressed: _showToolProperties,
                        ),
                      ),
                    ),
                    if (density == _ToolbarDensity.wide)
                      for (final preset in EditorToolbar._favoritePresets)
                        _PresetButton(
                          preset: preset,
                          isSelected: _toolMatches(widget.tool, preset.tool),
                          onPressed: () => _applyTool(preset.tool),
                        )
                    else if (density == _ToolbarDensity.standard)
                      _PresetMenuButton(
                        tool: widget.tool,
                        presets: EditorToolbar._favoritePresets,
                        onSelected: _applyTool,
                      ),
                    const _ToolbarDivider(),
                    _FingerModeMenuButton(
                      fingerPanEnabled: widget.fingerPanEnabled,
                      fingerWritingAssistEnabled:
                          widget.fingerWritingAssistEnabled,
                      showLabel: density != _ToolbarDensity.compact,
                      onFingerPanChanged: widget.onFingerPanChanged,
                      onFingerWritingAssistChanged:
                          widget.onFingerWritingAssistChanged,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ToolbarDensity { wide, standard, compact }

enum _InsertAction { text, image, shape }

enum _FingerMenuAction { writes, moves, toggleWritingAssist }

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
          child: PopupMenuButton<_InsertAction>(
            key: const ValueKey('editor-insert-menu'),
            tooltip: '',
            onSelected: onSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _InsertAction.text,
                height: 48,
                child: _MenuRow(icon: Icons.text_fields, label: 'Text'),
              ),
              PopupMenuItem(
                value: _InsertAction.image,
                height: 48,
                child: _MenuRow(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Image',
                ),
              ),
              PopupMenuItem(
                value: _InsertAction.shape,
                height: 48,
                child: _MenuRow(icon: Icons.category_outlined, label: 'Shape'),
              ),
            ],
            child: IgnorePointer(
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
    final label = _propertySummary(tool, preset);
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
          minWidth: compact ? 48 : 88,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolPreview(tool: tool),
              if (!compact) ...[
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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

  @override
  Widget build(BuildContext context) {
    final activePreset = _matchingPreset(tool);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'Presets',
        child: _DockPopupControl(
          child: PopupMenuButton<DrawingTool>(
            key: const ValueKey('editor-presets-menu'),
            tooltip: '',
            onSelected: onSelected,
            itemBuilder: (context) => [
              for (final preset in presets)
                PopupMenuItem(
                  value: preset.tool,
                  height: 48,
                  child: _MenuRow(
                    icon: preset.icon,
                    label: preset.label,
                    trailing: _ToolPreview(tool: preset.tool),
                  ),
                ),
            ],
            child: IgnorePointer(
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
          ),
        ),
      ),
    );
  }
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
          child: PopupMenuButton<_FingerMenuAction>(
            key: const ValueKey('editor-finger-mode-menu'),
            tooltip: '',
            onSelected: (action) {
              switch (action) {
                case _FingerMenuAction.writes:
                  onFingerPanChanged(false);
                case _FingerMenuAction.moves:
                  onFingerPanChanged(true);
                case _FingerMenuAction.toggleWritingAssist:
                  onFingerWritingAssistChanged(!fingerWritingAssistEnabled);
              }
            },
            itemBuilder: (context) => [
              _FingerModeMenuItem(
                value: _FingerMenuAction.writes,
                icon: Icons.gesture,
                label: 'Finger writes',
                isSelected: !fingerPanEnabled,
              ),
              _FingerModeMenuItem(
                value: _FingerMenuAction.moves,
                icon: Icons.pan_tool_alt,
                label: 'Finger moves',
                isSelected: fingerPanEnabled,
              ),
              if (!fingerPanEnabled) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _FingerMenuAction.toggleWritingAssist,
                  height: 52,
                  child: Row(
                    children: [
                      Icon(
                        fingerWritingAssistEnabled
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 21,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Writing assist'),
                            Text(
                              'Used for completed finger strokes',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            child: IgnorePointer(
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
                    if (showLabel) ...[const SizedBox(width: 6), Text(label)],
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_drop_down, size: 18),
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

class _FingerModeMenuItem extends PopupMenuItem<_FingerMenuAction> {
  _FingerModeMenuItem({
    required super.value,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) : super(
         height: 48,
         child: Row(
           children: [
             Icon(icon, size: 21),
             const SizedBox(width: 12),
             Expanded(child: Text(label)),
             if (isSelected) const Icon(Icons.check, size: 20),
           ],
         ),
       );
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

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ToolPreview(tool: _tool),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close tool properties',
                    icon: const Icon(Icons.close),
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_tool.type == ToolType.lasso)
                const _LassoProperties()
              else ...[
                if (_tool.type == ToolType.pen ||
                    _tool.type == ToolType.highlighter) ...[
                  Text('Style', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SettingChoice(
                        key: const ValueKey('writing-style-pen'),
                        label: 'Pen',
                        icon: Icons.edit,
                        isSelected: _tool.type == ToolType.pen,
                        onPressed: () => _selectWritingStyle(ToolType.pen),
                      ),
                      _SettingChoice(
                        key: const ValueKey('writing-style-highlighter'),
                        label: 'Highlighter',
                        icon: Icons.border_color,
                        isSelected: _tool.type == ToolType.highlighter,
                        onPressed: () =>
                            _selectWritingStyle(ToolType.highlighter),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Presets', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in widget.presets)
                        _SheetPresetButton(
                          preset: preset,
                          isSelected: _toolMatches(_tool, preset.tool),
                          onPressed: () => _apply(preset.tool),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (_tool.type == ToolType.eraser) ...[
                  Text('Eraser mode', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const _SelectedSettingRow(
                    icon: Icons.auto_fix_off_outlined,
                    title: 'Whole-stroke eraser',
                    subtitle: 'Removes a complete stroke when touched',
                  ),
                  const SizedBox(height: 20),
                ],
                if (_tool.type == ToolType.shape) ...[
                  Text('Shape', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final shapeType in NoteShapeType.values)
                        _SettingChoice(
                          key: ValueKey('shape-${shapeType.name}'),
                          label: _shapeLabel(shapeType),
                          icon: _shapeIcon(shapeType),
                          isSelected: _tool.shapeType == shapeType,
                          onPressed: () =>
                              _apply(_tool.copyWith(shapeType: shapeType)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (supportsColor) ...[
                  Text('Color', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in _colors)
                        _ColorSettingButton(
                          namedColor: color,
                          isSelected: _tool.color == color.color,
                          onPressed: () =>
                              _apply(_tool.copyWith(color: color.color)),
                        ),
                    ],
                  ),
                ],
                if (widths.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    _tool.type == ToolType.eraser ? 'Size' : 'Width',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final width in widths)
                        _SettingChoice(
                          key: ValueKey('tool-width-$width'),
                          label: '${_formatWidth(width)} pt',
                          icon: null,
                          preview: _StrokeWidthPreview(
                            color: _tool.type == ToolType.eraser
                                ? theme.colorScheme.onSurface
                                : _tool.color,
                            width: width,
                          ),
                          isSelected: _tool.width == width,
                          onPressed: () => _apply(_tool.copyWith(width: width)),
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

class _LassoProperties extends StatelessWidget {
  const _LassoProperties();

  @override
  Widget build(BuildContext context) {
    return const _SelectedSettingRow(
      icon: Icons.gesture,
      title: 'Ink-only selection',
      subtitle: 'Draw around handwriting, then use its contextual actions.',
    );
  }
}

class _SheetPresetButton extends StatelessWidget {
  const _SheetPresetButton({
    required this.preset,
    required this.isSelected,
    required this.onPressed,
  });

  final _FavoriteToolPreset preset;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      label: '${preset.label} preset${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: SizedBox(
        width: 156,
        child: _DockControlSurface(
          isSelected: isSelected,
          onTap: onPressed,
          minWidth: 156,
          child: Row(
            children: [
              _ToolPreview(tool: preset.tool),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingChoice extends StatelessWidget {
  const _SettingChoice({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
    this.preview,
  });

  final String label;
  final IconData? icon;
  final Widget? preview;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      label: '$label${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: _DockControlSurface(
        isSelected: isSelected,
        onTap: onPressed,
        minWidth: 80,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...switch (preview) {
              null => const <Widget>[],
              final preview => <Widget>[preview],
            },
            ...switch (icon) {
              null => const <Widget>[],
              final icon => <Widget>[Icon(icon, size: 20)],
            },
            if (preview != null || icon != null) const SizedBox(width: 7),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _ColorSettingButton extends StatelessWidget {
  const _ColorSettingButton({
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
      child: _DockControlSurface(
        isSelected: isSelected,
        onTap: onPressed,
        minWidth: 92,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: namedColor.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: const SizedBox.square(dimension: 20),
            ),
            const SizedBox(width: 8),
            Text(namedColor.name),
            if (isSelected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 18),
            ],
          ],
        ),
      ),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFDCEEEE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 12),
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
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.check),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        ...switch (trailing) {
          null => const <Widget>[],
          final trailing => <Widget>[trailing],
        },
      ],
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
