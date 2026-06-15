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
