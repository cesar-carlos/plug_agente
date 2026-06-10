import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/sql_rpc_client_token_gate.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:result_dart/result_dart.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

SqlRpcMethodHandlerSupport _support({
  required SqlRpcAuthorizeWithBudget authorizeWithBudget,
}) {
  return SqlRpcMethodHandlerSupport(
    invalidParams: (_, detail, {rpcReason, extraFields = const {}}) => throw UnimplementedError(),
    methodNotFound: (_) => throw UnimplementedError(),
    executionNotFound: (_) => throw UnimplementedError(),
    consumeIdempotentCacheIfAny: (_, key, fingerprint) async => null,
    storeIdempotentSuccessIfApplicable: ({
      required request,
      required idempotencyKey,
      required idempotencyFingerprint,
      required response,
    }) async {},
    runIdempotentExecution: ({
      required request,
      required idempotencyKey,
      required idempotencyFingerprint,
      required execute,
    }) => execute(),
    buildMissingClientTokenFailure: () => domain.ConfigurationFailure.withContext(
      message: 'Client token is required for authorized SQL operations',
      context: {
        'authentication': true,
        'reason': RpcClientTokenConstants.missingClientTokenReason,
      },
    ),
    authorizeWithBudget: authorizeWithBudget,
    effectiveStageTimeout: ({required deadline, required stageBudget}) => stageBudget,
  );
}

void main() {
  group('SqlRpcClientTokenGate', () {
    late MockFeatureFlags mockFeatureFlags;

    setUp(() {
      mockFeatureFlags = MockFeatureFlags();
      when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => mockFeatureFlags.enableDashboardSqlInvestigationFeed).thenReturn(false);
    });

    const request = RpcRequest(
      jsonrpc: '2.0',
      method: 'sql.executeBatch',
      id: 'req-auth',
      params: <String, dynamic>{'commands': <dynamic>[]},
    );

    test('returns null when client token authorization is disabled', () async {
      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(false);

      final gate = SqlRpcClientTokenGate(
        featureFlags: mockFeatureFlags,
        support: _support(
          authorizeWithBudget: ({required token, required sql, required requestDatabase, required requestId, required method, required deadline}) async => const Success(unit),
        ),
      );

      final response = await gate.enforce(
        request: request,
        clientToken: null,
        sqlStatements: const ['SELECT 1'],
        investigationSqlOnDeny: 'SELECT 1',
        requestDatabase: null,
        deadline: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(response, isNull);
    });

    test('returns authenticationFailed when client token is missing', () async {
      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);

      final gate = SqlRpcClientTokenGate(
        featureFlags: mockFeatureFlags,
        support: _support(
          authorizeWithBudget: ({required token, required sql, required requestDatabase, required requestId, required method, required deadline}) async => const Success(unit),
        ),
      );

      final response = await gate.enforce(
        request: request,
        clientToken: null,
        sqlStatements: const ['SELECT 1'],
        investigationSqlOnDeny: 'SELECT 1',
        requestDatabase: null,
        deadline: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(response, isNotNull);
      expect(response!.isError, isTrue);
      expect(response.error!.code, RpcErrorCode.authenticationFailed);
    });

    test('deduplicates equivalent SQL before authorizeWithBudget', () async {
      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);

      var authorizeCalls = 0;
      final gate = SqlRpcClientTokenGate(
        featureFlags: mockFeatureFlags,
        support: _support(
          authorizeWithBudget: ({required token, required sql, required requestDatabase, required requestId, required method, required deadline}) async {
            authorizeCalls++;
            return const Success(unit);
          },
        ),
      );

      final response = await gate.enforce(
        request: request,
        clientToken: 'token',
        sqlStatements: const [
          'SELECT * FROM users WHERE id = 1',
          ' SELECT  *  FROM users WHERE id = 1 ',
        ],
        investigationSqlOnDeny: 'batch preview',
        requestDatabase: null,
        deadline: DateTime.now().add(const Duration(seconds: 30)),
        deduplicateEquivalentSql: true,
      );

      expect(response, isNull);
      expect(authorizeCalls, 1);
    });

    test('returns unauthorized when authorizeWithBudget denies', () async {
      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);

      final gate = SqlRpcClientTokenGate(
        featureFlags: mockFeatureFlags,
        support: _support(
          authorizeWithBudget: ({required token, required sql, required requestDatabase, required requestId, required method, required deadline}) async {
            return Failure(
              domain.ConfigurationFailure.withContext(
                message: 'denied',
                context: {
                  'authorization': true,
                  'reason': 'missing_permission',
                },
              ),
            );
          },
        ),
      );

      final response = await gate.enforce(
        request: const RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-deny',
          params: {'sql': 'DELETE FROM dbo.users'},
        ),
        clientToken: 'token',
        sqlStatements: const ['DELETE FROM dbo.users'],
        investigationSqlOnDeny: 'DELETE FROM dbo.users',
        requestDatabase: null,
        deadline: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(response, isNotNull);
      expect(response!.isError, isTrue);
      expect(response.error!.code, RpcErrorCode.unauthorized);
    });
  });
}
