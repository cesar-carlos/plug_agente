import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';

void main() {
  group('OdbcInFlightExecutionRegistry', () {
    test('bindStatement and bindAsyncRequest update registered handle', () {
      final registry = OdbcInFlightExecutionRegistry();
      registry.register(
        'req-1',
        const OdbcInFlightExecutionHandle(connectionId: 'conn-1'),
      );

      registry.bindStatement('req-1', 42);
      registry.bindAsyncRequest('req-1', 99);

      final handle = registry.peek('req-1');
      expect(handle, isNotNull);
      expect(handle!.connectionId, 'conn-1');
      expect(handle.statementId, 42);
      expect(handle.asyncRequestId, 99);
      expect(handle.hasNativeCancelTarget, isTrue);
    });

    test('unregister removes handle', () {
      final registry = OdbcInFlightExecutionRegistry();
      registry.register(
        'req-1',
        const OdbcInFlightExecutionHandle(connectionId: 'conn-1', statementId: 1),
      );

      registry.unregister('req-1');

      expect(registry.peek('req-1'), isNull);
    });

    test('pending abort is notified on register and cleared on unregister', () async {
      final registry = OdbcInFlightExecutionRegistry();
      final notified = <String>[];
      registry.setPendingAbortListener(notified.add);

      registry.markPendingAbort('req-pending');
      expect(registry.hasPendingAbort('req-pending'), isTrue);

      registry.register(
        'req-pending',
        const OdbcInFlightExecutionHandle(connectionId: 'conn-1'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(notified, contains('req-pending'));
      expect(registry.hasPendingAbort('req-pending'), isTrue);

      registry.unregister('req-pending');
      expect(registry.hasPendingAbort('req-pending'), isFalse);
    });

    test('pending abort is re-notified when native cancel target is bound', () async {
      final registry = OdbcInFlightExecutionRegistry();
      final notified = <String>[];
      registry.setPendingAbortListener(notified.add);
      registry.markPendingAbort('req-1');
      registry.register(
        'req-1',
        const OdbcInFlightExecutionHandle(connectionId: 'conn-1'),
      );
      await Future<void>.delayed(Duration.zero);
      notified.clear();

      registry.bindStatement('req-1', 7);
      await Future<void>.delayed(Duration.zero);

      expect(notified, contains('req-1'));
    });

    test('expires orphan pending aborts after TTL', () async {
      final registry = OdbcInFlightExecutionRegistry(
        pendingAbortTtl: const Duration(milliseconds: 30),
      );
      registry.markPendingAbort('req-orphan');
      expect(registry.hasPendingAbort('req-orphan'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(registry.hasPendingAbort('req-orphan'), isFalse);
    });
  });

  group('odbcInFlightRegistryKey', () {
    test('prefers sourceRpcRequestId when present', () {
      expect(
        odbcInFlightRegistryKey(requestId: 'local-id', sourceRpcRequestId: 'rpc-9'),
        'rpc-9',
      );
    });

    test('falls back to requestId', () {
      expect(
        odbcInFlightRegistryKey(requestId: 'local-id'),
        'local-id',
      );
    });
  });
}
