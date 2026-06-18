import 'package:logger/logger.dart';
import 'package:plug_agente/core/utils/log_sanitizer.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';

class AppLogger {
  static final Logger _instance = Logger(
    printer: PrettyPrinter(
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static IStructuredLogSink? _structuredSink;

  static void attachStructuredSink(IStructuredLogSink sink) {
    _structuredSink = sink;
  }

  static void detachStructuredSink() {
    _structuredSink = null;
  }

  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.i(message, error: error, stackTrace: stackTrace);
  }

  static void warning(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ]) {
    final sink = _structuredSink;
    if (sink != null) {
      sink.logStructured(
        level: 'WARNING',
        message: message,
        error: error,
        stackTrace: stackTrace,
        context: _sanitizeContext(context),
      );
      return;
    }
    _instance.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ]) {
    final sink = _structuredSink;
    if (sink != null) {
      sink.logStructured(
        level: 'ERROR',
        message: message,
        error: error,
        stackTrace: stackTrace,
        context: _sanitizeContext(context),
      );
      return;
    }
    _instance.e(message, error: error, stackTrace: stackTrace);
  }

  static void logQuery(String query, Map<String, dynamic>? parameters) {
    _instance.d('Query: $query');
    if (parameters != null && parameters.isNotEmpty) {
      final sanitized = LogSanitizer.sanitizeParameters(parameters);
      _instance.d('Parameters: $sanitized');
    }
  }

  static void logNetwork(String method, String url, [dynamic data]) {
    _instance.d('$method $url');
    if (data != null) {
      final sanitized = data is Map<String, dynamic> ? LogSanitizer.sanitizeParameters(data) : data.toString();
      _instance.d('Data: $sanitized');
    }
  }

  static Map<String, dynamic>? _sanitizeContext(Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) {
      return null;
    }
    return LogSanitizer.sanitizeMap(Map<String, dynamic>.from(context));
  }
}
