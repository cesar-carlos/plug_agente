import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/count_active_client_tokens.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/get_client_token_secret.dart';
import 'package:plug_agente/application/use_cases/list_client_token_page.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_page.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';

import '../helpers/memory_token_secret_store.dart';

const _request = ClientTokenCreateRequest(
  clientId: 'client',
  allTables: true,
  allViews: true,
  allPermissions: true,
  rules: [],
);

class _ControlledDataSource extends ClientTokenLocalDataSource {
  _ControlledDataSource(super._database);
  Completer<void>? delayPage;
  Completer<void>? snapshotReady;
  bool failUpdates = false;
  bool failPages = false;
  bool failCounts = false;

  @override
  Future<int> countActiveTokens() {
    if (failCounts) throw Exception('injected count failure');
    return super.countActiveTokens();
  }

  int mappedRows = 0;

  @override
  Future<ClientTokenPage> listTokenPage({required ClientTokenListQuery query}) async {
    if (failPages) throw Exception('injected page failure');
    final delay = delayPage;
    delayPage = null;
    final snapshot = await super.listTokenPage(query: query);
    if (delay != null) {
      snapshotReady?.complete();
      await delay.future;
    }
    return snapshot;
  }

  @override
  ClientTokenSummary mapRowToSummaryWithoutTokenValue(ClientTokenCacheData row) {
    mappedRows++;
    return super.mapRowToSummaryWithoutTokenValue(row);
  }

  @override
  Future<int> applyTokenUpdate({
    required String tokenId,
    required int expectedVersion,
    required ClientTokenCacheTableCompanion companion,
  }) {
    if (failUpdates) throw Exception('injected database failure');
    return super.applyTokenUpdate(tokenId: tokenId, expectedVersion: expectedVersion, companion: companion);
  }
}

void main() {
  late AppDatabase db;
  late MemoryTokenSecretStore secrets;
  late _ControlledDataSource source;
  late ClientTokenRepository repository;
  late ClientTokenProvider provider;
  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    secrets = MemoryTokenSecretStore();
    source = _ControlledDataSource(db);
    repository = ClientTokenRepository(source, secretStore: secrets);
    provider = ClientTokenProvider(
      CreateClientToken(repository),
      UpdateClientToken(repository),
      ListClientTokenPage(repository),
      GetClientTokenSecret(repository),
      RevokeClientToken(repository),
      DeleteClientToken(repository),
      countActiveClientTokens: CountActiveClientTokens(repository),
    );
  });
  tearDown(() async {
    provider.dispose();
    await db.close();
  });

  for (final fault in ['write', 'read', 'unconfirmed', 'unavailable']) {
    test('secure storage $fault failure never confirms a new SQLite credential', () async {
      secrets.failWrite = fault == 'write';
      secrets.failRead = fault == 'read';
      secrets.unconfirmed = fault == 'unconfirmed';
      secrets.available = fault != 'unavailable';
      final result = await repository.createToken(_request);
      expect(result.exceptionOrNull(), isA<domain.ConfigurationFailure>());
      expect(await db.select(db.clientTokenCacheTable).get(), isEmpty);
      expect(secrets.values, isEmpty);
    });
  }

  for (final fault in ['secure', 'database']) {
    test('rotation $fault failure preserves old credential, version and policy', () async {
      final oldToken = (await repository.createToken(_request)).getOrThrow();
      final original = await db.select(db.clientTokenCacheTable).getSingle();
      secrets.failWrite = fault == 'secure';
      source.failUpdates = fault == 'database';
      final result = await repository.updateToken(
        original.id,
        const ClientTokenCreateRequest(
          clientId: 'client',
          allTables: true,
          allViews: true,
          rules: [],
          globalPermissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
        ),
        expectedVersion: original.version,
      );
      expect(result.isError(), isTrue);
      final current = await db.select(db.clientTokenCacheTable).getSingle();
      expect(current.tokenHash, original.tokenHash);
      expect(current.version, original.version);
      expect(current.globalPermissionsJson, original.globalPermissionsJson);
      expect(secrets.values, {original.tokenHash: oldToken});
    });
  }

  test('legacy plaintext remains readable until secure migration is confirmed', () async {
    await db
        .into(db.clientTokenCacheTable)
        .insert(
          ClientTokenCacheTableCompanion.insert(
            id: 'legacy',
            clientId: 'legacy',
            createdAt: DateTime.utc(2026),
            syncedAt: DateTime.utc(2026),
            tokenHash: Value(hashStoredClientToken('legacy-value')),
            tokenValue: const Value('legacy-value'),
          ),
        );
    secrets.failWrite = true;
    expect((await repository.getTokenSecret('legacy')).getOrThrow().tokenValue, 'legacy-value');
    expect((await source.findRowById('legacy'))!.tokenValue, 'legacy-value');
    secrets.failWrite = false;
    expect((await repository.getTokenSecret('legacy')).getOrThrow().tokenValue, 'legacy-value');
    expect((await source.findRowById('legacy'))!.tokenValue, '__secure_storage__');
  });

  test('legacy migration does not overwrite a token changed during secure persistence', () async {
    await db
        .into(db.clientTokenCacheTable)
        .insert(
          ClientTokenCacheTableCompanion.insert(
            id: 'legacy-race',
            clientId: 'legacy',
            createdAt: DateTime.utc(2026),
            syncedAt: DateTime.utc(2026),
            tokenHash: Value(hashStoredClientToken('old-value')),
            tokenValue: const Value('old-value'),
          ),
        );
    secrets.beforeWrite = () async {
      await source.applyTokenUpdate(
        tokenId: 'legacy-race',
        expectedVersion: 1,
        companion: const ClientTokenCacheTableCompanion(
          tokenHash: Value('new-hash'),
          tokenValue: Value(null),
          version: Value(2),
        ),
      );
    };
    final lookup = await repository.getTokenSecret('legacy-race');
    expect(lookup.exceptionOrNull(), isA<domain.ValidationFailure>());
    final current = (await source.findRowById('legacy-race'))!;
    expect(current.tokenHash, 'new-hash');
    expect(current.tokenValue, isNull);
  });

  test('legacy migration cannot return a secret after deletion during secure persistence', () async {
    await db
        .into(db.clientTokenCacheTable)
        .insert(
          ClientTokenCacheTableCompanion.insert(
            id: 'legacy-deleted',
            clientId: 'legacy',
            createdAt: DateTime.utc(2026),
            syncedAt: DateTime.utc(2026),
            tokenHash: Value(hashStoredClientToken('old-value')),
            tokenValue: const Value('old-value'),
          ),
        );
    secrets.beforeWrite = () async {
      await repository.deleteToken('legacy-deleted');
    };
    final lookup = await repository.getTokenSecret('legacy-deleted');
    expect(lookup.exceptionOrNull(), isA<domain.ValidationFailure>());
    expect(await source.findRowById('legacy-deleted'), isNull);
  });

  test('replacement verifies secrets before changing SQLite rows', () async {
    final value = (await repository.createToken(_request)).getOrThrow();
    final row = (await repository.listTokens()).getOrThrow().single;
    secrets.unconfirmed = true;
    await expectLater(
      repository.replaceTokens([row.copyWith(name: 'changed', tokenValue: 'replacement')]),
      throwsA(isA<domain.ConfigurationFailure>()),
    );
    expect((await source.findRowById(row.id))!.name, row.name);
    expect(secrets.values, {repository.hashTokenForLookup(value): value});
  });

  for (final mutation in ['revoke', 'delete']) {
    test('real SQLite delayed snapshot cannot overwrite $mutation', () async {
      await repository.createToken(_request);
      await provider.loadTokens();
      final id = provider.tokens.single.id;
      final release = Completer<void>();
      source.delayPage = release;
      source.snapshotReady = Completer<void>();
      final oldLoad = provider.loadTokens();
      await source.snapshotReady!.future;
      final result = mutation == 'revoke' ? await provider.revokeToken(id) : await provider.deleteToken(id);
      expect(result.isSuccess(), isTrue);
      release.complete();
      expect((await oldLoad).isError(), isTrue);
      if (mutation == 'revoke') {
        expect(provider.tokens.single.isRevoked, isTrue);
      } else {
        expect(provider.tokens, isEmpty);
      }
      expect(provider.activeTokenCount, 0);
    });
  }

  test('confirmed create stays successful when refresh fails and retry only reads', () async {
    await provider.loadTokens();
    source.failPages = true;
    final saved = await provider.createToken(_request);
    expect(saved.isSuccess(), isTrue);
    expect(provider.mutationError, isEmpty);
    expect(provider.listError, isNotEmpty);
    expect(provider.isListStale, isTrue);
    expect(provider.lastCreatedToken, isNotNull);
    expect(provider.activeTokenCount, 1);
    expect((await repository.listTokens()).getOrThrow(), hasLength(1));
    source.failPages = false;
    await provider.loadTokens();
    expect(provider.tokens, hasLength(1));
    expect(provider.isListStale, isFalse);
  });

  test('one mutation owns admission through secure write and refresh', () async {
    final release = Completer<void>();
    final writing = Completer<void>();
    secrets.beforeWrite = () async {
      writing.complete();
      await release.future;
    };
    final first = provider.createToken(_request);
    await writing.future;
    for (final blocked in [
      await provider.createToken(_request),
      await provider.updateToken('id', _request),
      await provider.revokeToken('id'),
      await provider.deleteToken('id'),
      await provider.loadTokens(),
    ]) {
      expect(blocked.exceptionOrNull().toString(), contains('OPERATION_BLOCKED'));
    }
    release.complete();
    expect((await first).isSuccess(), isTrue);
    expect((await repository.listTokens()).getOrThrow(), hasLength(1));
    expect(provider.isTokenMutationInProgress, isFalse);
  });

  test('mutation remains exclusive while its internal page refresh is pending', () async {
    final release = Completer<void>();
    source.delayPage = release;
    source.snapshotReady = Completer<void>();
    final saving = provider.createToken(_request);
    await source.snapshotReady!.future;
    expect(provider.isCreating, isTrue);
    expect((await provider.createToken(_request)).isError(), isTrue);
    expect((await provider.loadTokens()).isError(), isTrue);
    release.complete();
    expect((await saving).isSuccess(), isTrue);
    expect(provider.tokens, hasLength(1));
    expect(provider.isCreating, isFalse);
  });

  test('version conflict after secret confirmation cleans only the new key', () async {
    await repository.createToken(_request);
    final old = (await source.loadAllRowsById()).values.single;
    secrets.beforeWrite = () async {
      await source.applyTokenUpdate(
        tokenId: old.id,
        expectedVersion: old.version,
        companion: ClientTokenCacheTableCompanion(version: Value(old.version + 1)),
      );
    };
    final result = await repository.updateToken(
      old.id,
      const ClientTokenCreateRequest(
        clientId: 'changed',
        allTables: true,
        allViews: true,
        globalPermissions: ClientPermissionSet.none,
        rules: [],
      ),
      expectedVersion: old.version,
    );
    expect(result.isError(), isTrue);
    final row = (await source.loadAllRowsById()).values.single;
    expect(row.tokenHash, old.tokenHash);
    expect(row.allPermissions, old.allPermissions);
    expect(row.version, old.version + 1);
    expect(secrets.values.keys, [old.tokenHash]);
  });

  test('automatic refresh off still updates global statistics and forces refresh on revoke', () async {
    await provider.loadTokens();
    await provider.createToken(_request, refreshTokens: false);
    expect(provider.tokens, isEmpty);
    expect(provider.activeTokenCount, 1);
    expect(provider.isListStale, isTrue);
    final id = (await source.loadAllRowsById()).keys.single;
    await provider.revokeToken(id);
    expect(provider.tokens.single.isRevoked, isTrue);
    expect(provider.activeTokenCount, 0);
    expect(provider.isListStale, isFalse);
  });

  test('newer list query wins without stale completion changing loading or data', () async {
    await repository.createToken(_request);
    final release = Completer<void>();
    source.delayPage = release;
    source.snapshotReady = Completer<void>();
    final oldQuery = provider.loadTokens();
    await source.snapshotReady!.future;
    await provider.loadTokens(query: const ClientTokenListQuery(clientIdContains: 'not-present'));
    var changes = 0;
    provider.addListener(() => changes++);
    release.complete();
    expect((await oldQuery).isError(), isTrue);
    expect(changes, 0);
    expect(provider.tokens, isEmpty);
    expect(provider.listError, isEmpty);
    expect(provider.isLoading, isFalse);
  });

  test('failed global count preserves the last count and a confirmed mutation result', () async {
    await provider.createToken(_request);
    expect(provider.activeTokenCount, 1);
    source.failCounts = true;
    final result = await provider.createToken(_request);
    expect(result.isSuccess(), isTrue);
    expect(provider.mutationError, isEmpty);
    expect(provider.listError, isNotEmpty);
    expect(provider.activeTokenCount, 1);
    expect(provider.tokens, hasLength(2));
    source.failCounts = false;
    await provider.refreshActiveTokenCount();
    expect(provider.activeTokenCount, 2);
    expect(provider.listError, isEmpty);
  });

  test('page validation returns typed failures and empty results have one effective page', () async {
    final useCase = ListClientTokenPage(repository);
    for (final query in [const ClientTokenListQuery(page: 0), const ClientTokenListQuery(pageSize: 51)]) {
      expect((await useCase(query: query)).exceptionOrNull(), isA<domain.ValidationFailure>());
    }
    final page = (await useCase(query: const ClientTokenListQuery(page: 100))).getOrThrow();
    expect(page.page, 1);
    expect(page.totalPages, 1);
    expect(page.totalCount, 0);
    expect(page.items, isEmpty);
  });

  test('pagination clamps last page, maps bounded rows and ignores filters for global count', () async {
    await db.batch((batch) {
      batch.insertAll(
        db.clientTokenCacheTable,
        List.generate(
          101,
          (index) => ClientTokenCacheTableCompanion.insert(
            id: 'id-${index.toString().padLeft(3, '0')}',
            clientId: 'client',
            tokenHash: Value('hash-$index'),
            createdAt: DateTime.utc(2026),
            syncedAt: DateTime.utc(2026),
            isRevoked: Value(index == 0),
          ),
        ),
      );
    });
    await provider.refreshActiveTokenCount();
    await provider.loadTokens(query: const ClientTokenListQuery(page: 3, pageSize: 50));
    expect(provider.tokens.single.id, 'id-100');
    source.mappedRows = 0;
    final id = provider.tokens.single.id;
    await provider.deleteToken(id);
    expect(provider.currentPage, 2);
    expect(provider.totalCount, 100);
    expect(provider.tokens, hasLength(50));
    expect(source.mappedRows, 50);
    secrets.reads = 0;
    await provider.loadTokens(
      query: const ClientTokenListQuery(status: ClientTokenStatusFilter.revoked, page: 1, pageSize: 25),
    );
    expect(provider.tokens, hasLength(1));
    expect(provider.activeTokenCount, 99);
    expect(secrets.reads, 0);
  });
}
