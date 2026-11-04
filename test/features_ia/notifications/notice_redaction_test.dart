import 'package:flutter_test/flutter_test.dart';
import 'package:monekin/features_ia/notifications/notice_redaction.dart';

void main() {
  test('a one-time code is hidden', () {
    expect(
      maskSensitive('Tu clave de un solo uso es 482913. No la compartas.'),
      'Tu clave de un solo uso es ****. No la compartas.',
    );
    expect(maskSensitive('Código: 77'), 'Código: 77');
    expect(maskSensitive('Código de verificación 1234'), contains('****'));
  });

  test('an account or document number of 6 or more digits is hidden', () {
    expect(
      maskSensitive('Cuenta 123456789 recibió \$45.900'),
      'Cuenta ****** recibió \$45.900',
    );
    expect(maskSensitive('CC 1012345678'), 'CC ******');
  });

  test('a card number keeps only its last 4 digits', () {
    expect(maskSensitive('Tarjeta 4111111111111234'), 'Tarjeta ****1234');
    expect(maskSensitive('Tarjeta 4111 1111 1111 1234'), 'Tarjeta ****1234');
    expect(maskSensitive('con tu T.Deb *1234'), 'con tu T.Deb *1234');
  });

  test('amounts, dates and times stay', () {
    const text =
        'Compraste \$32.500,00 en UBER RIDES el 15/09/2026 a las 20:35. Saldo \$1.234.567';
    expect(maskSensitive(text), text);
    expect(
      maskSensitive('Pagaste \$450000 en EXITO'),
      'Pagaste \$450000 en EXITO',
    );
    expect(maskSensitive('Pagaste 450000 pesos'), 'Pagaste 450000 pesos');
    expect(maskSensitive('Pagaste COP 4500000'), 'Pagaste COP 4500000');
  });

  test('text without sensitive data is unchanged', () {
    const text = 'Pagaste \$45.900 en EXITO';
    expect(maskSensitive(text), text);
  });

  // F-07. Every text below is synthetic.
  group('redaction for the AI', () {
    test('balance, available and limit clauses are removed', () {
      expect(
        redactForAi(
          'Compra por \$45.900 en EXITO. Tu saldo es \$15.430.200,00. Disponible: \$900.000, cupo \$2.000.000',
        ),
        'Compra por \$45.900 en EXITO.',
      );
      expect(
        redactForAi('Saldo disponible \$15.430.200,00\nPagaste \$12.000 a ANA'),
        'Pagaste \$12.000 a ANA',
      );
    });

    test('digit runs are masked except the amount and the date', () {
      expect(
        redactForAi(
          'Compraste \$32.500,00 en UBER con tu T.Deb *1234, el 15/09/2026 a las 20:35. Cuenta 1234567890',
        ),
        'Compraste \$32.500,00 en UBER con tu T.Deb *****, el 15/09/2026 a las ****:****. Cuenta ****',
      );
      expect(redactForAi('Pagaste 45900 COP'), 'Pagaste 45900 COP');
      expect(
        redactForAi('Tarjeta 4111 1111 1111 4321'),
        'Tarjeta **** **** **** ****',
      );
    });

    test('a long text is cut', () {
      expect(redactForAi('Pagaste \$1.000 ${'x' * 2000}').length, 500);
    });
  });
}
