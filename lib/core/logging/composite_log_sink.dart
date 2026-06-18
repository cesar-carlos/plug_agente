import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/infrastructure/logging/file_log_sink.dart';

class CompositeLogSink implements IStructuredLogSink {
  const CompositeLogSink({
    required this.fileSink,
    required this.consoleSink,
  });

  final FileLogSink fileSink;
  final IStructuredLogSink consoleSink;

  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    consoleSink.logStructured(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
    fileSink.logStructured(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }
}
