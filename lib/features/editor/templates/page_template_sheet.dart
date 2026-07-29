import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/templates/page_template_layer.dart';
import 'package:inknest_notes/features/editor/theme/editor_chrome.dart';
import 'package:inknest_notes/features/editor/theme/editor_workspace_tokens.dart';
import 'package:inknest_notes/models/note_page_template.dart';

Future<NotePageTemplate?> showPageTemplateSheet({
  required BuildContext context,
  required NotePageTemplate selectedTemplate,
}) {
  return EditorChrome.showSheet<NotePageTemplate>(
    context: context,
    builder: (context) =>
        _PageTemplateSheet(selectedTemplate: selectedTemplate),
  );
}

class _PageTemplateSheet extends StatelessWidget {
  const _PageTemplateSheet({required this.selectedTemplate});

  final NotePageTemplate selectedTemplate;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columnCount = width >= 700 ? 6 : 3;

    return SizedBox(
      height: width >= 700 ? 300 : 430,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: EditorChromeHeader(
              title: 'Page template',
              subtitle: 'Choose a paper style for this page',
              onClose: () => Navigator.pop(context),
              closeTooltip: 'Close page templates',
            ),
          ),
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
                    isSelected: template == selectedTemplate,
                    onTap: () => Navigator.pop(context, template),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageTemplateTile extends StatelessWidget {
  const _PageTemplateTile({
    required this.template,
    required this.isSelected,
    required this.onTap,
  });

  final NotePageTemplate template;
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
