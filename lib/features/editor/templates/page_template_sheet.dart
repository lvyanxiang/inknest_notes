import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/templates/page_template_layer.dart';
import 'package:inknest_notes/models/note_page_template.dart';

Future<NotePageTemplate?> showPageTemplateSheet({
  required BuildContext context,
  required NotePageTemplate selectedTemplate,
}) {
  return showModalBottomSheet<NotePageTemplate>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Page template',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close page templates',
                  icon: const Icon(Icons.close),
                ),
              ],
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
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('page-template-${template.name}'),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isSelected ? 2.5 : 1,
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
                          Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.check_circle,
                                color: colorScheme.primary,
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
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
