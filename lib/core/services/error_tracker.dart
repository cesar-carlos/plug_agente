import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/errors.dart';

/// Error tracking service for monitoring and reporting errors.
///
/// Prepares the application for integration with error tracking services
/// like Sentry or Crashlytics.
///
/// Usage:
/// ```dart
/// await ErrorTracker.initialize(
///   dsn: 'your-sentry-dsn',
///   environment: 'production',
/// );
///
/// // Track errors
/// ErrorTracker.captureException(exception, stackTrace);
/// ErrorTracker.captureFailure(failure);
/// ```
class ErrorTracker {
  ErrorTracker._();

  static bool _isInitialized = false;
  static String _dsn = '';
  static String _environment = 'development';
  static String _release = '';
  static Map<String, dynamic> _tags = {};

  /// Initializes the error tracking service.
  ///
  /// Call this once at app startup, typically in main().
  ///
  /// Parameters:
  /// - [dsn]: Data Source Name for Sentry (empty string to disable)
  /// - [environment]: Environment name (development, staging, production)
  /// - [release]: Release version
  /// - [tags]: Additional tags for all events
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

    // TODO: Initialize Sentry here when package is added
    // await SentryFlutter.init(
    //   dsn: dsn,
    //   environment: environment,
    //   release: release,
    // );

    _isInitialized = true;
    AppLogger.info('Error tracking initialized: $_environment');
  }

  /// Captures an exception and reports it to the error tracking service.
  ///
  /// Use this in catch blocks to automatically report exceptions.
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   await riskyOperation();
  /// } catch (e, st) {
  ///   ErrorTracker.captureException(e, st);
  /// }
  /// ```
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

    // TODO: Send to Sentry when package is added
    // await Sentry.captureException(
    //   exception,
    //   stackTrace: stackTrace,
    //   hint: Hint.withHint(
    //     operation: operation,
    //     ...context,
    //   ),
    // );

    AppLogger.error(
      'Exception tracked: $exception',
      exception,
      stackTrace,
    );
  }

  /// Captures a [Failure] and reports it to the error tracking service.
  ///
  /// Use this when working with domain failures.
  ///
  /// Example:
  /// ```dart
  /// result.fold(
  ///   (success) => _data = success,
  ///   (failure) => ErrorTracker.captureFailure(failure),
  /// );
  /// ```
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

    // TODO: Send to Sentry when package is added
    // await Sentry.captureEvent(
    //   SentryEvent(
    //     level: fatal ? SentryLevel.fatal : SentryLevel.error,
    //     message: SentryMessage(failure.message),
    //     exception: failure.cause?.toString(),
    //     tags: {
    ///       'failure_code': failure.code,
    //       ..._tags,
    //     },
    //     extra: {
    //       if (operation != null) 'operation': operation,
    //       ...failure.context,
    //       ...additionalContext,
    //     },
    //   ),
    // );

    AppLogger.error(
      'Failure tracked: [${failure.code}] ${failure.message}',
      failure.cause,
      stackTrace,
    );
  }

  /// Adds a breadcrumb for tracking user navigation and actions.
  ///
  /// Breadcrumbs help debug issues by showing what happened before an error.
  ///
  /// Example:
  /// ```dart
  /// ErrorTracker.addBreadcrumb(
  ///   category: 'ui',
  ///   message: 'User clicked save button',
  ///   data: {'page': 'config'},
  /// );
  /// ```
  static void addBreadcrumb({
    required String category,
    required String message,
    Map<String, dynamic>? data,
  }) {
    if (!_isInitialized || _dsn.isEmpty) {
      return;
    }

    // TODO: Send to Sentry when package is added
    // Sentry.addBreadcrumb(
    //   Breadcrumb(
    //     category: category,
    //     message: message,
    //     data: data,
    //   ),
    // );

    AppLogger.debug('Breadcrumb: [$category] $message');
  }

  /// Sets the user identifier for error tracking.
  ///
  /// Call this when a user logs in to associate errors with that user.
  ///
  /// Example:
  /// ```dart
  /// ErrorTracker.setUser(id: user.id, email: user.email);
  /// ```
  static void setUser({
    String? id,
    String? email,
    String? username,
    Map<String, dynamic>? others,
  }) {
    if (!_isInitialized || _dsn.isEmpty) {
      return;
    }

    // TODO: Send to Sentry when package is added
    // Sentry.configureScope((scope) {
    //   scope.setUser(SentryUser(
    //     id: id,
    //     email: email,
    //     username: username,
    //     others: others,
    //   ));
    // });

    AppLogger.info('User set for error tracking: ${username ?? email ?? id}');
  }

  /// Clears the current user (e.g., on logout).
  static void clearUser() {
    if (!_isInitialized || _dsn.isEmpty) {
      return;
    }

    // TODO: Send to Sentry when package is added
    // Sentry.configureScope((scope) {
    //   scope.setUser(null);
    // });

    AppLogger.info('User cleared from error tracking');
  }

  /// Checks if error tracking is enabled and initialized.
  static bool get isEnabled => _isInitialized && _dsn.isNotEmpty;

  /// Gets current configuration (useful for debugging).
  static Map<String, dynamic> get config => {
    'initialized': _isInitialized,
    'dsn': _dsn.isEmpty ? '<empty>' : '${_dsn.substring(0, 20)}...',
    'environment': _environment,
    'release': _release,
    'tags': _tags,
  };
}
