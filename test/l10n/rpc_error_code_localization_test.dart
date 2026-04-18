import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/domain/protocol/rpc_error_user_message_localizer.dart';

class _StubLocalizer implements RpcErrorUserMessageLocalizer {
  @override
  String invalidRequest() => 'STUB_invalid_request';
  @override
  String methodNotFound() => 'STUB_method_not_found';
  @override
  String authenticationFailed() => 'STUB_auth_failed';
  @override
  String unauthorized() => 'STUB_unauthorized';
  @override
  String timeout() => 'STUB_timeout';
  @override
  String invalidPayload() => 'STUB_invalid_payload';
  @override
  String networkError() => 'STUB_network_error';
  @override
  String rateLimited() => 'STUB_rate_limited';
  @override
  String replayDetected() => 'STUB_replay_detected';
  @override
  String sqlValidationFailed() => 'STUB_sql_validation_failed';
  @override
  String sqlExecutionFailed() => 'STUB_sql_execution_failed';
  @override
  String connectionPoolExhausted() => 'STUB_pool_exhausted';
  @override
  String resultTooLarge() => 'STUB_result_too_large';
  @override
  String databaseConnectionFailed() => 'STUB_db_connection_failed';
  @override
  String invalidDatabaseConfig() => 'STUB_invalid_db_config';
  @override
  String executionNotFound() => 'STUB_execution_not_found';
  @override
  String executionCancelled() => 'STUB_execution_cancelled';
  @override
  String internalError() => 'STUB_internal_error';
}

void main() {
  group('RpcErrorCode user message localizer', () {
    late RpcErrorUserMessageLocalizer original;

    setUp(() {
      original = RpcErrorCode.userMessageLocalizer;
    });

    tearDown(() {
      RpcErrorCode.userMessageLocalizer = original;
    });

    test('default localizer returns PT-BR strings', () {
      RpcErrorCode.userMessageLocalizer = const DefaultPtRpcErrorUserMessageLocalizer();
      expect(
        RpcErrorCode.getUserMessage(RpcErrorCode.invalidRequest),
        contains('Requisi'),
      );
      expect(
        RpcErrorCode.getUserMessage(RpcErrorCode.executionCancelled),
        contains('cancelada'),
      );
    });

    test('installed localizer routes every code through it', () {
      RpcErrorCode.userMessageLocalizer = _StubLocalizer();

      expect(RpcErrorCode.getUserMessage(RpcErrorCode.invalidRequest), 'STUB_invalid_request');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.parseError), 'STUB_invalid_request');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.invalidParams), 'STUB_invalid_request');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.methodNotFound), 'STUB_method_not_found');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.authenticationFailed), 'STUB_auth_failed');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.unauthorized), 'STUB_unauthorized');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.timeout), 'STUB_timeout');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.queryTimeout), 'STUB_timeout');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.invalidPayload), 'STUB_invalid_payload');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.decodingFailed), 'STUB_invalid_payload');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.networkError), 'STUB_network_error');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.rateLimited), 'STUB_rate_limited');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.replayDetected), 'STUB_replay_detected');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.sqlValidationFailed), 'STUB_sql_validation_failed');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.sqlExecutionFailed), 'STUB_sql_execution_failed');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.transactionFailed), 'STUB_sql_execution_failed');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.connectionPoolExhausted), 'STUB_pool_exhausted');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.resultTooLarge), 'STUB_result_too_large');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.databaseConnectionFailed), 'STUB_db_connection_failed');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.invalidDatabaseConfig), 'STUB_invalid_db_config');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.executionNotFound), 'STUB_execution_not_found');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.executionCancelled), 'STUB_execution_cancelled');
      expect(RpcErrorCode.getUserMessage(RpcErrorCode.internalError), 'STUB_internal_error');
      expect(RpcErrorCode.getUserMessage(99999), 'STUB_internal_error');
    });
  });
}
