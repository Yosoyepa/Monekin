import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/services/user-setting/private_mode_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// Round soft button that toggles the private mode (hides every amount).
class PrivateModeButton extends StatelessWidget {
  const PrivateModeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Translations.of(context).settings.security.private_mode;

    return PressScale(
      child: Material(
        color: BrandColors.of(context).soft,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: BrandTokens.buttonHeight,
            child: StreamBuilder<bool>(
              stream: PrivateModeService.instance.privateModeStream,
              initialData: false,
              builder: (context, snapshot) {
                return Tooltip(
                  message: label,
                  child: Icon(
                    (snapshot.data ?? false)
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                    color: scheme.onSurface,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
