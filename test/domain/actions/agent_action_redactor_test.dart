import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_redactor.dart';

void main() {
  group('AgentActionRedactor', () {
    const redactor = AgentActionRedactor();

    test('should redact key-value and CLI secret patterns', () {
      const input = r'senha=plain --password "hidden" ${secret:db}';
      final output = redactor.redactText(input);

      expect(output, contains('senha=[REDACTED]'));
      expect(output, contains('--password [REDACTED]'));
      expect(output, contains('[REDACTED]'));
      expect(output, isNot(contains('plain')));
      expect(output, isNot(contains('hidden')));
    });

    test('should redact Data7 XML credential elements', () {
      const input = '''
<Conexao>
  <Senha>super-secret</Senha>
  <Usuario>admin</Usuario>
  <Servidor>10.0.0.1</Servidor>
  <BaseDados>Prod</BaseDados>
</Conexao>
''';
      final output = redactor.redactText(input);

      expect(output, contains('<Senha>[REDACTED]</Senha>'));
      expect(output, contains('<Usuario>[REDACTED]</Usuario>'));
      expect(output, contains('<Servidor>[REDACTED]</Servidor>'));
      expect(output, contains('<BaseDados>[REDACTED]</BaseDados>'));
      expect(output, isNot(contains('super-secret')));
      expect(output, isNot(contains('admin')));
      expect(output, isNot(contains('10.0.0.1')));
      expect(output, isNot(contains('Prod')));
    });
  });
}
