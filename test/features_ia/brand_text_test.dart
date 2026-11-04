// BUG-10: no visible text says «Monekin», except the credits to its developers and the links to its repository.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every string of the file with the dotted path of its key.
Map<String, String> _flatten(Object? node, [String path = '']) =>
    switch (node) {
      final Map<String, dynamic> map => {
        for (final e in map.entries)
          ..._flatten(e.value, path.isEmpty ? e.key : '$path.${e.key}'),
      },
      final String text => {path: text},
      _ => {},
    };

/// The text people read: the addresses inside links are not part of it.
String _visible(String text) =>
    text.replaceAll(RegExp(r'https?://[^\s\x27"<>]+'), '');

void main() {
  const credits = {
    'MORE.ABOUT_US.PROJECT.contributors.descr',
    'MORE.HELP_US.thanks_long',
  };

  for (final locale in ['es', 'en']) {
    test('$locale.json names the app Finanzas IA in every visible text', () {
      final json = jsonDecode(
        File('lib/i18n/json/$locale.json').readAsStringSync(),
      );
      final named = {
        for (final e in _flatten(json).entries)
          if (_visible(e.value).contains('Monekin')) e.key,
      };

      expect(named.difference(credits), isEmpty);
    });
  }

  test('the empty home asks for the first account', () {
    final es = _flatten(
      jsonDecode(File('lib/i18n/json/es.json').readAsStringSync()),
    );
    final en = _flatten(
      jsonDecode(File('lib/i18n/json/en.json').readAsStringSync()),
    );
    final key = es.keys.singleWhere((k) => k.endsWith('no-accounts.descr'));

    expect(es[key], 'Crea tu primera cuenta y empieza a registrar tus gastos');
    expect(
      en[key],
      'Create your first account and start tracking your spending',
    );
  });
}
