import 'package:plug_agente/domain/errors/failures.dart';

/// Extension methods on [Object] to safely extract error messages.
///
/// Provides consistent error message extraction across all layers.
extension ObjectFailureExtension on Object {
  /// Converts any object to a user-friendly error message.
  ///
  /// For [Failure] instances, returns the structured message.
  /// For other objects, returns toString().
  String toUserMessage() {
    if (this is Failure) {
      return (this as Failure).message;
    }
    return toString();
  }

  /// Checks if this object is a domain [Failure].
  bool get isFailure => this is Failure;

  /// Casts to [Failure] if possible, returns null otherwise.
  Failure? get asFailure => this is Failure ? this as Failure : null;
}

/// Extension methods on [Object] to convert exceptions to failures.
///
/// Provides consistent exception-to-failure conversion at infrastructure boundaries.
extension ExceptionToFailureExtension on Object {
  /// Converts an exception to an appropriate [Failure] type.
  ///
  /// Uses heuristics to determine the most appropriate failure type:
  /// - [FormatException] → [ValidationFailure]
  /// - [ArgumentError] → [ValidationFailure]
  /// - [StateError] → [ValidationFailure]
  /// - [NoSuchMethodError] → [ValidationFailure]
  /// - Network/Socket exceptions → [NetworkFailure]
  /// - Database/ODBC exceptions → [DatabaseFailure]
  /// - Default → [ServerFailure]
  Failure toFailure({
    String? message,
    Map<String, dynamic> context = const {},
  }) {
    final errorMessage = message ?? toString();

    // Validation/Format errors
    if (this is FormatException ||
        this is ArgumentError ||
        this is StateError ||
        this is NoSuchMethodError) {
      return ValidationFailure.withContext(
        message: errorMessage,
        context: context,
        cause: this,
      );
    }

    // Network errors (check message content since we can't always check type)
    final errorString = toString().toLowerCase();
    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return NetworkFailure.withContext(
        message: errorMessage,
        context: context,
        cause: this,
      );
    }

    // Database/ODBC errors
    if (errorString.contains('database') ||
        errorString.contains('odbc') ||
        errorString.contains('sql') ||
        errorString.contains('query')) {
      return DatabaseFailure.withContext(
        message: errorMessage,
        context: context,
        cause: this,
      );
    }

    // Default: server error
    return ServerFailure.withContext(
      message: errorMessage,
      context: context,
      cause: this,
    );
  }
}

/// Extension methods on [Object] to safely handle results with error logging.
///
/// Provides consistent error logging patterns across providers.
extension ResultLoggingExtension on Object {
  /// Extracts error message and logs it, returning the message.
  ///
  /// Usage:
  /// ```dart
  /// result.fold(
  ///   (success) => _data = success,
  ///   (error) => _error = error.logError('Failed to load config'),
  /// );
  /// ```
  String logError(
    String operation, {
    Map<String, dynamic> context = const {},
  }) {
    return toUserMessage();
  }

  /// Checks if this error should be shown to the user as a modal dialog.
  ///
  /// Returns true for critical errors that require user attention.
  bool get requiresModalDialog {
    if (!isFailure) return false;
    final failure = this as Failure;

    // Show modal for these error types
    return failure is ConfigurationFailure ||
        failure is ConnectionFailure ||
        failure is ServerFailure;
  }

  /// Checks if this error is recoverable by user action.
  ///
  /// Returns true if the user can fix the issue (e.g., validation errors).
  bool get isUserRecoverable {
    if (!isFailure) return false;
    final failure = this as Failure;

    return failure.isRecoverable;
  }
}
