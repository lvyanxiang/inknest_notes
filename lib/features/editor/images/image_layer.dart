import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inknest_notes/models/note_image.dart';
import 'package:inknest_notes/models/note_page.dart';

class ImageLayer extends StatelessWidget {
  const ImageLayer({
    super.key,
    required this.page,
    required this.onImageChanged,
    required this.onImageDeleted,
    this.activeImageId,
    this.showImage = true,
    this.showControls = true,
  });

  final NotePage page;
  final ValueChanged<NoteImage> onImageChanged;
  final ValueChanged<String> onImageDeleted;
  final String? activeImageId;
  final bool showImage;
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final image in page.images)
          Positioned(
            left: image.position.dx,
            top: image.position.dy,
            width: image.width,
            height: image.height,
            child: _EditablePageImage(
              key: ValueKey('page-image-${image.id}'),
              page: page,
              image: image,
              isActive: image.id == activeImageId,
              showImage: showImage,
              showControls: showControls,
              onChanged: onImageChanged,
              onDeleted: onImageDeleted,
            ),
          ),
      ],
    );
  }
}

class _EditablePageImage extends StatelessWidget {
  const _EditablePageImage({
    super.key,
    required this.page,
    required this.image,
    required this.isActive,
    required this.showImage,
    required this.showControls,
    required this.onChanged,
    required this.onDeleted,
  });

  static const _minimumSize = 72.0;

  final NotePage page;
  final NoteImage image;
  final bool isActive;
  final bool showImage;
  final bool showControls;
  final ValueChanged<NoteImage> onChanged;
  final ValueChanged<String> onDeleted;

  void _moveBy(Offset delta) {
    final position = image.position + delta;
    final maxX = math.max(0.0, page.width - image.width);
    final maxY = math.max(0.0, page.height - image.height);

    onChanged(
      image.copyWith(
        position: Offset(
          position.dx.clamp(0, maxX).toDouble(),
          position.dy.clamp(0, maxY).toDouble(),
        ),
      ),
    );
  }

  void _resizeBy(Offset delta) {
    final aspectRatio = image.height <= 0 ? 1.0 : image.width / image.height;
    final widthDeltaFromY = delta.dy * aspectRatio;
    final widthDelta = delta.dx.abs() > widthDeltaFromY.abs()
        ? delta.dx
        : widthDeltaFromY;
    final maxWidth = math.max(_minimumSize, page.width - image.position.dx);
    final maxHeight = math.max(_minimumSize, page.height - image.position.dy);
    var width = (image.width + widthDelta)
        .clamp(_minimumSize, maxWidth)
        .toDouble();
    var height = width / aspectRatio;

    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectRatio;
    }

    onChanged(image.copyWith(width: width, height: height));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isActive
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (showImage || showControls)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: showImage
                      ? const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: showImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.file(
                          File(image.filePath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
        if (showControls) ...[
          Positioned(
            left: 0,
            top: 0,
            child: _ImageHandleButton(
              tooltip: 'Move image',
              icon: Icons.open_with,
              onPanUpdate: (details) => _moveBy(details.delta),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: _ImageIconButton(
              tooltip: 'Delete image',
              icon: Icons.close,
              onPressed: () => onDeleted(image.id),
            ),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: _ImageHandleButton(
              tooltip: 'Resize image',
              icon: Icons.open_in_full,
              onPanUpdate: (details) => _resizeBy(details.delta),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageHandleButton extends StatelessWidget {
  const _ImageHandleButton({
    required this.tooltip,
    required this.icon,
    required this.onPanUpdate,
  });

  final String tooltip;
  final IconData icon;
  final GestureDragUpdateCallback onPanUpdate;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onPanUpdate,
        child: _ImageButtonSurface(icon: icon),
      ),
    );
  }
}

class _ImageIconButton extends StatelessWidget {
  const _ImageIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: _ImageButtonSurface(icon: icon),
      ),
    );
  }
}

class _ImageButtonSurface extends StatelessWidget {
  const _ImageButtonSurface({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SizedBox.square(
        dimension: 28,
        child: Icon(icon, size: 16, color: colorScheme.onSurface),
      ),
    );
  }
}
