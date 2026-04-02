import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/shared/widgets/common/form/brazilian_field_formatters.dart';

void main() {
  group('BrazilianFieldFormatters.format', () {
    test('should format CEP digits', () {
      final out = BrazilianFieldFormatters.format(
        '01310100',
        BrazilianFieldFormatters.postalCode,
      );
      expect(out, '01.310-100');
    });

    test('should format CPF digits', () {
      final out = BrazilianFieldFormatters.format(
        '12345678901',
        BrazilianFieldFormatters.document,
      );
      expect(out, '123.456.789-01');
    });

    test('should format phone digits', () {
      final out = BrazilianFieldFormatters.format(
        '11987654321',
        BrazilianFieldFormatters.phone,
      );
      expect(out, '(11) 98765-4321');
    });

    test('should uppercase state input', () {
      final out = BrazilianFieldFormatters.format(
        'sp',
        BrazilianFieldFormatters.state,
      );
      expect(out, 'SP');
    });
  });
}
