// Thumbnail of an attached image that opens it full screen (T002). Owner: w-inbox.
import 'dart:io';

import 'package:flutter/material.dart';

class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail({super.key, required this.path, this.size = 72});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: _broken,
        ),
      ),
    );
  }

  Widget _broken(BuildContext context, Object error, StackTrace? stackTrace) =>
      SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.broken_image_outlined),
      );
}
