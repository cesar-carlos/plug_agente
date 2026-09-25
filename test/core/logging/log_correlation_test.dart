import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/logging/composite_log_sink.dart';
import 'package:plug_agente/core/logging/log_correlation.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/infrastructure/logging/file_log_sink.dart';

class _RecordingSink implements IStructuredLogSink {
  Map<String, dynamic>? context;
  Object? error;

  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    this.context = context;
    this.error = error;
  }
}

void main() {
  test('composite sink adds the current rpc request id', () async {
    final directory = Directory.systemTemp.createTempSync('plug-log');
    final fileSink = FileLogSink(logDirectoryPath: directory.path);
    await fileSink.open();
    final console = _RecordingSink();
    final sink = CompositeLogSink(fileSink: fileSink, consoleSink: console);
    addTearDown(() async {
      await fileSink.close();
      directory.deleteSync(recursive: true);
    });

    await LogCorrelation.run(
      rpcRequestId: 'rpc-1',
      rpcMethod: 'sql.execute',
      body: () async {
        sink.logStructured(level: 'ERROR', message: 'failed', context: const {'reason': 'x'});
      },
    );

    expect(console.context?['rpc_request_id'], 'rpc-1');
    expect(console.context?['rpc_method'], 'sql.execute');
    expect(console.context?['reason'], 'x');
    final logged = File(fileSink.logFilePath).readAsStringSync();
    expect(logged.contains('rpc-1'), isTrue);
    expect(logged.contains('user_message'), isFalse);
  });

  test('file sink records only the failure code and message', () async {
    final directory = Directory.systemTemp.createTempSync('plug-log-failure');
    final fileSink = FileLogSink(logDirectoryPath: directory.path);
    await fileSink.open();
    addTearDown(() async {
      await fileSink.close();
      directory.deleteSync(recursive: true);
    });
    fileSink.logStructured(
      level: 'ERROR',
      message: 'failed',
      error: QueryExecutionFailure.withContext(
        message: 'link lost',
        context: const {'user_message': 'try again', 'reason': 'connection_lost_during_query'},
      ),
      context: const {'reason': 'connection_lost_during_query'},
    );
    final logged = File(fileSink.logFilePath).readAsStringSync();
    expect(logged.contains('[QUERY_ERROR] link lost'), isTrue);
    expect(logged.contains('try again'), isFalse);
  });
}
