// Placeholder from the T002 skeleton. Owner: w-insights (replace the body, keep the class name and constructor).
import 'package:flutter/material.dart';
import 'package:monekin/features_ia/core/widgets/coming_soon_page.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) => ComingSoonPage(title: Translations.of(context).ia_insights.title);
}
