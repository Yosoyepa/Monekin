// F-11: the statement text is reduced and masked before it goes to the AI provider.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/core/privacy/statement_redaction.dart';

const _header = '''
Bancolombia S.A. NIT 890.903.938-8
Titular: JUAN PEREZ GOMEZ
Documento: CC 1.032.456.789
Cuenta de ahorros No. 12345678901 Moneda: COP
Correo: juan.perez@example.com  Celular: 300 123 4567
Direccion: Calle 45 # 12-34 Bogota
Saldo disponible: \$ 8.765.432,10
Cupo de sobregiro: 500.000,00
Saldo inicial: \$ 2.350.000,00
Fecha       Descripcion                 Debito      Credito     Saldo
01/10/2026  ABONO NOMINA EMPRESA SAS                3.200.000,00  5.550.000,00
02/10/2026  PSE PAGO EPM ENERGIA         32.900,00                5.517.100,00
04/10/2026  TRANSFERENCIA A 3001234567   18.700,00                5.498.400,00
Saldo final: \$ 5.498.400,00
''';

void main() {
  group('statement header', () {
    final redacted = redactStatementText(_header);

    test('identifiers do not survive', () {
      for (final secret in [
        'JUAN',
        'PEREZ',
        '1.032.456.789',
        '1032456789',
        '890.903.938',
        '12345678901',
        'example.com',
        '300 123 4567',
        '3001234567',
        'Calle 45',
        '8.765.432',
        '500.000,00',
      ]) {
        expect(redacted, isNot(contains(secret)), reason: secret);
      }
    });

    test('movements, column headers and opening and closing balances stay', () {
      for (final kept in [
        'Fecha       Descripcion',
        '01/10/2026  ABONO NOMINA EMPRESA SAS',
        '3.200.000,00  5.550.000,00',
        '02/10/2026  PSE PAGO EPM ENERGIA         32.900,00',
        '04/10/2026  TRANSFERENCIA A [phone]',
        r'Saldo inicial: $ 2.350.000,00',
        r'Saldo final: $ 5.498.400,00',
      ]) {
        expect(redacted, contains(kept), reason: kept);
      }
    });
  });

  group('fixture statements', () {
    test('the Bancolombia text keeps every movement and both balances', () {
      final text = File(
        'test/features_ia/statements/bancolombia_extracted.txt',
      ).readAsStringSync();

      final redacted = redactStatementText(text);

      for (final line in text.split('\n')) {
        final dated = RegExp(r'^\d\d/\d\d/\d{4}\s').hasMatch(line);
        final amountOnly = RegExp(r'^\s+[\d.]+,\d\d\s*$').hasMatch(line);
        if (dated || amountOnly) {
          expect(redacted, contains(line.trim()), reason: line);
        }
      }
      expect(redacted, contains(r'Saldo inicial: $ 2.350.000,00'));
      expect(redacted, contains(r'Saldo final: $ 5.512.650,00'));
      expect(redacted, isNot(contains('1234')));
      expect(redacted, isNot(contains('Usuario de Prueba')));
    });

    test('the Nequi CSV keeps every row and both balances', () {
      final text = File(
        'test/features_ia/fixtures/statements/nequi_2026-10.csv',
      ).readAsStringSync();

      final redacted = redactStatementText(text);

      for (final line in text.split('\n')) {
        if (RegExp(r'^\d\d/\d\d/\d{4};').hasMatch(line) ||
            line.startsWith('Saldo')) {
          expect(redacted, contains(line.trim()), reason: line);
        }
      }
      expect(redacted, isNot(contains('Cuenta: Nequi')));
    });
  });

  group('masking', () {
    String mask(String text) => maskStatementIdentifiers(text);

    test('document, account and card numbers become tags', () {
      expect(mask('CC 1032456789'), 'CC [id]');
      expect(mask('cedula: 1.032.456.789'), 'cedula: [id]');
      expect(mask('NIT 900.123.456-7'), 'NIT [id]');
      expect(mask('Cuenta de ahorros: ****1234'), 'Cuenta de ahorros: [id]');
      expect(mask('cuenta 12345678901'), 'cuenta [id]');
      expect(mask('tarjeta 4111 1111 1111 1111'), 'tarjeta [card]');
      expect(mask('COMPRA **** **** **** 4412'), 'COMPRA [card]');
      expect(mask('PAGO 4111111111111111'), 'PAGO [id]');
      expect(mask('ref 900123456 abono'), 'ref [id] abono');
    });

    test('emails and phones become tags', () {
      expect(mask('escribe a juan@example.com hoy'), 'escribe a [email] hoy');
      expect(mask('ENVIO 3001234567'), 'ENVIO [phone]');
      expect(mask('ENVIO +57 300 123 4567'), 'ENVIO [phone]');
      expect(mask('LLAMAR (601) 234 5678'), 'LLAMAR [phone]');
    });

    test('dates, amounts and descriptions are untouched', () {
      for (final line in [
        '02/10/2026 Recarga celular -20.000,00 330.000,00',
        '2026-10-02 COMPRA TIENDA 45900',
        '13/10/2026 Recepcion de Maria Lopez +80.000,00',
        r'Saldo inicial: $ 2.350.000,00',
        'TOTAL 1.234.567,89',
        'ABONO 12345678,50',
        r'Saldo final $ 15430200',
        'Periodo 20261031 al 20261101',
        'Cuenta de ahorros Saldo inicial 2.350.000,00',
      ]) {
        expect(mask(line), line, reason: line);
      }
    });
  });

  group('reduction', () {
    test('fewer than three movements keeps every line, masked', () {
      const text =
          'Titular: ANA RUIZ CC 52123456\nFecha Valor\n01/10/2026 PAGO 10.000,00\n';

      final redacted = redactStatementText(text);

      expect(redacted, contains('Titular: ANA RUIZ CC [id]'));
      expect(redacted, contains('01/10/2026 PAGO 10.000,00'));
    });

    test('a description that says cliente stays when it has a date', () {
      const text =
          '01/10/2026 CONSIGNACION CLIENTE PROYECTO 1.000,00\n'
          '02/10/2026 PAGO 2.000,00\n'
          '03/10/2026 PAGO 3.000,00\n';

      expect(redactStatementText(text), text.trim());
    });
  });

  group('long lines', () {
    for (final entry in {
      'digits': '1' * 12000,
      'spaced digits': '1 ' * 6000,
      'stars': '*' * 12000,
      'masked card keywords': 'cuenta ' * 1700,
      'at signs': '${'a' * 6000}@${'b' * 6000}',
      'dots': '1.' * 6000,
      'dates': '01/10/2026 ' * 1100,
      'x runs': 'X' * 12000,
    }.entries) {
      test('${entry.key} are processed in under 50 ms', () {
        final watch = Stopwatch()..start();
        redactStatementText('${entry.value}\n${entry.value}');
        watch.stop();
        expect(watch.elapsedMilliseconds, lessThan(50), reason: entry.key);
      });
    }
  });
}
