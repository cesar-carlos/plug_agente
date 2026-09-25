import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_rpc_failure_reporter.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/domain/logging/structured_log_sink_registry.dart';
import 'package:plug_agente/domain/protocol/rpc_error.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

class _RecordingSink implements IStructuredLogSink {
  String? level;
  String? message;
  Map<String, dynamic>? context;

  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    this.level = level;
    this.message = message;
    this.context = context;
  }
}

void main() {
  late _RecordingSink sink;

  setUp(() {
    sink = _RecordingSink();
    AppLogger.attachStructuredSink(sink);
    StructuredLogSinkRegistry.register(sink);
  });

  tearDown(() {
    AppLogger.detachStructuredSink();
    StructuredLogSinkRegistry.reset();
  });

  test('validation failures are warnings and omit sql text', () {
    const sql = 'SELECT secret_column FROM customers WHERE name = :name';
    SqlRpcFailureReporter.report(
      failure: ValidationFailure.withContext(
        message: 'bad sql',
        context: const {'user_message': 'fix the query', 'reason': 'sql_validation_failed'},
      ),
      rpcError: const RpcError(code: RpcErrorCode.sqlValidationFailed, message: 'invalid'),
      rpcMethod: 'sql.execute',
      sql: sql,
    );
    expect(sink.level, 'WARNING');
    expect(sink.message, contains('bad sql'));
    expect(sink.context?['sql_verb'], 'SELECT');
    expect(sink.context.toString().contains('secret_column'), isFalse);
    expect(sink.context.toString().contains('user_message'), isFalse);
  });

  test('connection failures are errors', () {
    SqlRpcFailureReporter.report(
      failure: ConnectionFailure.withContext(
        message: 'down',
        context: const {'reason': 'server_unreachable'},
      ),
      rpcError: const RpcError(code: RpcErrorCode.internalError, message: 'internal'),
      rpcMethod: 'sql.execute',
      sql: 'UPDATE orders SET n = 1',
    );
    expect(sink.level, 'ERROR');
    expect(sink.context?['sql_verb'], 'UPDATE');
  });
}
