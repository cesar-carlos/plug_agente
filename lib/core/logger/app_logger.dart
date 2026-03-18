import 'package:logger/logger.dart';
import 'package:plug_agente/core/utils/log_sanitizer.dart';

class AppLogger {
  static final Logger _instance = Logger(
    printer: PrettyPrinter(
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.i(message, error: error, stackTrace: stackTrace);
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _instance.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
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
      _instance.d('Data: $data');
    }
  }
}
