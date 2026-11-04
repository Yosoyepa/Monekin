import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/app/home/widgets/balance_hero.dart';
import 'package:monekin/app/home/widgets/dashboard_account_list.dart';
import 'package:monekin/app/home/widgets/dashboard_greeting.dart';
import 'package:monekin/app/home/widgets/dashboard_layout.dart';
import 'package:monekin/app/home/widgets/flow_summary_card.dart';
import 'package:monekin/app/home/widgets/period_chips.dart';
import 'package:monekin/app/home/widgets/private_mode_button.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/core/database/app_db.dart';
import 'package:monekin/core/models/date-utils/date_period.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/core/presentation/widgets/card_with_header.dart';
import 'package:monekin/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:monekin/core/presentation/widgets/number_ui_formatters/ui_number_formatter.dart';
import 'package:monekin/core/presentation/widgets/trending_value.dart';
import 'package:monekin/core/presentation/widgets/user_avatar.dart';
import 'package:monekin/core/services/supported_icon/supported_icon_service.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

import '../ui_test_utils.dart';

const _cop = CurrencyInDB(
  code: 'COP',
  symbol: r'$',
  name: 'Peso colombiano',
  decimalPlaces: 0,
  isDefault: true,
  type: 0, // CurrencyType.fiat
);

final _balanceText = const UINumberFormatter.currency(
  amountToConvert: 4235670,
  currency: _cop,
).getFormattedAmount();

/// Stand-in for the balance chart (the real one reads the database).
class _FakeChart extends StatelessWidget {
  const _FakeChart();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(Theme.of(context).colorScheme.primary),
      size: Size.infinite,
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const points = [0.7, 0.62, 0.66, 0.5, 0.55, 0.4, 0.46, 0.3, 0.34, 0.22];
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height * points[i];
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color;
}

/// The home screen with sample data: the same widgets and layout the page
/// uses, with the database-backed parts replaced by fixed values.
class _HomeScene extends StatelessWidget {
  const _HomeScene({this.animateMascot = false});

  final bool animateMascot;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final brand = BrandColors.of(context);
    final icons = SupportedIconService.instance;

    Widget amount(double value) => CurrencyDisplayer(
      amountToConvert: value,
      currency: _cop,
      showDecimals: false,
      integerStyle: Theme.of(context).textTheme.titleSmall!,
    );

    Widget account(String name, String type, double value, {String? icon}) {
      return AccountRowTile(
        leading: AccountAvatar(
          name: name,
          icon: icon == null ? null : icons.getIconByID(icon),
        ),
        title: name,
        subtitle: type,
        trailing: amount(value),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: DashboardLayout(
            header: Row(
              children: [
                Expanded(
                  child: DashboardGreeting(
                    greeting: welcomeGreeting(t, DateTime(2026, 11, 4, 9)),
                    userName: 'Juan Carlos',
                    avatar: const UserAvatar(avatar: 'man'),
                    onTap: () {},
                    animateMascot: animateMascot,
                  ),
                ),
                const SizedBox(width: 8),
                PrivateModeButton(onPressed: () {}),
              ],
            ),
            balance: BalanceHero(
              label: t.home.total_balance,
              balance: 4235670,
              currency: _cop,
              chart: const _FakeChart(),
              chips: PeriodChips(
                currentPeriod: const DatePeriod.lastDays(30),
                onPeriodSelected: (_) {},
              ),
              trend: const TrendingValue(
                percentage: 0.082,
                value: 318000,
                valueCurrency: _cop,
                dataTypes: [
                  TrendingValueDataType.value,
                  TrendingValueDataType.percentage,
                ],
                fontWeight: FontWeight.bold,
                style: TrendingValueStyle.chip,
              ),
            ),
            expenseCard: FlowSummaryCard(
              label: TransactionType.expense.displayName(context),
              icon: TransactionType.expense.icon,
              color: brand.expense,
              amount: 1248300,
              currency: _cop,
              trend: const TrendingValue(
                percentage: -0.12,
                inverse: true,
                style: TrendingValueStyle.chip,
                showPercentageDecimals: false,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            incomeCard: FlowSummaryCard(
              label: TransactionType.income.displayName(context),
              icon: TransactionType.income.icon,
              color: brand.income,
              amount: 3560000,
              currency: _cop,
              trend: const TrendingValue(
                percentage: 0.05,
                style: TrendingValueStyle.chip,
                showPercentageDecimals: false,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            accounts: CardWithHeader(
              title: t.home.my_accounts,
              bodyPadding: const EdgeInsets.only(top: 4, bottom: 8),
              headerAction: CardHeaderAction(
                icon: const Icon(Icons.add_rounded),
                text: t.account.form.create,
                onTap: () {},
              ),
              body: Column(
                children: [
                  account('Efectivo', 'Dinero', 350000, icon: 'wallet'),
                  account('Nequi', 'Dinero', 1280670),
                  account('Bancolombia', 'Dinero', 2605000, icon: 'savings'),
                ],
              ),
            ),
            health: CardWithHeader(
              title: t.financial_health.display,
              body: const SizedBox(height: 120),
            ),
            categories: CardWithHeader(
              title: t.stats.by_categories,
              body: const SizedBox(height: 160),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _home({bool dark = false, bool reduce = false}) => uiApp(
  _HomeScene(animateMascot: reduce),
  dark: dark,
  disableAnimations: reduce,
);

void main() {
  setUpAll(() async {
    await loadUiFonts();
    await LocaleSettings.setLocale(AppLocale.es);
  });

  group('greeting', () {
    test('changes with the hour of the day', () async {
      for (final locale in [AppLocale.es, AppLocale.en]) {
        final t = await locale.build();
        String at(int hour) => welcomeGreeting(t, DateTime(2026, 1, 1, hour));

        expect(at(6), t.home.welcome_back_morning);
        expect(at(11), t.home.welcome_back_morning);
        expect(at(12), t.home.welcome_back_afternoon);
        expect(at(18), t.home.welcome_back_afternoon);
        expect(at(19), t.home.welcome_back_evening);
        expect(at(22), t.home.welcome_back_evening);
        expect(at(23), t.home.welcome_back_night);
        expect(at(2), t.home.welcome_back_night);
      }
    });

    test('is one of the plain greetings, never a random phrase', () async {
      final t = await AppLocale.es.build();
      final all = {
        for (var h = 0; h < 24; h++)
          welcomeGreeting(t, DateTime(2026, 1, 1, h)),
      };

      expect(all, {'¡Buenos días!', '¡Buenas tardes!', '¡Buenas noches!'});
    });

    test('the seeded and the blank names are not shown', () {
      expect(displayableUserName(null), isNull);
      expect(displayableUserName(''), isNull);
      expect(displayableUserName('   '), isNull);
      expect(displayableUserName('User'), isNull);
      expect(displayableUserName(' Ana '), 'Ana');
    });

    for (final name in [null, '', 'User']) {
      testWidgets('shows only the greeting for the name "$name"', (
        tester,
      ) async {
        await tester.pumpWidget(
          uiApp(
            Scaffold(
              body: DashboardGreeting(
                greeting: '¡Buenos días!',
                userName: name,
                avatar: const SizedBox(width: 40, height: 40),
                onTap: () {},
                animateMascot: false,
              ),
            ),
          ),
        );
        await settleSvgs(tester);

        expect(find.text('¡Buenos días!'), findsOneWidget);
        expect(find.text('User'), findsNothing);
        expect(find.byType(ChanchiMascot), findsOneWidget);
      });
    }

    testWidgets('shows the name the user picked below the greeting', (
      tester,
    ) async {
      await tester.pumpWidget(
        uiApp(
          Scaffold(
            body: DashboardGreeting(
              greeting: '¡Buenos días!',
              userName: 'Ana',
              avatar: const SizedBox(width: 40, height: 40),
              onTap: () {},
              animateMascot: false,
            ),
          ),
        ),
      );
      await settleSvgs(tester);

      expect(find.text('¡Buenos días!'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });
  });

  group('accounts', () {
    testWidgets('an account without an icon shows its initial on a soft '
        'circle', (tester) async {
      await tester.pumpWidget(
        uiApp(const Scaffold(body: AccountAvatar(name: 'nequi'))),
      );

      expect(find.text('N'), findsOneWidget);
      final circle = tester.widget<Container>(find.byType(Container).first);
      final decoration = circle.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, BrandTokens.light.soft);
    });

    testWidgets('an account with an icon shows it instead of the initial', (
      tester,
    ) async {
      final icon = SupportedIconService.instance.getIconByID('wallet');

      await tester.pumpWidget(
        uiApp(
          Scaffold(
            body: AccountAvatar(name: 'Efectivo', icon: icon),
          ),
        ),
      );

      expect(find.text('E'), findsNothing);
    });
  });

  for (final size in [(360.0, 'w360'), (412.0, 'w412')]) {
    for (final dark in [false, true]) {
      final name = '${size.$2}_${dark ? 'dark' : 'light'}';

      testWidgets('home with 3 accounts ($name)', (tester) async {
        await useSurface(tester, size.$1, 1180, ratio: 2);
        await tester.pumpWidget(_home(dark: dark));
        await settleSvgs(tester);
        await tester.pump(const Duration(seconds: 2));

        expect(tester.takeException(), isNull);

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home_$name.png'),
        );
      });
    }
  }

  group('reduced motion', () {
    testWidgets('the home paints its final state in the first frame', (
      tester,
    ) async {
      await useSurface(tester, 360, 1180);
      await tester.pumpWidget(_home(reduce: true));
      await settleSvgs(tester);

      // The balance is already its final value: no counting up.
      expect(find.text(_balanceText), findsOneWidget);
      // No staggered entrance (no fade wrappers) and nothing running.
      expect(
        find.descendant(
          of: find.byType(DashboardLayout),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('without it the balance counts up and the sections fade in', (
      tester,
    ) async {
      await useSurface(tester, 360, 1180);
      await tester.pumpWidget(uiApp(const _HomeScene()));
      await settleSvgs(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_balanceText), findsNothing);
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_balanceText), findsOneWidget);
    });
  });
}
