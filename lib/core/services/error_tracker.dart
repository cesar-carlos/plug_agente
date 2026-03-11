import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/errors.dart';

class ErrorTracker {
  ErrorTracker._();

  static bool _isInitialized = false;
  static String _dsn = '';
  static String _environment = 'development';
  static String _release = '';
  static Map<String, dynamic> _tags = {};

  static Future<void> initialize({
    String dsn = '',
    String environment = 'development',
    String release = '',
    Map<String, dynamic> tags = const {},
  }) async {
    _dsn = dsn;
    _environment = environment;
    _release = release;
    _tags = tags;

    if (dsn.isEmpty) {
      AppLogger.warning('Error tracking disabled (no DSN provided)');
      return;
    }

    _isInitialized = true;
    AppLogger.info('Error tracking initialized: $_environment');
  }

  static void captureException(
    Object exception,
    StackTrace stackTrace, {
    String? operation,
    Map<String, dynamic> context = const {},
    bool fatal = false,
  }) {
    if (!_isInitialized || _dsn.isEmpty) {
      // Fallback to local logging only
      AppLogger.error(
        'Exception captured: $exception',
        exception,
        stackTrace,
      );
      return;
    }

    AppLogger.error(
      'Exception tracked: $exception',
      exception,
      stackTrace,
    );
  }

  static void captureFailure(
    Failure failure, {
    String? operation,
    Map<String, dynamic> additionalContext = const {},
    StackTrace? stackTrace,
  }) {
    if (!_isInitialized || _dsn.isEmpty) {
      // Log to local only
      AppLogger.error(
        '[${failure.code}] ${failure.message}',
        failure.cause,
        stackTrace,
      );
      return;
    }

    AppLogger.error(
      'Failure tracked: [${failure.code}] ${failure.message}',
      failure.cause,
      stackTrace,
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
}
