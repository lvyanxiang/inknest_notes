import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inknest_notes/features/editor/theme/editor_workspace_tokens.dart';

/// Shared chrome surfaces for editor popovers, menus, and sheets.
class EditorChrome {
  const EditorChrome._();

  static ShapeBorder get shape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(EditorWorkspaceTokens.chromeRadius),
    side: const BorderSide(color: EditorWorkspaceTokens.divider),
  );

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: EditorWorkspaceTokens.chrome,
    borderRadius: BorderRadius.circular(EditorWorkspaceTokens.chromeRadius),
    border: Border.all(color: EditorWorkspaceTokens.divider),
    boxShadow: const [
      BoxShadow(
        color: EditorWorkspaceTokens.paperShadow,
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );

  static Widget material({
    required Widget child,
    double elevation = 10,
    Clip clipBehavior = Clip.antiAlias,
  }) {
    return Material(
      color: EditorWorkspaceTokens.chrome,
      elevation: elevation,
      shadowColor: EditorWorkspaceTokens.paperShadow,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: clipBehavior,
      child: child,
    );
  }

  /// Anchored floating card above a translucent barrier (like presets).
  static Future<T?> showAnchoredPopover<T>({
    required BuildContext anchorContext,
    required WidgetBuilder builder,
    double width = 280,
    double estimatedHeight = 240,
    double gap = 8,
  }) {
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    final renderObject = anchorContext.findRenderObject();
    if (overlay == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return Future<T?>.value();
    }

    final offset = renderObject.localToGlobal(Offset.zero, ancestor: overlay);
    final size = renderObject.size;
    final left = offset.dx
        .clamp(16.0, math.max(16.0, overlay.size.width - width - 16))
        .toDouble();
    final top = (offset.dy + size.height + gap)
        .clamp(16.0, math.max(16.0, overlay.size.height - estimatedHeight))
        .toDouble();

    return showDialog<T>(
      context: anchorContext,
      barrierColor: const Color(0x221E2526),
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: material(
                child: SizedBox(width: width, child: builder(dialogContext)),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<T?> showSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool showDragHandle = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      showDragHandle: showDragHandle,
      backgroundColor: EditorWorkspaceTokens.chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EditorWorkspaceTokens.chromeRadius),
        ),
      ),
      builder: builder,
    );
  }
}

class EditorChromeHeader extends StatelessWidget {
  const EditorChromeHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    this.closeTooltip = 'Close',
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: EditorWorkspaceTokens.ink,
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                tooltip: closeTooltip,
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class EditorChromeActionTile extends StatelessWidget {
  const EditorChromeActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.enabled = true,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = enabled
        ? (isSelected
              ? EditorWorkspaceTokens.primary
              : EditorWorkspaceTokens.ink)
        : theme.disabledColor;

    return Material(
      color: isSelected
          ? EditorWorkspaceTokens.selectedFill
          : Colors.transparent,
      borderRadius: BorderRadius.circular(EditorWorkspaceTokens.controlRadius),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(
          EditorWorkspaceTokens.controlRadius,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: subtitle == null ? 10 : 8,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check,
                  size: 18,
                  color: EditorWorkspaceTokens.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditorChromeIconTile extends StatelessWidget {
  const EditorChromeIconTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: EditorWorkspaceTokens.paper,
      borderRadius: BorderRadius.circular(EditorWorkspaceTokens.controlRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          EditorWorkspaceTokens.controlRadius,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              EditorWorkspaceTokens.controlRadius,
            ),
            border: Border.all(color: EditorWorkspaceTokens.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: EditorWorkspaceTokens.ink),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: EditorWorkspaceTokens.ink,
                    fontWeight: FontWeight.w600,
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
