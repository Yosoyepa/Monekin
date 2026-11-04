// Examples are invented with the wording of each bank (see the sources in bank_notice.dart); none comes from a real person.
import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/core/models/transaction/transaction_type.enum.dart';
import 'package:monekin/features_ia/notifications/bank_apps.dart';
import 'package:monekin/features_ia/notifications/bank_notice.dart';

import 'test_support.dart';

class _Case {
  const _Case(
    this.content,
    this.kind,
    this.amount, {
    this.merchant,
    this.last4,
  });

  final String content;
  final NoticeKind kind;
  final double amount;
  final String? merchant;
  final String? last4;
}

final _posted = DateTime(2026, 11, 4, 9, 30);

final Map<BankId, List<_Case>> _cases = {
  BankId.bancolombia: [
    const _Case(
      'Compraste \$32.500,00 en UBER RIDES con tu T.Deb *1234, el 15/09/2026 a las 20:35.',
      NoticeKind.purchase,
      32500,
      merchant: 'UBER RIDES',
      last4: '1234',
    ),
    const _Case(
      'Compraste \$45.900 en EXITO CHAPINERO con tu T.Cred *9876, el 02/10/2026 a las 13:05.',
      NoticeKind.purchase,
      45900,
      merchant: 'EXITO CHAPINERO',
      last4: '9876',
    ),
    const _Case(
      'Bancolombia: Pagaste \$62.000,00 a Pexto Capital SAS desde tu producto 1234 el 13/09/2026 22:20:37.',
      NoticeKind.payment,
      62000,
      merchant: 'Pexto Capital SAS',
      last4: '1234',
    ),
    const _Case(
      'Bancolombia: Transferiste \$75.000,00 desde tu cuenta *1234 a la cuenta *00001111222 el 13/09/26 a las 23:54.',
      NoticeKind.transferOut,
      75000,
      merchant: 'Transferencia *1222',
      last4: '1234',
    ),
    const _Case(
      'Bancolombia: Recibiste una transferencia por \$185,000.00 de Juan Pérez en tu cuenta *1234, el 14/09/26 a las 01:40.',
      NoticeKind.transferIn,
      185000,
      merchant: 'Juan Pérez',
      last4: '1234',
    ),
    const _Case(
      'Retiraste \$200.000,00 en CAJERO CALLE 85 con tu T.Deb *1234, el 20/10/2026 a las 18:10.',
      NoticeKind.withdrawal,
      200000,
      merchant: 'CAJERO CALLE 85',
      last4: '1234',
    ),
    const _Case(
      'Bancolombia: Recibiste un pago por \$1.200.000,00 de EMPRESA SAS en tu cuenta *1234, el 30/10/2026 a las 08:00.',
      NoticeKind.deposit,
      1200000,
      merchant: 'EMPRESA SAS',
      last4: '1234',
    ),
  ],
  BankId.nequi: [
    const _Case(
      'Juan Pérez te envió \$300.000',
      NoticeKind.transferIn,
      300000,
      merchant: 'Juan Pérez',
    ),
    const _Case(
      'Ana María te envió 50000',
      NoticeKind.transferIn,
      50000,
      merchant: 'Ana María',
    ),
    const _Case(
      'Pagaste \$45.900 en EXITO',
      NoticeKind.payment,
      45900,
      merchant: 'EXITO',
    ),
    const _Case(
      'Enviaste \$20.000 a Carlos Gómez',
      NoticeKind.transferOut,
      20000,
      merchant: 'Carlos Gómez',
    ),
    const _Case(
      'Compraste \$15.500 en TIENDA D1 con tu Tarjeta Nequi Visa terminada en 4821',
      NoticeKind.purchase,
      15500,
      merchant: 'TIENDA D1',
      last4: '4821',
    ),
    const _Case(
      'Retiraste \$100.000 del cajero Bancolombia',
      NoticeKind.withdrawal,
      100000,
      merchant: 'cajero Bancolombia',
    ),
    const _Case(
      'Recibiste \$120.000 de María Rodríguez',
      NoticeKind.deposit,
      120000,
      merchant: 'María Rodríguez',
    ),
  ],
  BankId.davivienda: [
    const _Case(
      'Realizaste una compra por \$85.000 en RAPPI COLOMBIA con tu tarjeta terminada en 5566.',
      NoticeKind.purchase,
      85000,
      merchant: 'RAPPI COLOMBIA',
      last4: '5566',
    ),
    const _Case(
      'Compra exitosa por \$120.500 en ALKOSTO con tu tarjeta *4411',
      NoticeKind.purchase,
      120500,
      merchant: 'ALKOSTO',
      last4: '4411',
    ),
    const _Case(
      'Pagaste \$230.000 a CODENSA ENEL desde tu cuenta de ahorros *7788',
      NoticeKind.payment,
      230000,
      merchant: 'CODENSA ENEL',
      last4: '7788',
    ),
    const _Case(
      'Transferiste \$500.000 a Laura Torres',
      NoticeKind.transferOut,
      500000,
      merchant: 'Laura Torres',
    ),
    const _Case(
      'Retiro por \$300.000 en cajero CRA 15',
      NoticeKind.withdrawal,
      300000,
      merchant: 'cajero CRA 15',
    ),
    const _Case(
      'Recibiste \$1.500.000 de EMPRESA XYZ SAS',
      NoticeKind.transferIn,
      1500000,
      merchant: 'EMPRESA XYZ SAS',
    ),
    const _Case(
      'Pedro Ruiz te transfirió \$90.000',
      NoticeKind.transferIn,
      90000,
      merchant: 'Pedro Ruiz',
    ),
  ],
  BankId.daviplata: [
    const _Case(
      'Pasaste \$40.000 a 3001234567',
      NoticeKind.transferOut,
      40000,
      merchant: 'Transferencia *4567',
    ),
    const _Case(
      'Pagaste \$12.300 en TIENDA MIS AMIGOS',
      NoticeKind.payment,
      12300,
      merchant: 'TIENDA MIS AMIGOS',
    ),
    const _Case(
      'Recibiste \$75.000 de Sandra Mora',
      NoticeKind.transferIn,
      75000,
      merchant: 'Sandra Mora',
    ),
    const _Case(
      'Compra por \$29.900 en NETFLIX COM con tu tarjeta Daviplata terminada en 3030',
      NoticeKind.purchase,
      29900,
      merchant: 'NETFLIX COM',
      last4: '3030',
    ),
    const _Case(
      'Retiraste \$50.000 en CAJERO DAVIVIENDA',
      NoticeKind.withdrawal,
      50000,
      merchant: 'CAJERO DAVIVIENDA',
    ),
    const _Case(
      'Compra aprobada por \$18.000 en CINE COLOMBIA',
      NoticeKind.purchase,
      18000,
      merchant: 'CINE COLOMBIA',
    ),
    const _Case(
      'Enviaste \$35.000 a Mario Pérez',
      NoticeKind.transferOut,
      35000,
      merchant: 'Mario Pérez',
    ),
  ],
  BankId.nu: [
    const _Case(
      'Compra aprobada: \$45.900 en EXITO',
      NoticeKind.purchase,
      45900,
      merchant: 'EXITO',
    ),
    const _Case(
      'Tu compra de \$120.000 en MERCADO LIBRE fue aprobada',
      NoticeKind.purchase,
      120000,
      merchant: 'MERCADO LIBRE',
    ),
    const _Case(
      'Compraste \$9.900 en SPOTIFY con tu tarjeta Nu terminada en 1122',
      NoticeKind.purchase,
      9900,
      merchant: 'SPOTIFY',
      last4: '1122',
    ),
    const _Case(
      'Recibiste \$200.000 de Camila Vargas',
      NoticeKind.transferIn,
      200000,
      merchant: 'Camila Vargas',
    ),
    const _Case(
      'Enviaste \$60.000 a Jorge Díaz',
      NoticeKind.transferOut,
      60000,
      merchant: 'Jorge Díaz',
    ),
    const _Case(
      'Pagaste \$150.000 a SURA SEGUROS',
      NoticeKind.payment,
      150000,
      merchant: 'SURA SEGUROS',
    ),
    const _Case(
      'Te abonamos \$5.000 por tu cashback',
      NoticeKind.deposit,
      5000,
    ),
  ],
  BankId.bbva: [
    const _Case(
      'BBVA: Compra por \$67.800 en FALABELLA con tarjeta *3344',
      NoticeKind.purchase,
      67800,
      merchant: 'FALABELLA',
      last4: '3344',
    ),
    const _Case(
      'Compra de \$23.000 en OXXO CALLE 80 con TC *9090',
      NoticeKind.purchase,
      23000,
      merchant: 'OXXO CALLE 80',
      last4: '9090',
    ),
    const _Case(
      'Retiro por \$400.000 en CAJERO BBVA',
      NoticeKind.withdrawal,
      400000,
      merchant: 'CAJERO BBVA',
    ),
    const _Case(
      'Transferencia enviada por \$150.000 a Luis Mendoza',
      NoticeKind.transferOut,
      150000,
      merchant: 'Luis Mendoza',
    ),
    const _Case(
      'Transferencia recibida por \$320.000 de Ana Lozano',
      NoticeKind.transferIn,
      320000,
      merchant: 'Ana Lozano',
    ),
    const _Case(
      'Pago por \$88.000 a CLARO COLOMBIA',
      NoticeKind.payment,
      88000,
      merchant: 'CLARO COLOMBIA',
    ),
    const _Case(
      'Compra aprobada por \$54.300 en ZARA',
      NoticeKind.purchase,
      54300,
      merchant: 'ZARA',
    ),
  ],
  BankId.bancoDeBogota: [
    const _Case(
      'Banco de Bogotá: Compra por \$76.400 en CARULLA con TC *2255',
      NoticeKind.purchase,
      76400,
      merchant: 'CARULLA',
      last4: '2255',
    ),
    const _Case(
      'Compra de \$31.000 en TERPEL con tarjeta débito *6677',
      NoticeKind.purchase,
      31000,
      merchant: 'TERPEL',
      last4: '6677',
    ),
    const _Case(
      'Transferencia enviada por \$200.000 a Felipe Castro',
      NoticeKind.transferOut,
      200000,
      merchant: 'Felipe Castro',
    ),
    const _Case(
      'Transferencia recibida por \$450.000',
      NoticeKind.transferIn,
      450000,
    ),
    const _Case(
      'Retiro por \$100.000 en ATH CALLE 100',
      NoticeKind.withdrawal,
      100000,
      merchant: 'ATH CALLE 100',
    ),
    const _Case(
      'Pago por \$64.000 a ACUEDUCTO DE BOGOTA',
      NoticeKind.payment,
      64000,
      merchant: 'ACUEDUCTO DE BOGOTA',
    ),
    const _Case(
      'Compra por \$19.900 en IFOOD',
      NoticeKind.purchase,
      19900,
      merchant: 'IFOOD',
    ),
  ],
};

void main() {
  for (final entry in _cases.entries) {
    group('templates ${entry.key.name}', () {
      test(
        'has at least 5 examples',
        () => expect(entry.value.length, greaterThanOrEqualTo(5)),
      );

      for (final c in entry.value) {
        test(c.content, () {
          final n = parseBankNotice(
            title: 'Aviso',
            content: c.content,
            receivedAt: _posted,
            bank: entry.key,
            parse: testAmountParser,
          );
          expect(n, isNotNull, reason: 'no template matched');
          expect(n!.kind, c.kind);
          expect(n.amount, c.amount);
          expect(n.merchant, c.merchant);
          expect(n.last4, c.last4);
          expect(
            n.type,
            c.kind.isIncome ? TransactionType.income : TransactionType.expense,
          );
        });
      }
    });
  }

  group('dates', () {
    BankNotice parse(String content) => parseBankNotice(
      title: '',
      content: content,
      receivedAt: _posted,
      bank: BankId.bancolombia,
      parse: testAmountParser,
    )!;

    test('four-digit year with time', () {
      final n = parse(
        'Compraste \$32.500,00 en UBER RIDES con tu T.Deb *1234, el 15/09/2026 a las 20:35.',
      );
      expect(n.date, DateTime(2026, 9, 15, 20, 35));
    });

    test('two-digit year with time', () {
      final n = parse(
        'Bancolombia: Recibiste una transferencia por \$185,000.00 de Juan Pérez en tu cuenta *1234, el 14/09/26 a las 01:40.',
      );
      expect(n.date, DateTime(2026, 9, 14, 1, 40));
    });

    test('time with seconds', () {
      final n = parse(
        'Bancolombia: Pagaste \$62.000,00 a Pexto Capital SAS desde tu producto 1234 el 13/09/2026 22:20:37.',
      );
      expect(n.date, DateTime(2026, 9, 13, 22, 20, 37));
    });

    test('no date in the text uses the time it was posted', () {
      expect(
        parse('Pagaste \$45.900 a EXITO desde tu cuenta *1234').date,
        _posted,
      );
    });

    test('an impossible date uses the time it was posted', () {
      expect(
        parse(
          'Pagaste \$45.900 a EXITO desde tu cuenta *1234 el 31/02/2026',
        ).date,
        _posted,
      );
    });
  });

  group('text that is not a movement', () {
    final texts = [
      'Haz 5 compras con tu Tarjeta Nequi Visa y gana premios',
      'Tu clave dinámica es 482913. No la compartas.',
      'Nequi: ¡Hola! Tenemos nuevas funciones para ti',
      'Tu saldo disponible es \$1.250.000',
    ];

    for (final text in texts) {
      test(text, () {
        expect(
          parseBankNotice(
            title: '',
            content: text,
            receivedAt: _posted,
            parse: testAmountParser,
          ),
          isNull,
        );
      });
    }

    test('only text with an amount looks financial', () {
      expect(looksFinancial('Nequi', 'Haz 5 compras y gana premios'), isFalse);
      expect(looksFinancial('Nequi', 'Pagaste \$45.900 en EXITO'), isTrue);
    });
  });

  test('the sentence can be in the title instead of the text', () {
    final n = parseBankNotice(
      title: 'Pagaste \$45.900 en EXITO',
      content: '',
      receivedAt: _posted,
      bank: BankId.nequi,
      parse: testAmountParser,
    );
    expect(n!.kind, NoticeKind.payment);
    expect(n.merchant, 'EXITO');
  });

  test('a zero amount is not a movement', () {
    expect(
      parseBankNotice(
        title: '',
        content: 'Pagaste \$0 en EXITO',
        receivedAt: _posted,
        parse: testAmountParser,
      ),
      isNull,
    );
  });

  test('the app picks which templates go first', () {
    // "Recibiste \$X de Y" reads the same in several banks: the app only changes the order.
    final fromNu = parseBankNotice(
      title: '',
      content: 'Recibiste \$200.000 de Camila Vargas',
      receivedAt: _posted,
      bank: BankId.nu,
      parse: testAmountParser,
    );
    expect(fromNu!.kind, NoticeKind.transferIn);
  });
}
