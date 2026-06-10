import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';

void main() {
  group('UpdateClientToken end-to-end outcome', () {
    late AppDatabase db;
    late _InMemorySecretStore secretStore;
    late _RecordingAuditStore auditStore;
    late ClientTokenLocalDataSource dataSource;
    late ClientTokenRepository repository;
    late UpdateClientToken useCase;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      secretStore = _InMemorySecretStore();
      auditStore = _RecordingAuditStore();
      dataSource = ClientTokenLocalDataSource(db, secretStore: secretStore);
      repository = ClientTokenRepository(dataSource);
      useCase = UpdateClientToken(repository, auditStore: auditStore);
    });

    tearDown(() async {
      await db.close();
    });

    Future<({String tokenValue, String tokenId})> seedToken({
      List<ClientTokenRule> rules = const [],
      bool allTables = false,
      bool allViews = false,
      String clientId = 'integration-client',
      String name = 'integration-name',
      Map<String, dynamic> payload = const {'database': 'ERP'},
    }) async {
      final tokenValue = await dataSource.createToken(
        ClientTokenCreateRequest(
          clientId: clientId,
          name: name,
          allTables: allTables,
          allViews: allViews,
          rules: rules,
          payload: payload,
        ),
      );
      final list = await dataSource.listTokens();
      return (tokenValue: tokenValue, tokenId: list.single.id);
    }

    test('metadata-only edit preserves token value, hash and secret store entry', () async {
      final seeded = await seedToken(
        rules: const [
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: 'dbo.users',
            ),
            permissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
            effect: ClientTokenRuleEffect.allow,
          ),
        ],
      );

      final result = await useCase(
        seeded.tokenId,
        const ClientTokenCreateRequest(
          clientId: 'renamed-client',
          name: 'renamed-name',
          allTables: false,
          allViews: false,
          rules: [
            ClientTokenRule(
              resource: DatabaseResource(
                resourceType: DatabaseResourceType.table,
                name: 'dbo.users',
              ),
              permissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
              effect: ClientTokenRuleEffect.allow,
            ),
          ],
          payload: {'database': 'ERP'},
        ),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.outcome, ClientTokenUpdateOutcome.metadataOnly);
      expect(updateResult.tokenValue, isNull);

      final stored = await dataSource.getTokenById(seeded.tokenId);
      expect(stored, isNotNull);
      expect(stored!.tokenValue, equals(seeded.tokenValue));
      expect(stored.clientId, 'renamed-client');
      expect(stored.name, 'renamed-name');

      expect(secretStore.values.values, contains(seeded.tokenValue));
      expect(auditStore.recorded, hasLength(1));
      expect(auditStore.recorded.single.eventType, TokenAuditEventType.metadataUpdate);
    });

    test('policy-changing edit rotates the secret and records rotate audit', () async {
      final seeded = await seedToken();

      final result = await useCase(
        seeded.tokenId,
        const ClientTokenCreateRequest(
          clientId: 'integration-client',
          name: 'integration-name',
          allTables: true,
          allViews: false,
          allPermissions: true,
          rules: [],
          payload: {'database': 'ERP'},
        ),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.outcome, ClientTokenUpdateOutcome.rotated);
      expect(updateResult.tokenValue, isNotNull);
      expect(updateResult.tokenValue, isNot(seeded.tokenValue));

      final stored = await dataSource.getTokenById(seeded.tokenId);
      expect(stored!.tokenValue, equals(updateResult.tokenValue));

      // Old secret hash entry must be cleaned up after rotation.
      expect(
        secretStore.values.values,
        isNot(contains(seeded.tokenValue)),
      );
      expect(auditStore.recorded.single.eventType, TokenAuditEventType.rotate);
    });

    test('no-op edit keeps state untouched and skips audit', () async {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'dbo.users',
        ),
        permissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
        effect: ClientTokenRuleEffect.allow,
      );
      final seeded = await seedToken(rules: const [rule]);
      final beforeRow = await dataSource.getTokenById(seeded.tokenId);

      final result = await useCase(
        seeded.tokenId,
        const ClientTokenCreateRequest(
          clientId: 'integration-client',
          name: 'integration-name',
          allTables: false,
          allViews: false,
          rules: [rule],
          payload: {'database': 'ERP'},
        ),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.outcome, ClientTokenUpdateOutcome.unchanged);
      expect(updateResult.tokenValue, isNull);
      expect(updateResult.version, equals(beforeRow!.version));

      final afterRow = await dataSource.getTokenById(seeded.tokenId);
      expect(afterRow!.tokenValue, equals(beforeRow.tokenValue));
      expect(afterRow.version, equals(beforeRow.version));
      expect(afterRow.updatedAt, equals(beforeRow.updatedAt));
      expect(auditStore.recorded, isEmpty);
    });
  });
}

class _InMemorySecretStore implements ITokenSecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretKey) async {
    values.remove(secretKey);
  }

  @override
  Future<String?> readSecret(String secretKey) async => values[secretKey];

  @override
  Future<void> saveSecret(String secretKey, String tokenValue) async {
    values[secretKey] = tokenValue;
  }
}

class _RecordingAuditStore implements ITokenAuditStore {
  final List<TokenAuditEvent> recorded = <TokenAuditEvent>[];

  @override
  Future<void> record(TokenAuditEvent event) async {
    recorded.add(event);
  }
}
