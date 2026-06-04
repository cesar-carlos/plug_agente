import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  late _MockFeatureFlags featureFlags;
  late List<({String direction, String event, dynamic data})> logs;
  late int refreshCalls;
  late AuthorizationDecisionLogger logger;

  setUp(() {
    featureFlags = _MockFeatureFlags();
    when(() => featureFlags.enableClientTokenAuthorization).thenReturn(true);
    when(() => featureFlags.enableClientTokenPolicyIntrospection).thenReturn(true);
    logs = [];
    refreshCalls = 0;
    logger = AuthorizationDecisionLogger(
      featureFlags: featureFlags,
      logMessage: (direction, event, data) {
        logs.add((direction: direction, event: event, data: data));
      },
      agentIdProvider: () => 'agent-1',
      onTokenRefreshRequested: () => refreshCalls++,
    );
  });

  RpcRequest sqlRequest({String id = 'req-1'}) => RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.execute',
    id: id,
  );

  group('log - happy paths', () {
    test('logs authorization.allowed for successful sql.* response', () {
      logger.log(
        request: sqlRequest(),
        response: RpcResponse.success(id: 'req-1', result: <String, dynamic>{}),
        clientToken: 'tok',
      );

      expect(logs, hasLength(1));
      expect(logs.single.event, 'authorization.allowed');
    });
  });

  group('log - skip conditions', () {
    test('skips logging when feature flag is off', () {
      when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
      logger.log(
        request: sqlRequest(),
        response: RpcResponse.success(id: 'req-1', result: <String, dynamic>{}),
        clientToken: 'tok',
      );
      expect(logs, isEmpty);
    });

    test('skips when client token is null/empty', () {
      logger.log(
        request: sqlRequest(),
        response: RpcResponse.success(id: 'req-1', result: <String, dynamic>{}),
        clientToken: null,
      );
      logger.log(
        request: sqlRequest(),
        response: RpcResponse.success(id: 'req-1', result: <String, dynamic>{}),
        clientToken: '',
      );
      expect(logs, isEmpty);
    });

    test('skips for methods that are not sql.* or client_token.getPolicy', () {
      logger.log(
        request: const RpcRequest(jsonrpc: '2.0', method: 'agent.getProfile', id: 1),
        response: RpcResponse.success(id: 1, result: <String, dynamic>{}),
        clientToken: 'tok',
      );
      expect(logs, isEmpty);
    });
  });

  group('log - client_token authentication failure', () {
    test('logs authentication_failed without triggering hub JWT refresh', () {
      final errorResponse = RpcResponse.error(
        id: 'req-1',
        error: const RpcError(
          code: RpcErrorCode.authenticationFailed,
          message: 'Authentication failed',
          data: {'reason': 'token_invalid'},
        ),
      );

      logger.log(
        request: sqlRequest(),
        response: errorResponse,
        clientToken: 'tok',
      );
      logger.log(
        request: sqlRequest(id: 'req-2'),
        response: errorResponse,
        clientToken: 'tok',
      );

      expect(refreshCalls, 0);
      final authFailed = logs.where((l) => l.event == 'authorization.authentication_failed');
      expect(authFailed, hasLength(2));
      expect(
        logs.where((l) => l.event == 'authorization.token_refresh_requested'),
        isEmpty,
      );
    });
  });

  group('log - token revocation triggers refresh', () {
    test('logs unauthorized and triggers refresh on token_revoked reason', () {
      final response = RpcResponse.error(
        id: 'req-1',
        error: const RpcError(
          code: RpcErrorCode.unauthorized,
          message: 'Unauthorized',
          data: {'reason': AuthorizationContextConstants.tokenRevokedReason, 'client_id': 'c1'},
        ),
      );

      logger.log(request: sqlRequest(), response: response, clientToken: 'tok');

      expect(refreshCalls, 1);
      final denied = logs.singleWhere((l) => l.event == 'authorization.denied');
      final data = denied.data as Map<String, dynamic>;
      expect(data['reason'], AuthorizationContextConstants.tokenRevokedReason);
      expect(data['client_id'], 'c1');
    });

    test('does not trigger refresh on generic unauthorized', () {
      final response = RpcResponse.error(
        id: 'req-1',
        error: const RpcError(
          code: RpcErrorCode.unauthorized,
          message: 'Unauthorized',
          data: {'reason': 'permission_denied'},
        ),
      );

      logger.log(request: sqlRequest(), response: response, clientToken: 'tok');

      expect(refreshCalls, 0);
    });

    test('includes denied_resources in authorization.denied payload when present', () {
      final response = RpcResponse.error(
        id: 'req-1',
        error: const RpcError(
          code: RpcErrorCode.unauthorized,
          message: 'Unauthorized',
          data: {
            'reason': AuthorizationContextConstants.unauthorizedReason,
            'resource': 'dbo.t1',
            'denied_resources': <String>['dbo.t1', 'dbo.t2'],
          },
        ),
      );

      logger.log(request: sqlRequest(), response: response, clientToken: 'tok');

      final denied = logs.singleWhere((l) => l.event == 'authorization.denied');
      final data = denied.data as Map<String, dynamic>;
      expect(
        (data['denied_resources'] as List<dynamic>).map((e) => e as String).toList(),
        equals(<String>['dbo.t1', 'dbo.t2']),
      );
      expect(data['resource'], equals('dbo.t1'));
    });
  });
}
