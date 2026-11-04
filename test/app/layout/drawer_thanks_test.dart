import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/i18n/generated/translations.g.dart';

void main() {
  test('the drawer thanks line is translated and has no emoji', () async {
    final es = await AppLocale.es.build();
    final en = await AppLocale.en.build();

    expect(es.brand_app.drawer_thanks, 'Gracias por confiar en Finanzas IA');
    expect(en.brand_app.drawer_thanks, 'Thanks for trusting Finanzas IA');
    expect(es.brand_app.drawer_thanks, isNot(contains('❤')));
    expect(en.brand_app.drawer_thanks, isNot(contains('❤')));
  });
}
