import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/text/note_text_box_styles.dart';
import 'package:inknest_notes/models/note_page.dart';
import 'package:inknest_notes/models/note_text_box.dart';

class TextBoxLayer extends StatelessWidget {
  const TextBoxLayer({
    super.key,
    required this.page,
    required this.onTextBoxChanged,
    required this.onTextBoxDeleted,
    required this.onTextBoxSelected,
    required this.onTextBoxEditingStarted,
    required this.onInteractionDismissed,
    required this.onMutationStarted,
    required this.onMutationEnded,
    this.onCreateTextBox,
    this.selectedTextBoxId,
    this.editingTextBoxId,
  });

  static const double _toolbarWidth = 312;
  static const double _toolbarExtent = 52;

  final NotePage page;
  final ValueChanged<Offset>? onCreateTextBox;
  final ValueChanged<NoteTextBox> onTextBoxChanged;
  final ValueChanged<String> onTextBoxDeleted;
  final ValueChanged<String> onTextBoxSelected;
  final ValueChanged<String> onTextBoxEditingStarted;
  final VoidCallback onInteractionDismissed;
  final VoidCallback onMutationStarted;
  final VoidCallback onMutationEnded;
  final String? selectedTextBoxId;
  final String? editingTextBoxId;

  @override
  Widget build(BuildContext context) {
    final interactionEnabled = onCreateTextBox != null;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (interactionEnabled)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('text-box-canvas-interaction'),
              behavior: HitTestBehavior.translucent,
              onTapDown: (details) {
                if (selectedTextBoxId != null || editingTextBoxId != null) {
                  onInteractionDismissed();
                } else {
                  onCreateTextBox!(details.localPosition);
                }
              },
            ),
          ),
        for (final textBox in page.textBoxes)
          _positionedTextBox(textBox, interactionEnabled),
      ],
    );
  }

  Widget _positionedTextBox(NoteTextBox textBox, bool interactionEnabled) {
    final isSelected = textBox.id == selectedTextBoxId;
    final isEditing = textBox.id == editingTextBoxId;
    final showsControls = interactionEnabled && (isSelected || isEditing);
    final toolbarAbove = showsControls && textBox.position.dy >= _toolbarExtent;
    final rootWidth = showsControls
        ? math.max(textBox.width, _toolbarWidth)
        : textBox.width;
    final alignToolbarToRight =
        showsControls && textBox.position.dx + rootWidth > page.width;
    final desiredContentOffsetX = alignToolbarToRight
        ? rootWidth - textBox.width
        : 0.0;
    final rootLeft = math.max(0.0, textBox.position.dx - desiredContentOffsetX);
    final contentOffsetX = textBox.position.dx - rootLeft;
    final rootTop = textBox.position.dy - (toolbarAbove ? _toolbarExtent : 0);

    return Positioned(
      left: rootLeft,
      top: rootTop,
      width: rootWidth,
      child: IgnorePointer(
        ignoring: !interactionEnabled,
        child: _EditableTextBox(
          key: ValueKey('text-box-${textBox.id}'),
          page: page,
          textBox: textBox,
          isSelected: isSelected,
          isEditing: isEditing,
          showsControls: showsControls,
          toolbarAbove: toolbarAbove,
          contentOffsetX: contentOffsetX,
          onSelected: () => onTextBoxSelected(textBox.id),
          onEditingStarted: () => onTextBoxEditingStarted(textBox.id),
          onDismissRequested: onInteractionDismissed,
          onChanged: onTextBoxChanged,
          onDeleted: () => onTextBoxDeleted(textBox.id),
          onMutationStarted: onMutationStarted,
          onMutationEnded: onMutationEnded,
        ),
      ),
    );
  }
}

class _EditableTextBox extends StatefulWidget {
  const _EditableTextBox({
    super.key,
    required this.page,
    required this.textBox,
    required this.isSelected,
    required this.isEditing,
    required this.showsControls,
    required this.toolbarAbove,
    required this.contentOffsetX,
    required this.onSelected,
    required this.onEditingStarted,
    required this.onDismissRequested,
    required this.onChanged,
    required this.onDeleted,
    required this.onMutationStarted,
    required this.onMutationEnded,
  });

  final NotePage page;
  final NoteTextBox textBox;
  final bool isSelected;
  final bool isEditing;
  final bool showsControls;
  final bool toolbarAbove;
  final double contentOffsetX;
  final VoidCallback onSelected;
  final VoidCallback onEditingStarted;
  final VoidCallback onDismissRequested;
  final ValueChanged<NoteTextBox> onChanged;
  final VoidCallback onDeleted;
  final VoidCallback onMutationStarted;
  final VoidCallback onMutationEnded;

  @override
  State<_EditableTextBox> createState() => _EditableTextBoxState();
}

class _EditableTextBoxState extends State<_EditableTextBox> {
  static const double _minimumWidth = 120;

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.textBox.text);
    _focusNode = FocusNode();
    if (widget.isEditing) {
      _requestFocus();
    }
  }

  @override
  void didUpdateWidget(covariant _EditableTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textBox.text != widget.textBox.text &&
        _controller.text != widget.textBox.text) {
      _controller.value = TextEditingValue(
        text: widget.textBox.text,
        selection: TextSelection.collapsed(offset: widget.textBox.text.length),
      );
    }
    if (!oldWidget.isEditing && widget.isEditing) {
      _requestFocus();
    } else if (oldWidget.isEditing && !widget.isEditing) {
      _focusNode.unfocus();
    }
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isEditing) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _moveBy(Offset delta) {
    final position = widget.textBox.position + delta;
    final maxX = math.max(0.0, widget.page.width - widget.textBox.width);
    final maxY = math.max(0.0, widget.page.height - 44);
    widget.onChanged(
      widget.textBox.copyWith(
        position: Offset(
          position.dx.clamp(0, maxX).toDouble(),
          position.dy.clamp(0, maxY).toDouble(),
        ),
      ),
    );
  }

  void _resizeRight(double deltaX) {
    final availableWidth = math.max(
      _minimumWidth,
      widget.page.width - widget.textBox.position.dx,
    );
    final width = (widget.textBox.width + deltaX)
        .clamp(_minimumWidth, availableWidth)
        .toDouble();
    if (width != widget.textBox.width) {
      widget.onChanged(widget.textBox.copyWith(width: width));
    }
  }

  void _resizeLeft(double deltaX) {
    final right = widget.textBox.position.dx + widget.textBox.width;
    final left = (widget.textBox.position.dx + deltaX)
        .clamp(0.0, right - _minimumWidth)
        .toDouble();
    final width = right - left;
    if (left != widget.textBox.position.dx || width != widget.textBox.width) {
      widget.onChanged(
        widget.textBox.copyWith(
          position: Offset(left, widget.textBox.position.dy),
          width: width,
        ),
      );
    }
  }

  void _applyDiscreteChange(NoteTextBox updated) {
    if (updated == widget.textBox) {
      return;
    }
    if (!widget.isEditing) {
      widget.onMutationStarted();
    }
    widget.onChanged(updated);
    if (!widget.isEditing) {
      widget.onMutationEnded();
    }
  }

  void _startControlMutation() {
    if (!widget.isEditing) {
      widget.onMutationStarted();
    }
  }

  void _endControlMutation() {
    if (!widget.isEditing) {
      widget.onMutationEnded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!widget.showsControls) {
      return SizedBox(
        width: widget.textBox.width,
        child: GestureDetector(
          key: ValueKey('text-box-idle-${widget.textBox.id}'),
          behavior: HitTestBehavior.translucent,
          onTap: widget.onSelected,
          child: content,
        ),
      );
    }

    final toolbar = _TextBoxObjectToolbar(
      textBox: widget.textBox,
      isEditing: widget.isEditing,
      onMoveStart: _startControlMutation,
      onMoveUpdate: _moveBy,
      onMoveEnd: _endControlMutation,
      onChanged: _applyDiscreteChange,
      onEdit: widget.onEditingStarted,
      onDone: widget.onDismissRequested,
      onDelete: widget.onDeleted,
    );
    final framedContent = Padding(
      padding: EdgeInsets.only(left: widget.contentOffsetX),
      child: SizedBox(
        width: widget.textBox.width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: widget.isEditing
                    ? Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.08)
                    : Colors.transparent,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: widget.isEditing ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: GestureDetector(
                key: ValueKey('text-box-selected-${widget.textBox.id}'),
                behavior: HitTestBehavior.translucent,
                onTap: widget.isEditing ? null : widget.onEditingStarted,
                child: content,
              ),
            ),
            _ResizeHandle(
              key: ValueKey('text-box-resize-left-${widget.textBox.id}'),
              alignment: Alignment.centerLeft,
              cursor: SystemMouseCursors.resizeLeftRight,
              onStart: _startControlMutation,
              onUpdate: _resizeLeft,
              onEnd: _endControlMutation,
              semanticLabel: 'Resize text box from left',
            ),
            _ResizeHandle(
              key: ValueKey('text-box-resize-right-${widget.textBox.id}'),
              alignment: Alignment.centerRight,
              cursor: SystemMouseCursors.resizeLeftRight,
              onStart: _startControlMutation,
              onUpdate: _resizeRight,
              onEnd: _endControlMutation,
              semanticLabel: 'Resize text box from right',
            ),
          ],
        ),
      ),
    );

    return TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.toolbarAbove
            ? [toolbar, const SizedBox(height: 8), framedContent]
            : [framedContent, const SizedBox(height: 8), toolbar],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final textAlign = noteTextBoxTextAlign(widget.textBox.alignment);
    if (widget.isEditing) {
      return TextField(
        key: ValueKey('text-box-field-${widget.textBox.id}'),
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textAlign: textAlign,
        decoration: const InputDecoration(
          hintText: 'Type text',
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        style: noteTextBoxTextStyle(widget.textBox),
        onChanged: (text) {
          widget.onChanged(widget.textBox.copyWith(text: text));
        },
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            widget.textBox.text,
            textAlign: textAlign,
            style: noteTextBoxTextStyle(widget.textBox),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    super.key,
    required this.alignment,
    required this.cursor,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.semanticLabel,
  });

  final Alignment alignment;
  final MouseCursor cursor;
  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Transform.translate(
          offset: Offset(alignment.x * 14, 0),
          child: Semantics(
            label: semanticLabel,
            child: Tooltip(
              message: semanticLabel,
              child: MouseRegion(
                cursor: cursor,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) => onStart(),
                  onHorizontalDragUpdate: (details) =>
                      onUpdate(details.delta.dx),
                  onHorizontalDragEnd: (_) => onEnd(),
                  onHorizontalDragCancel: onEnd,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const SizedBox.square(dimension: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextBoxObjectToolbar extends StatelessWidget {
  const _TextBoxObjectToolbar({
    required this.textBox,
    required this.isEditing,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onChanged,
    required this.onEdit,
    required this.onDone,
    required this.onDelete,
  });

  static const _fontSizes = <double>[16, 20, 24, 28, 36];
  static const _colors = <_TextColorChoice>[
    _TextColorChoice('Black', Color(0xFF1E2526)),
    _TextColorChoice('Teal', Color(0xFF2D6F73)),
    _TextColorChoice('Red', Color(0xFFC54A4A)),
    _TextColorChoice('Blue', Color(0xFF3568B8)),
  ];

  final NoteTextBox textBox;
  final bool isEditing;
  final VoidCallback onMoveStart;
  final ValueChanged<Offset> onMoveUpdate;
  final VoidCallback onMoveEnd;
  final ValueChanged<NoteTextBox> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDone;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('text-box-toolbar-${textBox.id}'),
      color: colorScheme.surface,
      elevation: 5,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Move text box',
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => onMoveStart(),
                  onPanUpdate: (details) => onMoveUpdate(details.delta),
                  onPanEnd: (_) => onMoveEnd(),
                  onPanCancel: onMoveEnd,
                  child: const SizedBox.square(
                    dimension: 44,
                    child: Icon(Icons.drag_indicator, size: 20),
                  ),
                ),
              ),
            ),
            _fontMenu(),
            _sizeMenu(),
            _colorMenu(),
            _alignmentMenu(),
            _moreMenu(),
            if (isEditing)
              IconButton(
                key: ValueKey('text-box-done-${textBox.id}'),
                tooltip: 'Done editing',
                onPressed: onDone,
                icon: const Icon(Icons.check, size: 20),
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fontMenu() {
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<NoteTextBoxFont>(
        key: ValueKey('text-box-font-menu-${textBox.id}'),
        tooltip: 'Choose font (${noteTextBoxFontLabel(textBox.font)})',
        initialValue: textBox.font,
        onSelected: (font) {
          if (font != textBox.font) {
            onChanged(textBox.copyWith(font: font));
          }
        },
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.font_download_outlined, size: 20),
        itemBuilder: (context) => [
          for (final font in noteTextBoxFontChoices)
            CheckedPopupMenuItem<NoteTextBoxFont>(
              key: ValueKey('text-box-font-${textBox.id}-${font.name}'),
              value: font,
              checked: font == textBox.font,
              child: Text(
                noteTextBoxFontLabel(font),
                style: TextStyle(fontFamily: noteTextBoxFontFamily(font)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sizeMenu() {
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<double>(
        key: ValueKey('text-box-size-menu-${textBox.id}'),
        tooltip: 'Text size ${textBox.fontSize.round()}',
        initialValue: textBox.fontSize,
        onSelected: (size) {
          if (size != textBox.fontSize) {
            onChanged(textBox.copyWith(fontSize: size));
          }
        },
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.format_size, size: 20),
        itemBuilder: (context) => [
          for (final size in _fontSizes)
            CheckedPopupMenuItem<double>(
              key: ValueKey('text-box-size-${textBox.id}-${size.round()}'),
              value: size,
              checked: size == textBox.fontSize,
              child: Text(size.round().toString()),
            ),
        ],
      ),
    );
  }

  Widget _colorMenu() {
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<Color>(
        key: ValueKey('text-box-color-menu-${textBox.id}'),
        tooltip: 'Text color',
        onSelected: (color) {
          if (color != textBox.color) {
            onChanged(textBox.copyWith(color: color));
          }
        },
        padding: EdgeInsets.zero,
        icon: Icon(Icons.circle, size: 20, color: textBox.color),
        itemBuilder: (context) => [
          for (final choice in _colors)
            CheckedPopupMenuItem<Color>(
              key: ValueKey('text-box-color-${textBox.id}-${choice.label}'),
              value: choice.color,
              checked: choice.color == textBox.color,
              child: Row(
                children: [
                  Icon(Icons.circle, size: 18, color: choice.color),
                  const SizedBox(width: 10),
                  Text(choice.label),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _alignmentMenu() {
    final icon = switch (textBox.alignment) {
      NoteTextBoxAlignment.left => Icons.format_align_left,
      NoteTextBoxAlignment.center => Icons.format_align_center,
      NoteTextBoxAlignment.right => Icons.format_align_right,
    };
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<NoteTextBoxAlignment>(
        key: ValueKey('text-box-alignment-menu-${textBox.id}'),
        tooltip: 'Text alignment',
        initialValue: textBox.alignment,
        onSelected: (alignment) {
          if (alignment != textBox.alignment) {
            onChanged(textBox.copyWith(alignment: alignment));
          }
        },
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 20),
        itemBuilder: (context) => [
          for (final alignment in NoteTextBoxAlignment.values)
            CheckedPopupMenuItem<NoteTextBoxAlignment>(
              key: ValueKey(
                'text-box-alignment-${textBox.id}-${alignment.name}',
              ),
              value: alignment,
              checked: alignment == textBox.alignment,
              child: Text(switch (alignment) {
                NoteTextBoxAlignment.left => 'Align left',
                NoteTextBoxAlignment.center => 'Align center',
                NoteTextBoxAlignment.right => 'Align right',
              }),
            ),
        ],
      ),
    );
  }

  Widget _moreMenu() {
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<_TextBoxAction>(
        key: ValueKey('text-box-more-${textBox.id}'),
        tooltip: 'More text box actions',
        onSelected: (action) {
          switch (action) {
            case _TextBoxAction.edit:
              onEdit();
              return;
            case _TextBoxAction.delete:
              onDelete();
              return;
          }
        },
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz, size: 20),
        itemBuilder: (context) => [
          if (!isEditing)
            const PopupMenuItem(
              value: _TextBoxAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit text'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          const PopupMenuItem(
            value: _TextBoxAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete text box'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

enum _TextBoxAction { edit, delete }

class _TextColorChoice {
  const _TextColorChoice(this.label, this.color);

  final String label;
  final Color color;
}
