import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:monekin/app/layout/page_switcher.dart';
import 'package:monekin/app/onboarding/classes/OnboardingItem.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/motion.dart';
import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/core/database/services/currency/currency_service.dart';
import 'package:monekin/core/database/services/user-setting/user_setting_service.dart';
import 'package:monekin/core/models/currency/currency.dart';
import 'package:monekin/core/presentation/animations/animated_expanded.dart';
import 'package:monekin/core/presentation/widgets/currency_selector_modal.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

const _sceneLocal = 'assets/brand/scenes/intro_local.svg';
const _sceneReceipt = 'assets/brand/scenes/intro_receipt.svg';
const _sceneCheck = 'assets/brand/scenes/intro_check.svg';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.onFinished});

  /// Replaces the default exit (mark the intro as seen and open the app).
  final VoidCallback? onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int currentPage = 0;
  PageController pageController = PageController();

  void introFinished() {
    if (widget.onFinished != null) {
      widget.onFinished!();
      return;
    }

    AppDataService.instance
        .setItem(AppDataKey.introSeen, '1', updateGlobalState: true)
        .then((value) {
          RouteUtils.pushRoute(
            PageSwitcher(key: tabsPageKey),
            withReplacement: true,
          );
        });
  }

  void _goToPage(int page) {
    final motion = BrandMotion.of(context);

    // Reduced motion: no sliding, the page is simply there.
    if (motion.reduce) {
      pageController.jumpToPage(page);
      return;
    }

    pageController.animateToPage(
      page,
      duration: motion.page,
      curve: motion.enter,
    );
  }

  @override
  void dispose() {
    pageController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = [
      OnboardingItem(
        header: t.brand_app.intro_local_title,
        description: t.brand_app.intro_local_descr,
        imageAsset: _sceneLocal,
        extraWidget: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: buildCurrencySelectorTile(context),
        ),
      ),
      OnboardingItem(
        header: t.brand_app.intro_receipt_title,
        description: t.brand_app.intro_receipt_descr,
        imageAsset: _sceneReceipt,
      ),
      OnboardingItem(
        header: t.brand_app.intro_check_title,
        description: t.brand_app.intro_check_descr,
        imageAsset: _sceneCheck,
      ),
    ];

    final isInLastPage = currentPage >= items.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Semantics(
                    label: t.brand_app.intro_page_of(
                      current: currentPage + 1,
                      total: items.length,
                    ),
                    child: ExcludeSemantics(
                      child: AnimatedSmoothIndicator(
                        activeIndex: currentPage,
                        count: items.length,
                        duration: BrandMotion.of(context).page,
                        curve: BrandCurves.enter,
                        effect: ExpandingDotsEffect(
                          dotHeight: 8,
                          dotWidth: 8,
                          expansionFactor: 3,
                          spacing: 8,
                          radius: 4,
                          activeDotColor: scheme.primary,
                          dotColor: scheme.outline.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: items.length,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (pageIndex) {
                      setState(() => currentPage = pageIndex);
                    },
                    itemBuilder: (context, index) => _IntroSlide(
                      item: items[index],
                      index: index,
                      controller: pageController,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BrandTokens.pageMargin,
                    8,
                    BrandTokens.pageMargin,
                    16,
                  ),
                  child: Row(
                    children: [
                      AnimatedExpanded(
                        axis: Axis.horizontal,
                        duration: BrandMotion.of(context).page,
                        sizeCurve: BrandCurves.enter,
                        expand: currentPage > 0,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: IconButton.filledTonal(
                            onPressed: () => _goToPage(currentPage - 1),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                      ),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            if (isInLastPage) {
                              introFinished();
                            } else {
                              _goToPage(currentPage + 1);
                            }
                          },
                          icon: const Icon(Icons.arrow_forward_rounded),
                          iconAlignment: IconAlignment.end,
                          label: Text(
                            isInLastPage
                                ? t.ui_actions.continue_text
                                : t.intro.next,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  StreamBuilder<Currency> buildCurrencySelectorTile(BuildContext context) {
    final t = Translations.of(context);

    return StreamBuilder(
      stream: CurrencyService.instance.ensureAndGetPreferredCurrency(),
      builder: (context, snapshot) {
        final userCurrency = snapshot.data;

        return Skeletonizer(
          enabled: userCurrency == null,
          child: ListTile(
            tileColor: BrandColors.of(context).soft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: BrandColors.of(context).textSecondary,
            ),
            leading: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
              ),
              child: userCurrency != null
                  ? userCurrency.displayFlagIcon(size: 42)
                  : Bone.square(size: 42),
            ),
            title: Text(t.intro.select_your_currency),
            subtitle: Text(userCurrency?.name ?? BoneMock.name),
            onTap: () {
              if (userCurrency == null) return;

              showCurrencySelectorModal(
                context,
                CurrencySelectorModal(
                  preselectedCurrency: userCurrency,
                  onCurrencySelected: (newCurrency) {
                    UserSettingService.instance
                        .setItem(SettingKey.preferredCurrency, newCurrency.code)
                        .then((value) => setState(() => {}));
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// One welcome page: the scene on a soft panel, then a short title and line.
/// While the page slides it also fades and scales between 0.98 and 1.
class _IntroSlide extends StatelessWidget {
  const _IntroSlide({
    required this.item,
    required this.index,
    required this.controller,
  });

  final OnboardingItem item;
  final int index;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reduce = BrandMotion.of(context).reduce;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: BrandTokens.pageMargin,
              vertical: 8,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(BrandTokens.sheetRadius),
            ),
            child: ExcludeSemantics(
              child: SvgPicture.asset(item.imageAsset, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandTokens.pageMargin + 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.header, style: textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  item.description,
                  style: textTheme.bodyLarge?.copyWith(
                    color: BrandColors.of(context).textSecondary,
                  ),
                ),
                ?item.extraWidget,
              ],
            ),
          ),
        ),
      ],
    );

    if (reduce) return content;

    return AnimatedBuilder(
      animation: controller,
      child: content,
      builder: (context, child) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        final distance = math.min((page - index).abs(), 1.0);

        return Opacity(
          opacity: 1 - distance,
          child: Transform.scale(scale: 1 - 0.02 * distance, child: child),
        );
      },
    );
  }
}
