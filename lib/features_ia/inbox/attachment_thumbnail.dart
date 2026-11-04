// Thumbnail of an attached image that opens it full screen (T002). Owner: w-inbox.
import 'dart:io';

import 'package:flutter/material.dart';

/// Tag of the receipt photo that flies from the inbox list to the review page.
Object inboxPhotoHeroTag(String itemId) => 'inbox-photo-$itemId';

class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail({
    super.key,
    required this.path,
    this.size = 72,
    this.radius = 16,
    this.heroTag,
    this.opensFullScreen = true,
  });

  final String path;
  final double size;
  final double radius;

  /// Makes the photo a Hero, so it flies between the list and the review.
  final Object? heroTag;

  /// False in lists, where the whole card is the tap target.
  final bool opensFullScreen;

  @override
  Widget build(BuildContext context) {
    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: _broken,
      ),
    );

    if (heroTag != null) image = Hero(tag: heroTag!, child: image);

    if (!opensFullScreen) return image;

    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  child: Image.file(File(path), errorBuilder: _broken),
                ),
              ),
              const SafeArea(child: CloseButton()),
            ],
          ),
        ),
      ),
      child: image,
    );
  }

  Widget _broken(BuildContext context, Object error, StackTrace? stackTrace) =>
      SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.broken_image_outlined),
      );
}
