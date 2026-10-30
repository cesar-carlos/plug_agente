import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/domain/logging/structured_log_sink_registry.dart';
import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';

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

    for (final pipe in [false, true]) {
      test('faithful ${pipe ? 'pipe' : 'storage'} failure keeps raw cause out of diagnostics', () {
        final cause = StateError('private-process-bytes-and-credential');
        final failure = pipe
            ? ActionIoPipeFailure(confirmedBytes: 2, cause: cause)
            : ActionRuntimeFailure.withContext(
                message: 'The I/O journal could not be updated.',
                code: 'ACTION_IO_STORAGE_FAILED',
                cause: cause,
                context: {'retryable': false, 'native_code': 112},
              );
        failure.log();
        expect(failure.cause, same(cause));
        expect(sink.entries.single['error'], 'StateError');
        expect(sink.entries.toString(), isNot(contains('private-process-bytes-and-credential')));
        expect(failure.toString(), isNot(contains('private-process-bytes-and-credential')));
        expect(failure.toString(), contains(failure.code));
        if (!pipe) expect((sink.entries.single['context'] as Map)['native_code'], 112);
      });
    }

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
