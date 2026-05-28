import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/agent_action_remote_audit_drift_store.dart';

AgentActionRemoteAuditRecord _record({
  required String id,
  required DateTime occurredAt,
  String method = 'agent.action.run',
  String outcome = 'success',
}) {
  return AgentActionRemoteAuditRecord(
    id: id,
    occurredAtUtc: occurredAt,
    rpcMethod: method,
    outcome: outcome,
    credentialPresent: true,
    actionId: 'action-1',
    executionId: 'exec-$id',
    traceId: 'trace-$id',
    requestedBy: 'tester',
    clientId: 'client-1',
    tokenJti: 'jti-1',
    runtimeInstanceId: 'runtime-1',
    runtimeSessionId: 'session-1',
    idempotencyKey: 'idem-$id',
  );
}

void main() {
  group('AgentActionRemoteAuditDriftStore', () {
    late AppDatabase database;
    late AgentActionRemoteAuditDriftStore store;

    setUp(() {
      database = AppDatabase(executor: NativeDatabase.memory());
      store = AgentActionRemoteAuditDriftStore(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('listRecent returns rows ordered by most recent first', () async {
      await store.append(_record(id: 'a', occurredAt: DateTime.utc(2026, 5, 15, 10)));
      await store.append(_record(id: 'b', occurredAt: DateTime.utc(2026, 5, 15, 11)));
      await store.append(_record(id: 'c', occurredAt: DateTime.utc(2026, 5, 15, 12)));

      final rows = await store.listRecent();

      expect(rows.map((r) => r.id).toList(), ['c', 'b', 'a']);
    });

    group('deleteWhereOccurredBefore', () {
      test('should return 0 and skip query when limit <= 0', () async {
        await store.append(_record(id: 'a', occurredAt: DateTime.utc(2026, 5, 15)));

        final deleted = await store.deleteWhereOccurredBefore(
          cutoffUtc: DateTime.utc(2030),
          limit: 0,
        );

        expect(deleted, 0);
        // Row was not touched.
        final remaining = await store.listRecent();
        expect(remaining, hasLength(1));
      });

      test('should return 0 when no rows match the cutoff', () async {
        await store.append(_record(id: 'recent', occurredAt: DateTime.utc(2026, 5, 15)));

        final deleted = await store.deleteWhereOccurredBefore(
          cutoffUtc: DateTime.utc(2020),
          limit: 100,
        );

        expect(deleted, 0);
        final remaining = await store.listRecent();
        expect(remaining, hasLength(1));
      });

      test('should delete only rows older than the cutoff and respect limit', () async {
        await store.append(_record(id: 'old-1', occurredAt: DateTime.utc(2026, 5, 10)));
        await store.append(_record(id: 'old-2', occurredAt: DateTime.utc(2026, 5, 11)));
        await store.append(_record(id: 'old-3', occurredAt: DateTime.utc(2026, 5, 12)));
        await store.append(_record(id: 'recent', occurredAt: DateTime.utc(2026, 6)));

        final deleted = await store.deleteWhereOccurredBefore(
          cutoffUtc: DateTime.utc(2026, 5, 20),
          limit: 2,
        );

        expect(deleted, 2);
        final remaining = await store.listRecent();
        // Must keep the most recent + the oldest one beyond the limit.
        expect(remaining.map((r) => r.id), containsAll(<String>['recent']));
        expect(remaining, hasLength(2));
      });

      test('should delete in ascending-occurredAt order so newest aged-out rows survive', () async {
        await store.append(_record(id: 'old-1', occurredAt: DateTime.utc(2026, 5, 10)));
        await store.append(_record(id: 'old-2', occurredAt: DateTime.utc(2026, 5, 11)));
        await store.append(_record(id: 'old-3', occurredAt: DateTime.utc(2026, 5, 12)));

        final deleted = await store.deleteWhereOccurredBefore(
          cutoffUtc: DateTime.utc(2026, 6),
          limit: 2,
        );

        expect(deleted, 2);
        final remaining = await store.listRecent();
        expect(remaining.map((r) => r.id), ['old-3']);
      });
    });
  });
}
