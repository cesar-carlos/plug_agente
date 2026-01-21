import 'package:logger/logger.dart';

class AppLogger {
  static final Logger _instance = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
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
      _instance.d('Parameters: $parameters');
    }
  }

  static void logNetwork(String method, String url, [dynamic data]) {
    _instance.d('$method $url');
    if (data != null) {
      _instance.d('Data: $data');
    }
  }
}
