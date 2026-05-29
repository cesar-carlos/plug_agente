import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_file_service.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';

void main() {
  group('ClientTokenRuleFileService', () {
    const service = ClientTokenRuleFileService();

    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ct_rule_file_service_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    File fileWith(String name, String contents) {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      file.writeAsStringSync(contents);
      return file;
    }

    const rule = ClientTokenRuleDraft(
      resource: 'dbo.clientes',
      resourceType: DatabaseResourceType.table,
      effect: ClientTokenRuleEffect.allow,
      canRead: true,
      canUpdate: true,
      canDelete: false,
      canDdl: false,
    );

    test('should serialize rules into the strict line format', () {
      final serialized = service.serializeRules([rule]);

      expect(serialized, 'dbo.clientes;table;allow;read,update');
    });

    test('should round-trip serialized rules back through importFromFile', () async {
      final serialized = service.serializeRules([rule]);
      final file = fileWith('rules.txt', serialized);

      final outcome = await service.importFromFile(file.path);

      expect(outcome, isA<ClientTokenRuleImportLoaded>());
      final loaded = (outcome as ClientTokenRuleImportLoaded).drafts.single;
      expect(loaded.resource, 'dbo.clientes');
      expect(loaded.resourceType, DatabaseResourceType.table);
      expect(loaded.effect, ClientTokenRuleEffect.allow);
      expect(loaded.canRead, isTrue);
      expect(loaded.canUpdate, isTrue);
      expect(loaded.canDelete, isFalse);
      expect(loaded.canDdl, isFalse);
    });

    test('should report empty when the file has no content', () async {
      final file = fileWith('empty.txt', '');

      final outcome = await service.importFromFile(file.path);

      expect(outcome, isA<ClientTokenRuleImportEmpty>());
    });

    test('should report invalid format when a valid line is mixed with a malformed one', () async {
      final file = fileWith(
        'bad.txt',
        'dbo.clientes;table;allow;read\nthis-is-not-a-valid-rule-line',
      );

      final outcome = await service.importFromFile(file.path);

      expect(outcome, isA<ClientTokenRuleImportInvalidFormat>());
    });

    test('should report too large when the file exceeds the size limit', () async {
      final oversized = 'a' * (maxRuleImportFileSizeBytes + 1);
      final file = fileWith('big.txt', oversized);

      final outcome = await service.importFromFile(file.path);

      expect(outcome, isA<ClientTokenRuleImportTooLarge>());
    });

    test('should report a read failure when the file does not exist', () async {
      final outcome = await service.importFromFile('${tempDir.path}${Platform.pathSeparator}missing.txt');

      expect(outcome, isA<ClientTokenRuleImportReadFailure>());
    });

    test('should write serialized rules to a file via exportToFile', () async {
      final path = '${tempDir.path}${Platform.pathSeparator}export.txt';

      await service.exportToFile(path, [rule]);

      expect(File(path).readAsStringSync(), 'dbo.clientes;table;allow;read,update');
    });
  });
}
