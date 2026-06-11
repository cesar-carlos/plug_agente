import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/sql_db_streaming_auto_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  group('SqlDbStreamingAutoPolicy', () {
    late MockFeatureFlags featureFlags;
    late SqlDbStreamingAutoPolicy policy;
    var now = DateTime(2026, 6, 10, 12);

    setUp(() {
      featureFlags = MockFeatureFlags();
      when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(true);
      when(() => featureFlags.enableSocketStreamingChunks).thenReturn(false);
      policy = SqlDbStreamingAutoPolicy(
        envGetter: (_) => null,
        clock: () => now,
      );
    });

    QueryRequest queryRequest({String sql = 'SELECT * FROM users'}) {
      return QueryRequest(
        id: 'q-1',
        agentId: 'agent-1',
        query: sql,
        timestamp: DateTime.now(),
      );
    }

    test('returns prefer when prefer_db_streaming is true', () {
      final reason = policy.resolveAutoReason(
        featureFlags: featureFlags,
        queryRequest: queryRequest(),
        sql: 'SELECT * FROM users',
        negotiatedExtensions: const {'streamingResults': true},
        preferDbStreaming: true,
      );

      expect(reason, DbStreamingAutoReason.prefer);
    });

    test('returns allowlist when table matches env allowlist', () {
      policy = SqlDbStreamingAutoPolicy(
        envGetter: (_) => 'public.users',
        clock: () => now,
      );

      final reason = policy.resolveAutoReason(
        featureFlags: featureFlags,
        queryRequest: queryRequest(sql: 'SELECT * FROM public.users'),
        sql: 'SELECT * FROM public.users',
        negotiatedExtensions: const {'streamingResults': true},
        preferDbStreaming: false,
      );

      expect(reason, DbStreamingAutoReason.allowlist);
    });

    test('returns largeMaxRows when effective max rows meets streaming threshold', () {
      const limits = TransportLimits();
      final reason = policy.resolveAutoReason(
        featureFlags: featureFlags,
        queryRequest: queryRequest(),
        sql: 'SELECT * FROM users',
        negotiatedExtensions: const {'streamingResults': true},
        preferDbStreaming: false,
        effectiveMaxRows: limits.streamingRowThreshold,
      );

      expect(reason, DbStreamingAutoReason.largeMaxRows);
    });

    test('shouldMaterializeBoundedDbStreaming is false for large explicit TOP', () {
      const limits = TransportLimits();
      final normalized = policy.normalizeSqlForDbStreaming('SELECT TOP 1000 * FROM users');
      expect(
        policy.shouldMaterializeBoundedDbStreaming(
          normalized,
          effectiveMaxRows: 100,
          limits: limits,
        ),
        isFalse,
      );
    });

    test('returns sqlLength for long simple select', () {
      final longSql = 'SELECT ${'x' * 260} FROM users';

      final reason = policy.resolveAutoReason(
        featureFlags: featureFlags,
        queryRequest: queryRequest(sql: longSql),
        sql: longSql,
        negotiatedExtensions: const {'streamingResults': true},
        preferDbStreaming: false,
      );

      expect(reason, DbStreamingAutoReason.sqlLength);
    });

    test('returns sqlSignal when query contains join', () {
      final reason = policy.resolveAutoReason(
        featureFlags: featureFlags,
        queryRequest: queryRequest(sql: 'SELECT u.id FROM users u JOIN orders o ON u.id = o.user_id'),
        sql: 'SELECT u.id FROM users u JOIN orders o ON u.id = o.user_id',
        negotiatedExtensions: const {'streamingResults': true},
        preferDbStreaming: false,
      );

      expect(reason, DbStreamingAutoReason.none);
    });

    test('returns none when chunk streaming is enabled', () {
      when(() => featureFlags.enableSocketStreamingChunks).thenReturn(true);

      final reason = policy.resolveAutoReason(
        featureFlags: featureFlags,
        queryRequest: queryRequest(),
        sql: 'SELECT * FROM users',
        negotiatedExtensions: const {'streamingResults': true},
        preferDbStreaming: true,
      );

      expect(reason, DbStreamingAutoReason.none);
    });

    test('shouldMaterializeBoundedDbStreaming is true for explicit row limit', () {
      final normalized = policy.normalizeSqlForDbStreaming('SELECT TOP 10 * FROM users');
      expect(
        policy.shouldMaterializeBoundedDbStreaming(
          normalized,
          effectiveMaxRows: 10_000,
          limits: const TransportLimits(),
        ),
        isTrue,
      );
    });

    test('shouldMaterializeBoundedDbStreaming is false at streaming threshold boundary', () {
      const limits = TransportLimits();
      final normalized = policy.normalizeSqlForDbStreaming('SELECT * FROM users');
      expect(
        policy.shouldMaterializeBoundedDbStreaming(
          normalized,
          effectiveMaxRows: 500,
          limits: limits,
        ),
        isFalse,
      );
      expect(
        policy.shouldMaterializeBoundedDbStreaming(
          normalized,
          effectiveMaxRows: 499,
          limits: limits,
        ),
        isTrue,
      );
    });

    test('tableAllowlist caches parsed values until env or ttl changes', () {
      var envValue = 'orders';
      policy = SqlDbStreamingAutoPolicy(
        envGetter: (_) => envValue,
        clock: () => now,
      );

      expect(policy.tableAllowlist(), {'orders'});
      expect(policy.tableAllowlist(), {'orders'});

      envValue = 'invoices';
      expect(policy.tableAllowlist(), {'invoices'});

      now = now.add(const Duration(seconds: 11));
      expect(policy.tableAllowlist(), {'invoices'});
    });

    test('isDriverAllowed accepts SQL Server and rejects unknown', () {
      expect(policy.isDriverAllowed('SQL Server'), isTrue);
      expect(policy.isDriverAllowed('unknown-driver'), isFalse);
    });
  });
}
