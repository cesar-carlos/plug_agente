import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_rule_parser.dart';

void main() {
  group('parseTokenRulesStrict', () {
    test('parses valid full-format lines', () {
      const content =
          'dbo.clientes;table;allow;read,update\n'
          'dbo.pedidos;view;deny;ddl';

      final result = parseTokenRulesStrict(content);

      expect(result.hasErrors, isFalse);
      expect(result.drafts, hasLength(2));
      expect(result.drafts.first.resource, 'dbo.clientes');
      expect(result.drafts.first.resourceType, DatabaseResourceType.table);
      expect(result.drafts.first.canRead, isTrue);
      expect(result.drafts.first.canUpdate, isTrue);
      expect(result.drafts.last.canDdl, isTrue);
    });

    test('rejects simplified format in strict mode', () {
      const content = 'dbo.clientes;dbo.pedidos';

      final result = parseTokenRulesStrict(content);

      expect(result.hasErrors, isTrue);
      expect(result.drafts, isEmpty);
      expect(result.errors.first.line, 1);
    });

    test('skips empty lines', () {
      const content = '\n\n';

      final result = parseTokenRulesStrict(content);

      expect(result.hasErrors, isFalse);
      expect(result.drafts, isEmpty);
    });
  });
}
