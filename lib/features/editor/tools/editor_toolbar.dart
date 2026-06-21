import 'package:flutter/material.dart';
import 'package:inknest_notes/models/note_shape.dart';
import 'package:inknest_notes/models/tool.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.tool,
    required this.fingerPanEnabled,
    required this.onToolChanged,
    required this.onFingerPanChanged,
    required this.onInsertImage,
  });

  final DrawingTool tool;
  final bool fingerPanEnabled;
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<bool> onFingerPanChanged;
  final VoidCallback onInsertImage;

  static const _colors = [
    Color(0xFF1E2526),
    Color(0xFF2F6F73),
    Color(0xFFC24B3A),
    Color(0xFFB98A16),
  ];

  static const _widths = [3.0, 5.0, 8.0];

  static const _favoritePresets = [
    _FavoriteToolPreset(
      label: 'Favorite black pen',
      tool: DrawingTool(type: ToolType.pen, color: Color(0xFF1E2526), width: 3),
      icon: Icons.edit,
    ),
    _FavoriteToolPreset(
      label: 'Favorite teal pen',
      tool: DrawingTool(type: ToolType.pen, color: Color(0xFF2F6F73), width: 5),
      icon: Icons.edit,
    ),
    _FavoriteToolPreset(
      label: 'Favorite red pen',
      tool: DrawingTool(type: ToolType.pen, color: Color(0xFFC24B3A), width: 5),
      icon: Icons.edit,
    ),
    _FavoriteToolPreset(
      label: 'Favorite yellow highlighter',
      tool: DrawingTool(
        type: ToolType.highlighter,
        color: Color(0xFFB98A16),
        width: 12,
      ),
      icon: Icons.border_color,
    ),
  ];

  void _selectTool(ToolType type) {
    final width = switch (type) {
      ToolType.pen => tool.width,
      ToolType.highlighter => tool.width < 8 ? 12.0 : tool.width,
      ToolType.eraser => tool.width < 16 ? 24.0 : tool.width,
      ToolType.text => tool.width,
      ToolType.smartInk => tool.width,
      ToolType.shape => tool.width,
    };

    onToolChanged(tool.copyWith(type: type, width: width));
  }

  void _selectColor(Color color) {
    onToolChanged(tool.copyWith(color: color));
  }

  void _selectWidth(double width) {
    onToolChanged(tool.copyWith(width: width));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              _ToolButton(
                icon: Icons.edit,
                label: 'Pen',
                isSelected: tool.type == ToolType.pen,
                onPressed: () => _selectTool(ToolType.pen),
              ),
              _ToolButton(
                icon: Icons.border_color,
                label: 'Highlighter',
                isSelected: tool.type == ToolType.highlighter,
                onPressed: () => _selectTool(ToolType.highlighter),
              ),
              _ToolButton(
                icon: Icons.cleaning_services,
                label: 'Eraser',
                isSelected: tool.type == ToolType.eraser,
                onPressed: () => _selectTool(ToolType.eraser),
              ),
              _ToolButton(
                icon: Icons.text_fields,
                label: 'Text',
                isSelected: tool.type == ToolType.text,
                onPressed: () => _selectTool(ToolType.text),
              ),
              _ToolButton(
                icon: Icons.auto_fix_high,
                label: 'Smart Ink',
                isSelected: tool.type == ToolType.smartInk,
                onPressed: () => _selectTool(ToolType.smartInk),
              ),
              _ToolButton(
                icon: _shapeIcon(tool.shapeType),
                label: 'Shape',
                isSelected: tool.type == ToolType.shape,
                onPressed: () => _selectTool(ToolType.shape),
              ),
              _ShapeMenuButton(
                shapeType: tool.shapeType,
                onSelected: (shapeType) {
                  onToolChanged(
                    tool.copyWith(type: ToolType.shape, shapeType: shapeType),
                  );
                },
              ),
              const _ToolbarDivider(),
              _ModeButton(
                icon: Icons.pan_tool_alt,
                label: 'Finger pan',
                isSelected: fingerPanEnabled,
                onPressed: () => onFingerPanChanged(!fingerPanEnabled),
              ),
              const _ToolbarDivider(),
              for (final color in _colors)
                _ColorButton(
                  color: color,
                  isSelected: tool.color == color,
                  onPressed: () => _selectColor(color),
                ),
              const _ToolbarDivider(),
              for (final width in _widths)
                _WidthButton(
                  width: width,
                  isSelected: tool.width == width,
                  onPressed: () => _selectWidth(width),
                ),
              const _ToolbarDivider(),
              _CommandButton(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Insert image',
                onPressed: onInsertImage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditorFavoriteToolbar extends StatelessWidget {
  const EditorFavoriteToolbar({
    super.key,
    required this.tool,
    required this.onToolChanged,
  });

  final DrawingTool tool;
  final ValueChanged<DrawingTool> onToolChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.94),
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preset in EditorToolbar._favoritePresets)
              _FavoriteToolButton(
                preset: preset,
                isSelected: _toolMatches(tool, preset.tool),
                onPressed: () => onToolChanged(preset.tool),
              ),
          ],
        ),
      ),
    );
  }
}

bool _toolMatches(DrawingTool a, DrawingTool b) {
  return a.type == b.type &&
      a.color == b.color &&
      a.width == b.width &&
      a.shapeType == b.shapeType;
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

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: label,
        child: IconButton.filledTonal(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: Icon(icon),
          selectedIcon: Icon(icon),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _FavoriteToolButton extends StatelessWidget {
  const _FavoriteToolButton({
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
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: preset.label,
        child: IconButton.filledTonal(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: _FavoriteToolPreview(preset: preset, isSelected: isSelected),
          selectedIcon: _FavoriteToolPreview(
            preset: preset,
            isSelected: isSelected,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 42, height: 36),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _FavoriteToolPreview extends StatelessWidget {
  const _FavoriteToolPreview({required this.preset, required this.isSelected});

  final _FavoriteToolPreset preset;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isSelected
        ? colorScheme.primary
        : colorScheme.onSecondaryContainer;

    return SizedBox.square(
      dimension: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: Icon(preset.icon, size: 18, color: iconColor)),
          Positioned(
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: preset.tool.color,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 1.5),
              ),
              child: const SizedBox.square(dimension: 11),
            ),
          ),
          Positioned(
            left: 4,
            right: 13,
            bottom: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: preset.tool.color,
                borderRadius: BorderRadius.circular(2),
              ),
              child: SizedBox(
                height: _favoriteStrokePreviewHeight(preset.tool),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _favoriteStrokePreviewHeight(DrawingTool tool) {
  return switch (tool.type) {
    ToolType.highlighter => 5,
    _ => tool.width.clamp(2, 5).toDouble(),
  };
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: label,
        child: IconButton.filledTonal(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: Icon(icon),
          selectedIcon: Icon(icon),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: label,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _ShapeMenuButton extends StatelessWidget {
  const _ShapeMenuButton({required this.shapeType, required this.onSelected});

  final NoteShapeType shapeType;
  final ValueChanged<NoteShapeType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: PopupMenuButton<NoteShapeType>(
        tooltip: 'Shape type',
        initialValue: shapeType,
        onSelected: onSelected,
        itemBuilder: (context) {
          return [
            for (final value in NoteShapeType.values)
              PopupMenuItem(
                value: value,
                child: Row(
                  children: [
                    Icon(_shapeIcon(value), size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_shapeLabel(value))),
                  ],
                ),
              ),
          ];
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(_shapeIcon(shapeType)),
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.color,
    required this.isSelected,
    required this.onPressed,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: 'Color',
        child: IconButton(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: _ColorDot(color: color, isSelected: isSelected),
          selectedIcon: _ColorDot(color: color, isSelected: isSelected),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _WidthButton extends StatelessWidget {
  const _WidthButton({
    required this.width,
    required this.isSelected,
    required this.onPressed,
  });

  final double width;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: 'Width ${width.toInt()}',
        child: IconButton(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: _WidthPreview(width: width, isSelected: isSelected),
          selectedIcon: _WidthPreview(width: width, isSelected: isSelected),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.isSelected});

  final Color color;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 3,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 18),
        ),
      ),
    );
  }
}

class _WidthPreview extends StatelessWidget {
  const _WidthPreview({required this.width, required this.isSelected});

  final double width;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: 28,
      child: Center(
        child: Container(
          width: 24,
          height: width,
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            borderRadius: BorderRadius.circular(width),
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
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: VerticalDivider(width: 1),
    );
  }
}
