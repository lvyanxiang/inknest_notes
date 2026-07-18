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
    this.onCreateTextBox,
    this.activeTextBoxId,
    this.highlightedTextBoxId,
  });

  final NotePage page;
  final ValueChanged<Offset>? onCreateTextBox;
  final ValueChanged<NoteTextBox> onTextBoxChanged;
  final ValueChanged<String> onTextBoxDeleted;
  final String? activeTextBoxId;
  final String? highlightedTextBoxId;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (onCreateTextBox != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (details) => onCreateTextBox!(details.localPosition),
            ),
          ),
        for (final textBox in page.textBoxes)
          Positioned(
            left: textBox.position.dx,
            top: textBox.position.dy,
            width: textBox.width,
            child: _EditableTextBox(
              key: ValueKey('text-box-${textBox.id}'),
              page: page,
              textBox: textBox,
              autofocus: textBox.id == activeTextBoxId,
              isSearchHighlighted: textBox.id == highlightedTextBoxId,
              onChanged: onTextBoxChanged,
              onDeleted: onTextBoxDeleted,
            ),
          ),
      ],
    );
  }
}

class _EditableTextBox extends StatefulWidget {
  const _EditableTextBox({
    super.key,
    required this.page,
    required this.textBox,
    required this.autofocus,
    required this.isSearchHighlighted,
    required this.onChanged,
    required this.onDeleted,
  });

  final NotePage page;
  final NoteTextBox textBox;
  final bool autofocus;
  final bool isSearchHighlighted;
  final ValueChanged<NoteTextBox> onChanged;
  final ValueChanged<String> onDeleted;

  @override
  State<_EditableTextBox> createState() => _EditableTextBoxState();
}

class _EditableTextBoxState extends State<_EditableTextBox> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.textBox.text);
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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _moveBy(Offset delta) {
    final position = widget.textBox.position + delta;
    final maxX = math.max(0.0, widget.page.width - widget.textBox.width);
    final maxY = math.max(0.0, widget.page.height - 64);
    widget.onChanged(
      widget.textBox.copyWith(
        position: Offset(
          position.dx.clamp(0, maxX).toDouble(),
          position.dy.clamp(0, maxY).toDouble(),
        ),
      ),
    );
  }

  void _toggleStyle() {
    final style = widget.textBox.style == NoteTextBoxStyle.handwriting
        ? NoteTextBoxStyle.regular
        : NoteTextBoxStyle.handwriting;
    widget.onChanged(widget.textBox.copyWith(style: style));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isHandwriting = widget.textBox.style == NoteTextBoxStyle.handwriting;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        key: widget.isSearchHighlighted
            ? ValueKey('text-box-search-highlight-${widget.textBox.id}')
            : null,
        decoration: BoxDecoration(
          color: widget.isSearchHighlighted
              ? const Color(0xFFFFF3BF).withValues(alpha: 0.96)
              : colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: widget.isSearchHighlighted
                ? const Color(0xFFF57F17)
                : colorScheme.primary,
            width: widget.isSearchHighlighted ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isSearchHighlighted
                  ? const Color(0x55F9A825)
                  : const Color(0x1A000000),
              blurRadius: widget.isSearchHighlighted ? 12 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Tooltip(
                    message: 'Move text box',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) => _moveBy(details.delta),
                      child: const SizedBox.square(
                        dimension: 28,
                        child: Icon(Icons.open_with, size: 16),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: isHandwriting ? 'Plain text' : 'Handwriting style',
                    onPressed: _toggleStyle,
                    icon: Icon(
                      isHandwriting ? Icons.text_fields : Icons.draw_outlined,
                      size: 16,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: 'Delete text box',
                    onPressed: () => widget.onDeleted(widget.textBox.id),
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            TextField(
              key: ValueKey('text-box-field-${widget.textBox.id}'),
              controller: _controller,
              autofocus: widget.autofocus,
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(10, 4, 10, 10),
              ),
              style: noteTextBoxTextStyle(widget.textBox),
              onChanged: (text) {
                widget.onChanged(widget.textBox.copyWith(text: text));
              },
            ),
          ],
        ),
      ),
    );
  }
}
