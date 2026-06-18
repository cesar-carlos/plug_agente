import 'package:logger/logger.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';

class ConsoleStructuredLogSink implements IStructuredLogSink {
  ConsoleStructuredLogSink({Logger? logger})
    : _logger =
          logger ??
          Logger(
            printer: PrettyPrinter(
              dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
            ),
          );

  final Logger _logger;

  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    final enrichedMessage = _enrichMessage(message, context);
    switch (level) {
      case 'WARNING':
        _logger.w(enrichedMessage, error: error, stackTrace: stackTrace);
      case 'ERROR':
        _logger.e(enrichedMessage, error: error, stackTrace: stackTrace);
      default:
        _logger.i(enrichedMessage, error: error, stackTrace: stackTrace);
    }
  }

  String _enrichMessage(String message, Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) {
      return message;
    }
    return '$message | context=$context';
  }
}
