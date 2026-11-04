import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// The name the app seeds before the user picks one.
const defaultUserName = 'User';

/// Greeting for the hour of [now].
String welcomeGreeting(Translations t, DateTime now) {
  return switch (now.hour) {
    >= 6 && < 12 => t.home.welcome_back_morning,
    >= 12 && < 19 => t.home.welcome_back_afternoon,
    >= 19 && < 23 => t.home.welcome_back_evening,
    _ => t.home.welcome_back_night,
  };
}

/// The name to show next to the greeting, or null when there is nothing worth
/// showing: blank, or still the seeded default.
String? displayableUserName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == defaultUserName) {
    return null;
  }

  return trimmed;
}

/// Avatar, time-of-day greeting, the user name when there is one, and Chanchi
/// on the right (it hops once when it appears).
class DashboardGreeting extends StatelessWidget {
  const DashboardGreeting({
    super.key,
    required this.greeting,
    required this.avatar,
    required this.onTap,
    this.userName,
    this.animateMascot = true,
  });

  /// False paints Chanchi still (goldens).
  final bool animateMascot;
  final String greeting;
  final String? userName;
  final Widget avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = displayableUserName(userName);

    return PressScale(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: BrandTokens.buttonHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          greeting,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: name == null
                              ? textTheme.titleLarge
                              : textTheme.labelMedium,
                        ),
                        if (name != null)
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleLarge,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChanchiMascot(
                    mood: ChanchiMood.idle,
                    size: 36,
                    animate: animateMascot,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
