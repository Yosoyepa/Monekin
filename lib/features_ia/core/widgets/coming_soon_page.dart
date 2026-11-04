// Placeholder page used by the T002 skeleton until a feature owner replaces it. Owner: architect.
import 'package:flutter/material.dart';
import 'package:monekin/app/layout/page_framework.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return PageFramework(
      title: title,
      body: Center(child: Text(t.ia_common.coming_soon)),
    );
  }
}
