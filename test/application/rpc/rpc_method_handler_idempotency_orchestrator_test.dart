import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler_idempotency_orchestrator.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';

class _MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockIdempotencyStore extends Mock implements IIdempotencyStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  group('RpcMethodHandlerIdempotencyOrchestrator', () {
    late _MockAuthorizeSqlOperation authorizeSqlOperation;
    late _MockFeatureFlags featureFlags;
    late _MockIdempotencyStore idempotencyStore;
    late RpcMethodHandlerIdempotencyOrchestrator orchestrator;

    setUp(() {
      authorizeSqlOperation = _MockAuthorizeSqlOperation();
      featureFlags = _MockFeatureFlags();
      idempotencyStore = _MockIdempotencyStore();
      when(() => featureFlags.enableSocketIdempotency).thenReturn(true);
      registerFallbackValue(
        RpcResponse.success(id: 'fallback', result: const <String, dynamic>{}),
      );
      orchestrator = RpcMethodHandlerIdempotencyOrchestrator(
        authorizeSqlOperation: authorizeSqlOperation,
        featureFlags: featureFlags,
        idempotencyStore: idempotencyStore,
      );
    });

    test('should not persist error responses in idempotency cache', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: <String, dynamic>{
          'sql': 'SELECT 1',
          'idempotency_key': 'key-1',
        },
      );

      when(() => idempotencyStore.getRecord(any())).thenAnswer((_) async => null);
      when(() => idempotencyStore.set(any(), any(), any(), requestFingerprint: any(named: 'requestFingerprint')))
          .thenAnswer((_) async {});

      await orchestrator.runIdempotentExecution(
        request: request,
        idempotencyKey: 'key-1',
        idempotencyFingerprint: 'fp-1',
        execute: () async => RpcResponse.error(
          id: 'req-1',
          error: const RpcError(code: -32000, message: 'transient'),
        ),
      );

      verifyNever(
        () => idempotencyStore.set(any(), any(), any(), requestFingerprint: any(named: 'requestFingerprint')),
      );
    });

    test('should persist successful responses in idempotency cache', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-2',
        params: <String, dynamic>{
          'sql': 'SELECT 1',
          'idempotency_key': 'key-2',
        },
      );

      when(() => idempotencyStore.getRecord(any())).thenAnswer((_) async => null);
      when(() => idempotencyStore.set(any(), any(), any(), requestFingerprint: any(named: 'requestFingerprint')))
          .thenAnswer((_) async {});

      await orchestrator.runIdempotentExecution(
        request: request,
        idempotencyKey: 'key-2',
        idempotencyFingerprint: 'fp-2',
        execute: () async => RpcResponse.success(id: 'req-2', result: const {'ok': true}),
      );

      verify(
        () => idempotencyStore.set(
          'sql.execute:key-2',
          any(that: predicate<RpcResponse>((response) => response.isSuccess)),
          any(),
          requestFingerprint: 'fp-2',
        ),
      ).called(1);
    });
  });
}
