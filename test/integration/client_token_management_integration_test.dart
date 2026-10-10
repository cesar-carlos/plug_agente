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

  test('creation returns the persisted identity without a follow-up lookup', () async {
    final created = (await CreateClientToken(repository).createWithIdentity(_request)).getOrThrow();
    final row = (await source.findRowById(created.tokenId))!;
    expect(row.tokenHash, hashStoredClientToken(created.tokenValue));
    expect(row.version, created.version);
    expect(row.tokenValue, isNot(created.tokenValue));
    expect((await repository.countActiveTokens()).getOrThrow(), 1);
  });

  for (final action in ['revoke', 'delete']) {
    test('$action invalidates off-page feedback even when the reconciliation query fails', () async {
      expect((await provider.createToken(_request, refreshTokens: false)).isSuccess(), isTrue);
      final feedback = provider.secretFeedback!;
      await provider.applyListQuery(const ClientTokenListQuery(clientIdContains: 'no-match'));
      expect(provider.tokens, isEmpty);
      expect(provider.secretFeedback, same(feedback));
      source.failPages = true;
      final result = action == 'revoke'
          ? await provider.revokeToken(feedback.tokenId)
          : await provider.deleteToken(feedback.tokenId);
      expect(result.isSuccess(), isTrue);
      expect(provider.secretFeedback, isNull);
      expect(provider.lastCreatedToken, isNull);
      expect(provider.isListStale, isTrue);
      expect(provider.hasListLoadError, isTrue);
    });

    test('failed $action preserves feedback until the write is confirmed', () async {
      await provider.createToken(_request, refreshTokens: false);
      final feedback = provider.secretFeedback!;
      final operation = action == 'revoke' ? 'UPDATE' : 'DELETE';
      await db.customStatement(
        "CREATE TRIGGER reject_mutation BEFORE $operation ON client_token_cache_table BEGIN SELECT RAISE(ABORT, 'injected write failure'); END",
      );
      final result = action == 'revoke'
          ? await provider.revokeToken(feedback.tokenId)
          : await provider.deleteToken(feedback.tokenId);
      expect(result.exceptionOrNull(), isA<domain.DatabaseFailure>());
      expect(provider.secretFeedback, same(feedback));
      expect(provider.isSecretFeedbackCurrent(feedback), isTrue);
    });
  }

  test('an unrelated deletion preserves the visible secret feedback', () async {
    final other = (await repository.createTokenWithIdentity(_request)).getOrThrow();
    await provider.createToken(_request);
    final feedback = provider.secretFeedback!;
    await provider.deleteToken(other.tokenId);
    expect(provider.secretFeedback, same(feedback));
  });

  test('metadata edits preserve the current secret and update its audit identity', () async {
    await provider.createToken(_request, refreshTokens: false);
    final previous = provider.secretFeedback!;
    const renamed = ClientTokenCreateRequest(
      clientId: 'renamed',
      allTables: true,
      allViews: true,
      allPermissions: true,
      rules: [],
    );
    await provider.updateToken(previous.tokenId, renamed, expectedVersion: previous.version, refreshTokens: false);
    expect(provider.secretFeedback!.tokenValue, previous.tokenValue);
    expect(provider.secretFeedback!.clientId, 'renamed');
    expect(provider.secretFeedback!.version, previous.version + 1);
    expect(provider.isSecretFeedbackCurrent(previous), isFalse);
  });

  test('rotation replaces feedback and a failed rotation preserves the previous credential', () async {
    await provider.createToken(_request, refreshTokens: false);
    final previous = provider.secretFeedback!;
    const policy = ClientTokenCreateRequest(
      clientId: 'client',
      allTables: true,
      allViews: false,
      globalPermissions: ClientPermissionSet.fullAccess,
      rules: [],
    );
    source.failUpdates = true;
    expect((await provider.updateToken(previous.tokenId, policy, expectedVersion: 1)).isError(), isTrue);
    expect(provider.secretFeedback, same(previous));
    source.failUpdates = false;
    expect((await provider.updateToken(previous.tokenId, policy, expectedVersion: 1)).isSuccess(), isTrue);
    expect(provider.secretFeedback!.tokenId, previous.tokenId);
    expect(provider.secretFeedback!.tokenValue, isNot(previous.tokenValue));
    expect(provider.secretFeedback!.isCreation, isFalse);
    expect(provider.isSecretFeedbackCurrent(previous), isFalse);
  });

  test('reloading a revoked credential invalidates its feedback without reading secrets', () async {
    await provider.createToken(_request, refreshTokens: false);
    final feedback = provider.secretFeedback!;
    await repository.revokeToken(feedback.tokenId);
    final reads = secrets.reads;
    await provider.loadTokens();
    expect(provider.secretFeedback, isNull);
    expect(secrets.reads, reads);
  });

  test('dismissal releases both copies of the displayed credential', () async {
    await provider.createToken(_request, refreshTokens: false);
    provider.dismissSecretFeedback();
    expect(provider.secretFeedback, isNull);
    expect(provider.lastCreatedToken, isNull);
  });

  test('clearing mutation errors preserves page and global-count failures', () async {
    source.failCounts = true;
    await provider.refreshActiveTokenCount();
    source.failPages = true;
    await provider.loadTokens();
    secrets.available = false;
    await provider.createToken(_request);
    expect(provider.mutationError, isNotEmpty);
    provider.clearMutationError();
    expect(provider.mutationError, isEmpty);
    expect(provider.hasListLoadError, isTrue);
    source.failPages = false;
    await provider.loadTokens();
    expect(provider.hasListLoadError, isFalse);
    expect(provider.listError, isNotEmpty);
    source.failCounts = false;
    await provider.refreshActiveTokenCount();
    expect(provider.listError, isEmpty);
  });

  for (final column in ['payload_json', 'rules_json', 'global_permissions_json']) {
    test('administration recovers corrupt $column without accepting its authorization policy', () async {
      final badSecret = (await repository.createToken(_request)).getOrThrow();
      await repository.createToken(_request);
      final badHash = hashStoredClientToken(badSecret);
      final bad = (await source.findRowByHash(badHash))!;
      await db.customStatement('UPDATE client_token_cache_table SET $column = ? WHERE id = ?', [
        'invalid JSON',
        bad.id,
      ]);
      secrets.reads = 0;
      expect((await provider.loadTokens()).isSuccess(), isTrue);
      expect(provider.totalCount, 2);
      final entry = provider.tokens.singleWhere((token) => token.id == bad.id);
      expect(entry.hasInvalidPolicy, isTrue);
      expect(entry.globalPermissions, ClientPermissionSet.none);
      expect(entry.allTables || entry.allViews || entry.allPermissions, isFalse);
      expect(entry.rules, isEmpty);
      expect(entry.tokenValue, isNull);
      expect(entry.copyWith(isRevoked: true).hasInvalidPolicy, isTrue);
      expect(provider.tokens.where((token) => !token.hasInvalidPolicy), hasLength(1));
      final denied = await repository.getTokenPolicySummaryByHash(badHash);
      expect(denied.exceptionOrNull(), isA<domain.ConfigurationFailure>());
      expect((denied.exceptionOrNull()! as domain.ConfigurationFailure).code, 'CLIENT_TOKEN_POLICY_INVALID');
      expect((await repository.listTokens()).exceptionOrNull(), isA<domain.ConfigurationFailure>());
      expect(secrets.reads, 0);
      expect((await provider.revokeToken(bad.id)).isSuccess(), isTrue);
      expect(provider.tokens.singleWhere((token) => token.id == bad.id).isRevoked, isTrue);
      expect(provider.activeTokenCount, 1);
      expect((await provider.deleteToken(bad.id)).isSuccess(), isTrue);
      expect(provider.totalCount, 1);
      expect(provider.tokens.single.hasInvalidPolicy, isFalse);
      expect(await source.findRowById(bad.id), isNull);
    });
  }

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

  for (final failWrite in [false, true]) {
    test('latest filter is reconciled after ${failWrite ? 'failed' : 'successful'} mutation with SQLite', () async {
      await repository.createToken(_request);
      await provider.loadTokens();
      final release = Completer<void>();
      final writing = Completer<void>();
      secrets.failWrite = failWrite;
      secrets.beforeWrite = () async {
        writing.complete();
        await release.future;
      };
      final mutation = provider.createToken(_request, refreshTokens: false);
      await writing.future;
      final superseded = provider.applyListQuery(const ClientTokenListQuery(clientIdContains: 'client'));
      final latest = provider.applyListQuery(const ClientTokenListQuery(clientIdContains: 'not-present'));
      expect((await superseded).exceptionOrNull().toString(), contains('SUPERSEDED'));
      expect((await provider.loadTokens()).exceptionOrNull().toString(), contains('OPERATION_BLOCKED'));
      release.complete();
      expect((await mutation).isError(), failWrite);
      expect((await latest).isSuccess(), isTrue);
      expect(provider.tokens, isEmpty);
      expect(provider.currentPage, 1);
      expect(provider.isQueryPending, isFalse);
      expect(provider.isTokenMutationInProgress, isFalse);
      expect((await repository.listTokens()).getOrThrow(), hasLength(failWrite ? 1 : 2));
    });
  }

  test('a mutation with automatic refresh off reapplies a filter already in flight', () async {
    await repository.createToken(_request);
    await provider.loadTokens();
    final release = Completer<void>();
    source.delayPage = release;
    source.snapshotReady = Completer<void>();
    final oldFilter = provider.applyListQuery(const ClientTokenListQuery(clientIdContains: 'not-present'));
    await source.snapshotReady!.future;
    expect((await provider.createToken(_request, refreshTokens: false)).isSuccess(), isTrue);
    expect(provider.tokens, isEmpty);
    expect(provider.activeTokenCount, 2);
    expect(provider.isListStale, isFalse);
    release.complete();
    expect((await oldFilter).exceptionOrNull().toString(), contains('SUPERSEDED'));
    expect(provider.tokens, isEmpty);
  });

  test('filter queued during an internal refresh supersedes its delayed snapshot', () async {
    await repository.createToken(_request);
    final release = Completer<void>();
    source.delayPage = release;
    source.snapshotReady = Completer<void>();
    final mutation = provider.createToken(_request);
    await source.snapshotReady!.future;
    final filtered = provider.applyListQuery(const ClientTokenListQuery(clientIdContains: 'not-present'));
    release.complete();
    expect((await mutation).isSuccess(), isTrue);
    expect((await filtered).isSuccess(), isTrue);
    expect(provider.tokens, isEmpty);
    expect(provider.activeTokenCount, 2);
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
    expect(provider.hasListLoadError, isFalse);
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
