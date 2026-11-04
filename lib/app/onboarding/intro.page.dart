import 'package:flutter/material.dart';
import 'package:monekin/app/onboarding/onboarding.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/core/presentation/app_colors.dart';
import 'package:monekin/core/presentation/widgets/html_text.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

/// First screen of a fresh install: the app name, Chanchi and one line of
/// value. The button leads to the welcome pages.
class IntroPage extends StatelessWidget {
  const IntroPage({super.key, this.onStart, this.animateMascot = true});

  /// Replaces the default exit to the welcome pages.
  final VoidCallback? onStart;

  /// False paints Chanchi still (goldens).
  final bool animateMascot;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final footerStyle = textTheme.bodySmall!;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(BrandTokens.pageMargin),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        ChanchiMascot(
                          mood: ChanchiMood.idle,
                          size: 160,
                          animate: animateMascot,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          t.brand_app.intro_app_name,
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.brand_app.intro_tagline,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(
                            color: BrandColors.of(context).textSecondary,
                          ),
                        ),
                        const SizedBox(height: 40),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed:
                                onStart ??
                                () => RouteUtils.pushRoute(
                                  const OnboardingPage(),
                                  withReplacement: true,
                                ),
                            child: Text(t.brand_app.intro_start),
                          ),
                        ),
                        const SizedBox(height: 24),
                        HTMLText(
                          textAlign: TextAlign.center,
                          htmlString: t.intro.welcome_footer,
                          defaultTextStyle: footerStyle,
                          tags: {
                            'a': footerStyle.copyWith(
                              color: AppColors.of(context).link,
                            ),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
