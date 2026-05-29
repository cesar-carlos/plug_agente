import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/constants/rpc_error_data_constants.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

void main() {
  group('FailureToRpcErrorMapper', () {
    test('should map ValidationFailure to invalidParams', () {
      final failure = ValidationFailure('Invalid input');

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, equals(RpcErrorCode.invalidParams));
      expect(rpcError.message, equals('Invalid params'));
      expect(rpcError.data, isNotNull);
      expect(data['detail'], equals('Invalid input'));
      expect(data['reason'], equals('invalid_params'));
      expect(data['category'], equals('validation'));
      expect(data['recoverable'], isTrue);
      expect(data['retryable'], isFalse);
      expect(data['user_message'], isA<String>());
      expect(data['technical_message'], equals('Invalid input'));
      expect(data['correlation_id'], isA<String>());
      expect(data['timestamp'], isA<String>());
    });

    test(
      'should map ValidationFailure with SQL context to sqlValidationFailed',
      () {
        final failure = ValidationFailure.withContext(
          message: 'SQL syntax error',
          context: {'operation': 'sql_validation'},
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.sqlValidationFailed));
      },
    );

    test('should map QueryExecutionFailure to sqlExecutionFailed', () {
      final failure = QueryExecutionFailure('Query failed');

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.sqlExecutionFailed));
      expect(rpcError.message, equals('SQL execution failed'));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['recoverable'], isFalse);
    });

    test('should map QueryExecutionFailure with timeout to queryTimeout', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'Query timed out',
        context: {'timeout': true},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.queryTimeout));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['retryable'], isTrue);
    });

    test(
      'should map QueryExecutionFailure with connectionFailed to databaseConnectionFailed',
      () {
        final failure = QueryExecutionFailure.withContext(
          message: 'Communication link failure',
          context: {
            'connectionFailed': true,
            'reason': 'connection_lost_during_query',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.databaseConnectionFailed));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('database_connection_failed'));
        expect(data['odbc_reason'], equals('connection_lost_during_query'));
        expect(
          data['type'],
          equals('https://plugdb.dev/problems/database-error'),
        );
      },
    );

    test(
      'should map QueryExecutionFailure transaction context to transactionFailed',
      () {
        final failure = QueryExecutionFailure.withContext(
          message: 'Transaction aborted',
          context: {'reason': 'transaction_failed'},
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        check(rpcError.code).equals(RpcErrorCode.transactionFailed);
      },
    );

    test('should map NetworkFailure to networkError', () {
      final failure = NetworkFailure('Connection lost');

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.networkError));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['retryable'], isTrue);
      expect(data['reason'], equals('network_error'));
      expect(data['category'], equals('network'));
      expect(data['technical_message'], equals('Connection lost'));
    });

    test('should map CompressionFailure on decompress to decodingFailed', () {
      final failure = CompressionFailure.withContext(
        message: 'Failed to decompress',
        context: {'operation': 'decompress'},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.decodingFailed));
    });

    test('should map CompressionFailure on compress to compressionFailed', () {
      final failure = CompressionFailure.withContext(
        message: 'Failed to compress',
        context: {'operation': 'compress'},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.compressionFailed));
    });

    test('should include Problem Details data', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'Query failed',
        context: {'table': 'users', 'operation': 'select'},
      );

      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: 'trace-123',
      );

      final data = rpcError.data as Map<String, dynamic>;
      expect(data['type'], isNotNull);
      expect(data['title'], isNotNull);
      expect(data['status'], isNotNull);
      expect(data['detail'], equals('Query failed'));
      expect(data['instance'], equals('trace-123'));
      expect(data['retryable'], isNotNull);
      expect(data['table'], equals('users'));
    });

    test(
      'should map NetworkFailure with timeout_stage transport when flag on',
      () {
        final failure = NetworkFailure.withContext(
          message: 'Connection timeout',
          context: {'timeout': true, 'timeout_stage': 'transport'},
        );

        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          useTimeoutByStage: true,
        );

        expect(rpcError.code, equals(RpcErrorCode.timeout));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('transport_timeout'));
      },
    );

    test('should map NetworkFailure with timeout_stage ack when flag on', () {
      final failure = NetworkFailure.withContext(
        message: 'Ack timeout',
        context: {'timeout': true, 'timeout_stage': 'ack'},
      );

      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        useTimeoutByStage: true,
      );

      expect(rpcError.code, equals(RpcErrorCode.timeout));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['reason'], equals('ack_timeout'));
    });

    test(
      'should map QueryExecutionFailure with timeout_stage sql when flag on',
      () {
        final failure = QueryExecutionFailure.withContext(
          message: 'Query timed out',
          context: {'timeout_stage': 'sql'},
        );

        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          useTimeoutByStage: true,
        );

        expect(rpcError.code, equals(RpcErrorCode.queryTimeout));
      },
    );

    test('should not override reason when useTimeoutByStage is false', () {
      final failure = NetworkFailure.withContext(
        message: 'Connection timeout',
        context: {'timeout': true, 'timeout_stage': 'transport'},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.timeout));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['reason'], equals('timeout'));
    });

    test('should sanitize sensitive data from context', () {
      final failure = DatabaseFailure.withContext(
        message: 'Connection failed',
        context: {
          'host': 'localhost',
          'password': 'secret123',
          'connectionString': 'Server=localhost;Password=secret',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      final data = rpcError.data as Map<String, dynamic>;
      expect(data['host'], equals('localhost'));
      expect(data.containsKey('password'), isFalse);
      expect(data.containsKey('connectionString'), isFalse);
    });

    test(
      'should map ConnectionFailure with poolExhausted to connectionPoolExhausted',
      () {
        final failure = ConnectionFailure.withContext(
          message: 'Pool de conexoes ODBC esgotado',
          context: {
            'poolExhausted': true,
            'reason': OdbcContextConstants.poolExhaustedReason,
            'user_message': 'O agente esta sem conexoes livres no momento.',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.connectionPoolExhausted));
        expect(rpcError.message, equals('Connection pool exhausted'));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('connection_pool_exhausted'));
        expect(data['odbc_reason'], equals(OdbcContextConstants.poolExhaustedReason));
        expect(
          data['type'],
          equals('https://plugdb.dev/problems/database-error'),
        );
        expect(
          data['user_message'],
          equals(
            'O agente esta sem conexoes livres no momento.',
          ),
        );
      },
    );

    test('should map missing client token ConfigurationFailure to authenticationFailed', () {
      final failure = ConfigurationFailure.withContext(
        message: 'Client token is required for remote agent action RPC',
        context: {
          'authentication': true,
          'reason': RpcClientTokenConstants.missingClientTokenReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, equals(RpcErrorCode.authenticationFailed));
      expect(data['reason'], equals(RpcClientTokenConstants.missingClientTokenReason));
    });

    test('should map sql_queue_full to rateLimited with subreason', () {
      final failure = ConfigurationFailure.withContext(
        message: 'SQL execution queue is full; system is under heavy load',
        context: {
          'rpc_error_code': RpcErrorCode.rateLimited,
          'reason': SqlPipelineContextConstants.sqlQueueFullReason,
          'retryable': true,
          'user_message': 'O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, equals(RpcErrorCode.rateLimited));
      expect(data['reason'], equals('rate_limited'));
      expect(data['subreason'], equals(SqlPipelineContextConstants.sqlQueueFullReason));
      expect(data.containsKey('odbc_reason'), isFalse);
      expect(
        data['user_message'],
        equals('O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.'),
      );
    });

    test('should map queue_wait_timeout to rateLimited with subreason', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'SQL request timed out waiting in queue',
        context: {
          'rpc_error_code': RpcErrorCode.rateLimited,
          'reason': SqlPipelineContextConstants.queueWaitTimeoutReason,
          'timeout': true,
          'timeout_stage': 'queue',
          'retryable': true,
          'user_message': 'O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, equals(RpcErrorCode.rateLimited));
      expect(data['reason'], equals('rate_limited'));
      expect(data['subreason'], equals(SqlPipelineContextConstants.queueWaitTimeoutReason));
      expect(data.containsKey('odbc_reason'), isFalse);
      expect(data['timeout_stage'], equals('queue'));
      expect(
        data['user_message'],
        equals('O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.'),
      );
    });

    test(
      'should map ConnectionFailure ODBC to databaseConnectionFailed with odbc_reason',
      () {
        final failure = ConnectionFailure.withContext(
          message: 'Nao foi possivel alcancar o servidor de banco de dados',
          context: {
            'connectionFailed': true,
            'reason': 'server_unreachable',
            'user_message': 'Nao foi possivel conectar ao servidor do banco. Verifique host, porta, VPN.',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.databaseConnectionFailed));
        expect(rpcError.message, equals('Database connection failed'));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('database_connection_failed'));
        expect(data['odbc_reason'], equals('server_unreachable'));
        expect(
          data['type'],
          equals('https://plugdb.dev/problems/database-error'),
        );
        expect(
          data['user_message'],
          equals(
            'Nao foi possivel conectar ao servidor do banco. Verifique host, porta, VPN.',
          ),
        );
      },
    );

    test(
      'should map bare ConnectionFailure to databaseConnectionFailed',
      () {
        final failure = ConnectionFailure('Falha desconhecida ao inicializar ODBC');

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.databaseConnectionFailed));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('database_connection_failed'));
        expect(data.containsKey('odbc_reason'), isFalse);
      },
    );

    test('should stringify non-string context reason as odbc_reason', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'ODBC error',
        context: {
          'reason': 42,
          'connectionFailed': true,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(data['odbc_reason'], equals('42'));
      expect(data['reason'], equals('database_connection_failed'));
    });

    test(
      'should omit odbc_reason when domain reason matches canonical reason',
      () {
        final failure = ConnectionFailure.withContext(
          message: 'Falha ao conectar',
          context: const {
            'connectionFailed': true,
            'reason': 'database_connection_failed',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);
        final data = rpcError.data as Map<String, dynamic>;

        expect(data['reason'], equals('database_connection_failed'));
        expect(data.containsKey('odbc_reason'), isFalse);
      },
    );

    test(
      'NotFoundFailure maps to internalError with reason resource_not_found',
      () {
        // JSON-RPC reserves -32601 for "method does not exist". A missing
        // resource (HTTP 404, missing config row) must NOT be confused with
        // a typo in `request.method` — use internalError + resource_not_found.
        final failure = NotFoundFailure('Configuração não encontrada');

        final rpcError = FailureToRpcErrorMapper.map(failure);
        final data = rpcError.data as Map<String, dynamic>;

        expect(rpcError.code, equals(RpcErrorCode.internalError));
        expect(data['reason'], equals(RpcErrorDataConstants.resourceNotFoundReason));
      },
    );

    test(
      'should pass denied_resources list through for ConfigurationFailure authorization',
      () {
        final failure = ConfigurationFailure.withContext(
          message: 'Authorization denied for read on a, b',
          context: {
            'authorization': true,
            'reason': 'missing_permission',
            'operation': 'read',
            'resource': 'a',
            'denied_resources': <String>['a', 'b'],
            'user_message': 'Acesso negado nos recursos: a, b',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);
        final data = rpcError.data as Map<String, dynamic>;

        expect(rpcError.code, equals(RpcErrorCode.unauthorized));
        final denied = data['denied_resources'];
        expect(denied, isA<List<dynamic>>());
        expect(
          (denied as List<dynamic>).map((e) => e as String).toList(),
          equals(<String>['a', 'b']),
        );
        expect(data['user_message'], equals('Acesso negado nos recursos: a, b'));
      },
    );

    test(
      'should map sql_permission_denied query failure to unauthorized preserving denied resources',
      () {
        final failure = QueryExecutionFailure.withContext(
          message: "The SELECT permission was denied on the object 'Orders'.",
          context: {
            'reason': 'sql_permission_denied',
            'odbc_sql_state': '42501',
            'resource': 'dbo.Orders',
            'denied_resources': <String>['dbo.Orders'],
            'user_message': 'Acesso negado para os recursos: dbo.Orders.',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);
        final data = rpcError.data as Map<String, dynamic>;

        expect(rpcError.code, equals(RpcErrorCode.unauthorized));
        expect(data['reason'], equals(AuthorizationContextConstants.unauthorizedReason));
        expect(data['odbc_reason'], equals('sql_permission_denied'));
        expect(data['resource'], equals('dbo.Orders'));
        expect(data['denied_resources'], equals(<String>['dbo.Orders']));
        expect(data['user_message'], equals('Acesso negado para os recursos: dbo.Orders.'));
      },
    );

    test('should not forward the verbatim ODBC driver message across the RPC boundary', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'The database returned an error when executing the query.',
        context: {
          'reason': OdbcContextConstants.sqlExecutionFailedReason,
          'odbc_message': "[Microsoft][ODBC Driver 17][SQL Server]Login failed for user 'sa' on SRV01.",
          'odbc_sql_state': '42000',
          'user_message': 'The database returned an error when executing the query.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(data.containsKey('odbc_message'), isFalse);
      // The local Failure still keeps the diagnostic detail for in-app display.
      expect(failure.context['odbc_message'], isNotNull);
      // Safe, structured fields remain available to the hub.
      expect(data['odbc_sql_state'], equals('42000'));
      expect(data['user_message'], isA<String>());
    });

    test('should redact credential tokens from detail and technical_message', () {
      final failure = ConnectionFailure.withContext(
        message: 'connect failed using DRIVER={x};UID=app;PWD=topsecret;Server=h',
        context: {
          'reason': OdbcContextConstants.databaseConnectionFailedReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(data['detail'], contains('PWD=***'));
      expect(data['detail'], isNot(contains('topsecret')));
      expect(data['technical_message'], contains('PWD=***'));
      expect(data['technical_message'], isNot(contains('topsecret')));
    });

    test('should map ActionValidationFailure to invalidParams with action category', () {
      final failure = ActionValidationFailure.withContext(
        message: 'Remote idempotency key is required',
        code: AgentActionFailureCode.remoteIdempotencyRequired,
        context: {'field': 'idempotencyKey'},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, equals(RpcErrorCode.invalidParams));
      expect(data['category'], equals(RpcErrorCode.categoryAction));
      expect(data['failure_code'], equals(AgentActionFailureCode.remoteIdempotencyRequired));
    });

    test(
      'should map ActionValidationFailure remote context to invalidParams with remote_context_not_supported reason',
      () {
        final failure = ActionValidationFailure.withContext(
          message: 'Remote agent action RPC does not accept inline context in MVP.',
          code: AgentActionFailureCode.remoteContextNotSupported,
          context: {
            'field': 'context_json',
            'reason': AgentActionRpcConstants.remoteContextNotSupportedRpcReason,
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);
        final data = rpcError.data as Map<String, dynamic>;

        expect(rpcError.code, equals(RpcErrorCode.invalidParams));
        expect(data['category'], equals(RpcErrorCode.categoryAction));
        expect(data['reason'], equals(AgentActionRpcConstants.remoteContextNotSupportedRpcReason));
      },
    );

    test('should map ActionAuthorizationFailure remote disabled to unauthorized with action category', () {
      final failure = ActionAuthorizationFailure.withContext(
        message: 'Remote agent actions are disabled',
        code: AgentActionFailureCode.remoteFeatureDisabled,
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, equals(RpcErrorCode.unauthorized));
      expect(data['category'], equals(RpcErrorCode.categoryAction));
      expect(data['reason'], equals('agent_actions_remote_disabled'));
    });
  });
}
