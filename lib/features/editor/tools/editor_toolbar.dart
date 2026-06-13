import 'package:flutter/material.dart';
import 'package:inknest_notes/models/tool.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.tool,
    required this.onToolChanged,
  });

  final DrawingTool tool;
  final ValueChanged<DrawingTool> onToolChanged;

  static const _colors = [
    Color(0xFF1E2526),
    Color(0xFF2F6F73),
    Color(0xFFC24B3A),
    Color(0xFFB98A16),
  ];

  static const _widths = [3.0, 5.0, 8.0];

  void _selectTool(ToolType type) {
    final width = switch (type) {
      ToolType.pen => tool.width,
      ToolType.highlighter => tool.width < 8 ? 12.0 : tool.width,
      ToolType.eraser => tool.width < 16 ? 24.0 : tool.width,
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
            ],
          ),
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: label,
        child: IconButton.filledTonal(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: Icon(icon),
          selectedIcon: Icon(icon),
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
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Color',
        child: IconButton(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: _ColorDot(color: color, isSelected: isSelected),
          selectedIcon: _ColorDot(color: color, isSelected: isSelected),
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
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Width ${width.toInt()}',
        child: IconButton(
          isSelected: isSelected,
          onPressed: onPressed,
          icon: _WidthPreview(width: width, isSelected: isSelected),
          selectedIcon: _WidthPreview(width: width, isSelected: isSelected),
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
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: VerticalDivider(width: 1),
    );
  }
}
