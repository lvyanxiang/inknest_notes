import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/templates/page_template_layer.dart';
import 'package:inknest_notes/features/editor/theme/editor_chrome.dart';
import 'package:inknest_notes/features/editor/theme/editor_workspace_tokens.dart';
import 'package:inknest_notes/models/note_page_template.dart';
import 'package:inknest_notes/models/note_page_size.dart';

class PageSetupSelection {
  const PageSetupSelection({
    required this.template,
    required this.sizePreset,
    required this.orientation,
  });

  final NotePageTemplate template;
  final NotePageSizePreset sizePreset;
  final NotePageOrientation orientation;

  Size get pageSize => sizePreset.sizeFor(orientation);
}

Future<PageSetupSelection?> showPageTemplateSheet({
  required BuildContext context,
  required NotePageTemplate selectedTemplate,
  NotePageSizePreset selectedSize = NotePageSizePreset.a4,
  NotePageOrientation selectedOrientation = NotePageOrientation.portrait,
  String title = 'Page template',
  String subtitle = 'Choose a size, orientation, and style',
}) {
  return EditorChrome.showSheet<PageSetupSelection>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PageTemplateSheet(
      selectedTemplate: selectedTemplate,
      selectedSize: selectedSize,
      selectedOrientation: selectedOrientation,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _PageTemplateSheet extends StatefulWidget {
  const _PageTemplateSheet({
    required this.selectedTemplate,
    required this.selectedSize,
    required this.selectedOrientation,
    required this.title,
    required this.subtitle,
  });

  final NotePageTemplate selectedTemplate;
  final NotePageSizePreset selectedSize;
  final NotePageOrientation selectedOrientation;
  final String title;
  final String subtitle;

  @override
  State<_PageTemplateSheet> createState() => _PageTemplateSheetState();
}

class _PageTemplateSheetState extends State<_PageTemplateSheet> {
  late NotePageSizePreset _selectedSize;
  late NotePageOrientation _selectedOrientation;

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.selectedSize;
    _selectedOrientation = widget.selectedOrientation;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final columnCount = width >= 700 ? 6 : 3;
    final pageSize = _selectedSize.sizeFor(_selectedOrientation);

    return SizedBox(
      height: math.min(width >= 700 ? 430 : 600, height * 0.9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: EditorChromeHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              onClose: () => Navigator.pop(context),
              closeTooltip: 'Close paper styles',
            ),
          ),
          _PaperSetupControls(
            selectedSize: _selectedSize,
            selectedOrientation: _selectedOrientation,
            onSizeChanged: (size) {
              setState(() {
                _selectedSize = size;
              });
            },
            onOrientationChanged: (orientation) {
              setState(() {
                _selectedOrientation = orientation;
              });
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              crossAxisCount: columnCount,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                for (final template in NotePageTemplate.values)
                  _PageTemplateTile(
                    template: template,
                    pageSize: pageSize,
                    isSelected: template == widget.selectedTemplate,
                    onTap: () => Navigator.pop(
                      context,
                      PageSetupSelection(
                        template: template,
                        sizePreset: _selectedSize,
                        orientation: _selectedOrientation,
                      ),
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

class _PaperSetupControls extends StatelessWidget {
  const _PaperSetupControls({
    required this.selectedSize,
    required this.selectedOrientation,
    required this.onSizeChanged,
    required this.onOrientationChanged,
  });

  final NotePageSizePreset selectedSize;
  final NotePageOrientation selectedOrientation;
  final ValueChanged<NotePageSizePreset> onSizeChanged;
  final ValueChanged<NotePageOrientation> onOrientationChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paper size',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: EditorWorkspaceTokens.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in NotePageSizePreset.values)
                ChoiceChip(
                  key: ValueKey('page-size-${size.name}'),
                  label: Text(size.label),
                  selected: size == selectedSize,
                  onSelected: (_) => onSizeChanged(size),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedSize.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SegmentedButton<NotePageOrientation>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: NotePageOrientation.portrait,
                    icon: Icon(Icons.stay_current_portrait, size: 18),
                    tooltip: 'Portrait paper',
                  ),
                  ButtonSegment(
                    value: NotePageOrientation.landscape,
                    icon: Icon(Icons.stay_current_landscape, size: 18),
                    tooltip: 'Landscape paper',
                  ),
                ],
                selected: {selectedOrientation},
                onSelectionChanged: (selection) {
                  onOrientationChanged(selection.first);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PageTemplateTile extends StatelessWidget {
  const _PageTemplateTile({
    required this.template,
    required this.pageSize,
    required this.isSelected,
    required this.onTap,
  });

  final NotePageTemplate template;
  final Size pageSize;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? EditorWorkspaceTokens.selectedFill
          : EditorWorkspaceTokens.paper,
      borderRadius: BorderRadius.circular(EditorWorkspaceTokens.controlRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('page-template-${template.name}'),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              EditorWorkspaceTokens.controlRadius,
            ),
            border: Border.all(
              color: isSelected
                  ? EditorWorkspaceTokens.primary
                  : EditorWorkspaceTokens.divider,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: pageSize.width / pageSize.height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE4DED1)),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PageTemplateLayer(template: template),
                            if (isSelected)
                              const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.check_circle,
                                    color: EditorWorkspaceTokens.primary,
                                    size: 20,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  template.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: EditorWorkspaceTokens.ink,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
