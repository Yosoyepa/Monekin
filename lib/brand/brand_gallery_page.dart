import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:monekin/brand/brand_tokens.dart';
import 'package:monekin/brand/chanchi.dart';
import 'package:monekin/brand/motion.dart';

/// Route of the brand gallery, or null in release builds where it does not
/// exist. Wire it from a debug-only entry point.
Route<void>? brandGalleryRoute() => kDebugMode
    ? MaterialPageRoute<void>(builder: (_) => const BrandGalleryPage())
    : null;

/// Visual review of the brand: colors, type, buttons, fields, chips and
/// Chanchi in his five moods. Debug only.
class BrandGalleryPage extends StatelessWidget {
  const BrandGalleryPage({super.key, this.animate = true});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = BrandColors.of(context);
    final scheme = theme.colorScheme;

    final swatches = <String, Color>{
      'background': scheme.surface,
      'surface': scheme.surfaceContainerLowest,
      'surfaceLow': brand.surfaceLow,
      'soft': brand.soft,
      'primary': scheme.primary,
      'primaryContainer': scheme.primaryContainer,
      'text': scheme.onSurface,
      'textSecondary': brand.textSecondary,
      'outline': brand.outline,
      'expense': brand.expense,
      'income': brand.income,
      'warning': brand.warning,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Brand gallery')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          BrandTokens.pageMargin,
          8,
          BrandTokens.pageMargin,
          32,
        ),
        children: [
          _Section('Colors', [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final e in swatches.entries) _Swatch(e.key, e.value),
              ],
            ),
          ]),
          _Section('Typography', [
            Text('1,250.00', style: theme.textTheme.displaySmall),
            Text('Page title', style: theme.textTheme.headlineSmall),
            Text('Section title', style: theme.textTheme.titleLarge),
            Text(
              'Body text with the line height of the brand.',
              style: theme.textTheme.bodyLarge,
            ),
            Text('Caption', style: theme.textTheme.labelMedium),
          ]),
          _Section('Buttons', [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                const FilledButton(onPressed: null, child: Text('Disabled')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                PressScale(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Press me'),
                  ),
                ),
              ],
            ),
          ]),
          _Section('Fields', [
            const TextField(
              decoration: InputDecoration(
                labelText: 'Merchant',
                hintText: 'Where did you spend?',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Amount',
                errorText: 'Required',
              ),
            ),
          ]),
          _Section('Chips', [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const Chip(label: Text('Week')),
                ChoiceChip(
                  label: const Text('Month'),
                  selected: true,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('Year'),
                  selected: false,
                  onSelected: (_) {},
                ),
              ],
            ),
          ]),
          _Section('Card', [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('A flat card, radius 20, no shadow.'),
              ),
            ),
          ]),
          _Section('Chanchi', [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final mood in ChanchiMood.values)
                  Column(
                    children: [
                      ChanchiMascot(mood: mood, size: 96, animate: animate),
                      const SizedBox(height: 4),
                      Text(mood.name, style: theme.textTheme.labelMedium),
                    ],
                  ),
              ],
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(BrandTokens.fieldRadius),
              border: Border.all(color: BrandColors.of(context).outline),
            ),
            child: const SizedBox(height: 48, width: 96),
          ),
          const SizedBox(height: 4),
          Text(name, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
