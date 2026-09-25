import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/infrastructure/logging/odbc_resilience_log.dart';

class _RecordingSink implements IStructuredLogSink {
  int warnings = 0;
  Map<String, dynamic>? context;

  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    if (level == 'WARNING') {
      warnings++;
      this.context = context;
    }
  }
}

void main() {
  test('resilience log uses a dsn fingerprint and then rate limits', () {
    final sink = _RecordingSink();
    AppLogger.attachStructuredSink(sink);
    addTearDown(AppLogger.detachStructuredSink);
    const connectionString = 'Driver=SQL Server;Server=db;PWD=secret';
    for (var i = 0; i < 8; i++) {
      OdbcResilienceLog.warning(
        event: 'circuit_opened_test',
        connectionString: connectionString,
        reason: 'server_unreachable',
      );
    }
    expect(sink.warnings, lessThan(8));
    expect(sink.warnings, greaterThan(0));
    expect(sink.context?['dsn'].toString().contains('secret'), isFalse);
    expect(sink.context?['event'], 'circuit_opened_test');
  });
}
