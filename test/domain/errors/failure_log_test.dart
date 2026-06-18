import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/domain/logging/structured_log_sink_registry.dart';

class _CapturingStructuredLogSink implements IStructuredLogSink {
  final entries = <Map<String, dynamic>>[];

  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    entries.add(<String, dynamic>{
      'level': level,
      'message': message,
      'error': error,
      'stackTrace': stackTrace,
      'context': context,
    });
  }
}

void main() {
  group('Failure.log', () {
    late _CapturingStructuredLogSink sink;

    setUp(() {
      sink = _CapturingStructuredLogSink();
      StructuredLogSinkRegistry.register(sink);
    });

    tearDown(StructuredLogSinkRegistry.reset);

    test('should route through structured sink with sanitized context', () {
      final failure = ServerFailure.withContext(
        message: 'Startup bootstrap failed',
        cause: StateError('hub rejected credentials'),
        context: <String, dynamic>{
          'operation': 'bootstrap',
          'password': 'do-not-log',
        },
      );

      failure.log(
        stackTrace: StackTrace.current,
        operation: 'startup_session_bootstrap',
      );

      expect(sink.entries, hasLength(1));
      final entry = sink.entries.single;
      expect(entry['level'], 'ERROR');
      expect(entry['message'], contains('SERVER_ERROR'));
      expect(entry['message'], contains('Startup bootstrap failed'));
      expect(entry['error'], isA<StateError>());

      final context = entry['context'] as Map<String, dynamic>;
      expect(context['operation'], 'startup_session_bootstrap');
      expect(context['password'], '[REDACTED]');
    });
  });
}
