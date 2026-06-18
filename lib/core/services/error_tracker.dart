import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/domain/utils/log_sanitizer.dart';

/// Local error tracking facade with optional remote backend integration.
///
/// When no DSN is configured, errors are routed to the composite structured
/// sink (console + file) when available, otherwise to [AppLogger] only.
class ErrorTracker {
  ErrorTracker._();

  static bool _isInitialized = false;
  static String _dsn = '';
  static String _environment = 'development';
  static String _release = '';
  static Map<String, dynamic> _tags = {};
  static IStructuredLogSink? _sink;

  static Future<void> initialize({
    String dsn = '',
    String environment = 'development',
    String release = '',
    Map<String, dynamic> tags = const {},
    IStructuredLogSink? sink,
  }) async {
    _dsn = dsn;
    _environment = environment;
    _release = release;
    _tags = tags;
    _sink = sink;
    _isInitialized = true;

    if (dsn.isEmpty) {
      AppLogger.info('Error tracking initialized without remote DSN');
      return;
    }

    AppLogger.info('Error tracking initialized: $_environment');
  }

  static void captureException(
    Object exception,
    StackTrace stackTrace, {
    String? operation,
    Map<String, dynamic> context = const {},
    bool fatal = false,
  }) {
    final enrichedContext = _enrichContext(
      operation: operation,
      context: context,
      fatal: fatal,
    );
    final message = fatal ? 'Fatal exception captured: $exception' : 'Exception captured: $exception';

    _log(
      level: 'ERROR',
      message: message,
      error: exception,
      stackTrace: stackTrace,
      context: enrichedContext,
    );
  }

  static void captureFailure(
    Failure failure, {
    String? operation,
    Map<String, dynamic> additionalContext = const {},
    StackTrace? stackTrace,
  }) {
    failure.log(
      stackTrace: stackTrace,
      operation: operation,
      additionalContext: additionalContext,
    );
  }

  static void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    _log(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  static void addBreadcrumb({
    required String category,
    required String message,
    Map<String, dynamic>? data,
  }) {
    if (!_isInitialized || _dsn.isEmpty) {
      return;
    }

    AppLogger.debug('Breadcrumb: [$category] $message');
  }

  static void setUser({
    String? id,
    String? email,
    String? username,
    Map<String, dynamic>? others,
  }) {
    if (!_isInitialized || _dsn.isEmpty) {
      return;
    }

    AppLogger.info('User set for error tracking: ${username ?? email ?? id}');
  }

  static void clearUser() {
    if (!_isInitialized || _dsn.isEmpty) {
      return;
    }

    AppLogger.info('User cleared from error tracking');
  }

  static bool get isEnabled => _isInitialized && _dsn.isNotEmpty;

  static Map<String, dynamic> get config => {
    'initialized': _isInitialized,
    'dsn': _dsn.isEmpty
        ? '<empty>'
        : _dsn.length <= 20
        ? _dsn
        : '${_dsn.substring(0, 20)}...',
    'environment': _environment,
    'release': _release,
    'tags': _tags,
  };

  static void _log({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    final sink = _sink;
    if (sink != null) {
      sink.logStructured(
        level: level,
        message: message,
        error: error,
        stackTrace: stackTrace,
        context: _sanitizeContext(context),
      );
      return;
    }

    if (level == 'WARNING') {
      AppLogger.warning(message, error, stackTrace, context);
      return;
    }

    AppLogger.error(message, error, stackTrace, context);
  }

  static Map<String, dynamic> _enrichContext({
    required Map<String, dynamic> context,
    String? operation,
    bool fatal = false,
  }) {
    return <String, dynamic>{
      'operation': ?operation,
      if (fatal) 'fatal': true,
      ...context,
    };
  }

  static Map<String, dynamic>? _sanitizeContext(Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) {
      return null;
    }
    return LogSanitizer.sanitizeMap(Map<String, dynamic>.from(context));
  }
}
