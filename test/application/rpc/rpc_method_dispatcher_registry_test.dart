import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_concurrency_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/rpc_method_dispatcher_test_support.dart';

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockHealthService extends Mock implements HealthService {}

class _MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class _MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class _MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

class _MockClientTokenGetPolicyRateLimiter extends Mock implements ClientTokenGetPolicyRateLimiter {}

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _StubRpcMethodHandler implements RpcMethodHandler {
  const _StubRpcMethodHandler(this.method);

  @override
  final String method;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    return RpcResponse.success(
      id: request.id,
      result: <String, dynamic>{
        'method': method,
        'agent_id': context.agentId,
        'client_token': context.clientToken,
      },
    );
  }
}

class _BlockingRpcMethodHandler implements RpcMethodHandler {
  _BlockingRpcMethodHandler({
    required this.method,
    required this.release,
  });

  @override
  final String method;
  final Future<void> release;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    await release;
    return RpcResponse.success(id: request.id, result: const <String, dynamic>{'ok': true});
  }
}

RpcMethodDispatcher _buildDispatcher({
  Iterable<RpcMethodHandler>? handlers,
  RpcMethodConcurrencyLimiter? methodConcurrencyLimiter,
}) {
  return RpcMethodDispatcher(
    streamingConnectionStringCache: rpcTestStreamingConnectionStringCache(),
    databaseGateway: _MockDatabaseGateway(),
    healthService: _MockHealthService(),
    normalizerService: _MockQueryNormalizerService(),
    uuid: const Uuid(),
    authorizeSqlOperation: _MockAuthorizeSqlOperation(),
    getClientTokenPolicy: _MockGetClientTokenPolicy(),
    getPolicyRateLimiter: _MockClientTokenGetPolicyRateLimiter(),
    featureFlags: _MockFeatureFlags(),
    handlers: handlers,
    methodConcurrencyLimiter: methodConcurrencyLimiter,
  );
}

void main() {
  group('RpcMethodDispatcher handler registry', () {
    test('dispatches through a registered method handler', () async {
      final dispatcher = _buildDispatcher(
        handlers: const <RpcMethodHandler>[
          _StubRpcMethodHandler('custom.echo'),
        ],
      );

      final response = await dispatcher.dispatch(
        const RpcRequest(jsonrpc: '2.0', method: 'custom.echo', id: 'req-1'),
        'agent-1',
        clientToken: 'token-1',
      );

      expect(response.isSuccess, isTrue);
      expect(response.result, {
        'method': 'custom.echo',
        'agent_id': 'agent-1',
        'client_token': 'token-1',
      });
    });

    test('rejects duplicate method handlers during construction', () {
      expect(
        () => _buildDispatcher(
          handlers: const <RpcMethodHandler>[
            _StubRpcMethodHandler('custom.echo'),
            _StubRpcMethodHandler('custom.echo'),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('returns methodNotFound for unregistered methods', () async {
      final dispatcher = _buildDispatcher(handlers: const <RpcMethodHandler>[]);

      final response = await dispatcher.dispatch(
        const RpcRequest(jsonrpc: '2.0', method: 'unknown.method', id: 'req-2'),
        'agent-1',
      );

      expect(response.error?.code, RpcErrorCode.methodNotFound);
    });

    test('applies method concurrency limit per client without leaking token', () async {
      final releaseFirst = Completer<void>();
      final dispatcher = _buildDispatcher(
        handlers: <RpcMethodHandler>[
          _BlockingRpcMethodHandler(
            method: 'custom.slow',
            release: releaseFirst.future,
          ),
        ],
        methodConcurrencyLimiter: RpcMethodConcurrencyLimiter(
          methodLimits: const <String, int>{'custom.slow': 1},
        ),
      );

      final first = dispatcher.dispatch(
        const RpcRequest(jsonrpc: '2.0', method: 'custom.slow', id: 'req-1'),
        'agent-1',
        clientToken: 'secret-token',
      );
      final second = await dispatcher.dispatch(
        const RpcRequest(jsonrpc: '2.0', method: 'custom.slow', id: 'req-2'),
        'agent-1',
        clientToken: 'secret-token',
      );

      expect(second.error?.code, RpcErrorCode.rateLimited);
      expect(second.error?.data, containsPair('reason', 'method_concurrency_limit'));
      expect(second.error?.data.toString(), isNot(contains('secret-token')));

      releaseFirst.complete();
      expect((await first).isSuccess, isTrue);
    });
  });
}
