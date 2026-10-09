import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';

import '../helpers/memory_token_secret_store.dart';

class _Flags extends Mock implements FeatureFlags {}

const _full = ClientTokenCreateRequest(
  clientId: 'review',
  allTables: true,
  allViews: true,
  allPermissions: true,
  rules: [],
);

void main() {
  late AppDatabase db;
  late MemoryTokenSecretStore secrets;
  late ClientTokenLocalDataSource source;
  late ClientTokenRepository repository;
  late AuthorizeSqlOperation authorize;
  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    secrets = MemoryTokenSecretStore();
    source = ClientTokenLocalDataSource(db);
    repository = ClientTokenRepository(source, secretStore: secrets);
    final flags = _Flags();
    when(() => flags.enableSocketJwksValidation).thenReturn(false);
    when(() => flags.enableSocketRevokedTokenInSession).thenReturn(false);
    authorize = AuthorizeSqlOperation(
      SqlOperationClassifier(),
      ClientTokenValidationService(AuthorizationPolicyResolver(flags, clientTokenRepository: repository)),
    );
  });
  tearDown(() async {
    await db.close();
  });

  test('corrupt stored payload cannot remove database restriction', () async {
    final token = (await repository.createToken(
      const ClientTokenCreateRequest(
        clientId: 'review',
        allTables: true,
        allViews: true,
        allPermissions: true,
        rules: [],
        payload: {'database': 'ERP'},
      ),
    )).getOrThrow();
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users', requestDatabase: 'other')).isError(), isTrue);
    final row = await db.select(db.clientTokenCacheTable).getSingle();
    await (db.update(db.clientTokenCacheTable)..where((t) => t.id.equals(row.id))).write(
      const ClientTokenCacheTableCompanion(payloadJson: Value('{"database":')),
    );
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users', requestDatabase: 'other')).isError(), isTrue);
    expect((await repository.listTokens()).exceptionOrNull(), isA<domain.ConfigurationFailure>());
  });

  test('corrupt stored permissions cannot restore legacy read access', () async {
    final token = (await repository.createToken(
      const ClientTokenCreateRequest(
        clientId: 'review',
        allTables: true,
        allViews: false,
        rules: [],
        globalPermissions: ClientPermissionSet(canRead: false, canUpdate: true, canDelete: false),
      ),
    )).getOrThrow();
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isError(), isTrue);
    final row = await db.select(db.clientTokenCacheTable).getSingle();
    await (db.update(db.clientTokenCacheTable)..where((t) => t.id.equals(row.id))).write(
      const ClientTokenCacheTableCompanion(globalPermissionsJson: Value('{')),
    );
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isError(), isTrue);
  });

  test('invalid stored permission type returns a typed failure', () async {
    await repository.createToken(_full);
    final row = await db.select(db.clientTokenCacheTable).getSingle();
    await (db.update(db.clientTokenCacheTable)..where((t) => t.id.equals(row.id))).write(
      const ClientTokenCacheTableCompanion(globalPermissionsJson: Value('{"read":"yes"}')),
    );
    expect((await repository.listTokens()).exceptionOrNull(), isA<domain.ConfigurationFailure>());
    expect(
      (await repository.getTokenPolicySummaryByHash(row.tokenHash)).exceptionOrNull(),
      isA<domain.ConfigurationFailure>(),
    );
  });

  test('deletion during legacy migration cleans up the orphan secret', () async {
    const token = 'review-legacy-secret';
    final hash = repository.hashTokenForLookup(token);
    final now = DateTime.now().toUtc();
    await db
        .into(db.clientTokenCacheTable)
        .insert(
          ClientTokenCacheTableCompanion.insert(
            id: 'legacy',
            clientId: 'review',
            createdAt: now,
            syncedAt: now,
            tokenHash: Value(hash),
            tokenValue: const Value(token),
          ),
        );
    secrets.beforeWrite = () async {
      await repository.deleteToken('legacy');
    };
    expect((await repository.getTokenSecret('legacy')).isError(), isTrue);
    expect(await source.findRowById('legacy'), isNull);
    expect(secrets.values, isEmpty);
  });

  test('stale ID secret cannot be returned or migrated under current credential hash', () async {
    final currentToken = (await repository.createToken(_full)).getOrThrow();
    final row = await db.select(db.clientTokenCacheTable).getSingle();
    secrets.values.remove(row.tokenHash);
    const staleToken = 'review-old-legacy-secret';
    secrets.values[row.id] = staleToken;
    expect(repository.hashTokenForLookup(staleToken), isNot(row.tokenHash));
    final failure = (await repository.getTokenSecret(row.id)).exceptionOrNull()! as domain.ConfigurationFailure;
    expect(failure.code, 'CLIENT_TOKEN_SECRET_MISMATCH');
    expect(failure.message, isNot(contains(staleToken)));
    expect(secrets.values.containsKey(row.tokenHash), isFalse);
    expect((await source.findRowById(row.id))!.tokenHash, repository.hashTokenForLookup(currentToken));
  });

  for (final field in ['payload', 'permissions', 'rules']) {
    for (final invalid in ['null', '[]', '42', '"sensitive-payload"']) {
      if (field == 'rules' && invalid == '[]') continue;
      test('invalid stored $field root $invalid never authorizes', () async {
        final token = (await repository.createToken(_full)).getOrThrow();
        final row = await db.select(db.clientTokenCacheTable).getSingle();
        await (db.update(db.clientTokenCacheTable)..where((t) => t.id.equals(row.id))).write(
          ClientTokenCacheTableCompanion(
            payloadJson: field == 'payload' ? Value(invalid) : const Value.absent(),
            globalPermissionsJson: field == 'permissions' ? Value(invalid) : const Value.absent(),
            rulesJson: field == 'rules' ? Value(invalid) : const Value.absent(),
          ),
        );
        final failure =
            (await repository.getTokenPolicySummaryByHash(row.tokenHash)).exceptionOrNull()!
                as domain.ConfigurationFailure;
        expect(failure.code, 'CLIENT_TOKEN_POLICY_INVALID');
        expect(failure.toString(), isNot(contains('sensitive-payload')));
        expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isError(), isTrue);
      });
    }
  }

  test('malformed deny rule cannot be silently removed from a valid allow list', () async {
    final token = (await repository.createToken(_full)).getOrThrow();
    final row = await db.select(db.clientTokenCacheTable).getSingle();
    await (db.update(db.clientTokenCacheTable)..where((t) => t.id.equals(row.id))).write(
      const ClientTokenCacheTableCompanion(
        rulesJson: Value('[{"effect":"deny_typo","resource":"dbo.users","read":true}]'),
      ),
    );
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isError(), isTrue);
  });

  for (final location in ['hash', 'plaintext']) {
    test('mismatched $location secret remains unavailable without modifying SQLite', () async {
      await repository.createToken(_full);
      final row = await db.select(db.clientTokenCacheTable).getSingle();
      const stale = 'unrelated-secret';
      if (location == 'hash') {
        secrets.values[row.tokenHash] = stale;
      } else {
        secrets.values.clear();
        await (db.update(
          db.clientTokenCacheTable,
        )..where((t) => t.id.equals(row.id))).write(const ClientTokenCacheTableCompanion(tokenValue: Value(stale)));
      }
      final failure = (await repository.getTokenSecret(row.id)).exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.code, 'CLIENT_TOKEN_SECRET_MISMATCH');
      expect((await source.findRowById(row.id))!.tokenHash, row.tokenHash);
      if (location == 'plaintext') expect(secrets.values, isEmpty);
    });
  }

  Future<String> insertLegacy() async {
    const value = 'valid-legacy-secret';
    final hash = repository.hashTokenForLookup(value);
    final now = DateTime.now().toUtc();
    await db
        .into(db.clientTokenCacheTable)
        .insert(
          ClientTokenCacheTableCompanion.insert(
            id: 'legacy',
            clientId: 'review',
            createdAt: now,
            syncedAt: now,
            tokenHash: Value(hash),
            tokenValue: const Value(value),
          ),
        );
    return hash;
  }

  test('migration cleanup preserves a hash still referenced after metadata change', () async {
    final hash = await insertLegacy();
    secrets.beforeWrite = () async {
      secrets.beforeWrite = null;
      await source.applyTokenUpdate(
        tokenId: 'legacy',
        expectedVersion: 1,
        companion: const ClientTokenCacheTableCompanion(version: Value(2)),
      );
    };
    expect((await repository.getTokenSecret('legacy')).isError(), isTrue);
    expect(secrets.values[hash], 'valid-legacy-secret');
    expect((await repository.getTokenSecret('legacy')).getOrThrow().tokenValue, 'valid-legacy-secret');
  });

  test('migration cleanup preserves a credential reassigned to another row', () async {
    final hash = await insertLegacy();
    secrets.beforeWrite = () async {
      secrets.beforeWrite = null;
      await repository.deleteToken('legacy');
      final now = DateTime.now().toUtc();
      await db
          .into(db.clientTokenCacheTable)
          .insert(
            ClientTokenCacheTableCompanion.insert(
              id: 'replacement',
              clientId: 'review',
              createdAt: now,
              syncedAt: now,
              tokenHash: Value(hash),
              tokenValue: const Value('__secure_storage__'),
            ),
          );
    };
    expect((await repository.getTokenSecret('legacy')).isError(), isTrue);
    expect(secrets.values[hash], 'valid-legacy-secret');
    expect((await repository.getTokenSecret('replacement')).getOrThrow().tokenValue, 'valid-legacy-secret');
  });

  test('rotation during migration removes old orphan and preserves new credential', () async {
    final hash = await insertLegacy();
    secrets.beforeWrite = () async {
      secrets.beforeWrite = null;
      expect((await repository.updateToken('legacy', _full)).isSuccess(), isTrue);
    };
    expect((await repository.getTokenSecret('legacy')).isError(), isTrue);
    final current = (await source.findRowById('legacy'))!;
    expect(current.tokenHash, isNot(hash));
    expect(secrets.values.containsKey(hash), isFalse);
    expect(secrets.values.containsKey(current.tokenHash), isTrue);
    expect((await repository.getTokenSecret('legacy')).getOrThrow().isAvailable, isTrue);
  });
}
