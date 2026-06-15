import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/sql_cancel_handler.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockStreamingGateway extends Mock implements IStreamingDatabaseGateway {}

class _MockAbortPort extends Mock implements ISqlInFlightExecutionAbortPort {}

SqlRpcMethodHandlerSupport _support() {
  return SqlRpcMethodHandlerSupport(
    invalidParams: (request, detail, {rpcReason, extraFields = const {}}) => RpcResponse.error(
      id: request.id,
      error: RpcError(code: -32602, message: detail),
    ),
    methodNotFound: (request) => RpcResponse.error(
      id: request.id,
      error: const RpcError(code: -32601, message: 'not found'),
    ),
    executionNotFound: (request) => RpcResponse.error(
      id: request.id,
      error: const RpcError(code: -32001, message: 'execution not found'),
    ),
    consumeIdempotentCacheIfAny: (_, key, fingerprint) async => null,
    storeIdempotentSuccessIfApplicable:
        ({
          required request,
          required idempotencyKey,
          required idempotencyFingerprint,
          required response,
        }) async {},
    runIdempotentExecution:
        ({
          required request,
          required idempotencyKey,
          required idempotencyFingerprint,
          required execute,
          idempotentCachePrefetched = false,
        }) => execute(),
    buildMissingClientTokenFailure: () => domain.ConfigurationFailure('missing token'),
    authorizeWithBudget:
        ({
          required token,
          required sql,
          required requestDatabase,
          required requestId,
          required method,
          required deadline,
        }) async => const Success(unit),
    effectiveStageTimeout: ({required deadline, required stageBudget}) => stageBudget,
  );
}

void main() {
  late _MockFeatureFlags featureFlags;
  late _MockAbortPort abortPort;

  setUp(() {
    featureFlags = _MockFeatureFlags();
    abortPort = _MockAbortPort();
    when(() => featureFlags.enableSocketCancelMethod).thenReturn(true);
    when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
    when(() => abortPort.abortInFlightExecution(any())).thenAnswer((_) async => const Success(unit));
  });

  test('cancels materialized execution via in-flight abort port', () async {
    final handler = SqlCancelHandler(
      featureFlags: featureFlags,
      support: _support(),
      sqlStreamingCoordinator: SqlStreamingCoordinator(gateway: _MockStreamingGateway()),
      streamingGateway: _MockStreamingGateway(),
      inFlightAbortPort: abortPort,
    );

    final response = await handler.handleSqlCancel(
      const RpcRequest(jsonrpc: '2.0', id: 1, method: 'sql.cancel', params: {'request_id': 'req-materialized'}),
    );

    expect(response.error, isNull);
    final result = response.result as Map<String, dynamic>?;
    expect(result?['cancelled'], isTrue);
    expect(result?['via_in_flight_abort'], isTrue);
    verify(() => abortPort.abortInFlightExecution('req-materialized')).called(1);
  });
}
