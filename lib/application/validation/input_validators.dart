import 'package:plug_agente/application/validation/zard_adapter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:zard/zard.dart';

/// Validators for user input using Zard
class InputValidators {
  InputValidators._();

  /// Email validator
  ///
  /// Validates email format using HTML5 pattern (allows john@example)
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.email('user@example.com');
  /// // Success('user@example.com')
  ///
  /// final result2 = InputValidators.email('invalid');
  /// // Failure(ValidationFailure('Invalid email address'))
  /// ```
  static Result<String> email(
    String value, {
    String? message,
  }) {
    final schema = z.string().email(message: message ?? 'Invalid email address').trim().toLowerCase();

    return schema.parseSafe(value);
  }

  /// Email validator with strict pattern (requires TLD)
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.emailStrict('user@example.com');
  /// // Success('user@example.com')
  ///
  /// final result2 = InputValidators.emailStrict('user@example');
  /// // Failure(ValidationFailure('Invalid email address'))
  /// ```
  static Result<String> emailStrict(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .email(
          pattern: z.regexes.email,
          message: message ?? 'Invalid email address',
        )
        .trim()
        .toLowerCase();

    return schema.parseSafe(value);
  }

  /// URL validator
  ///
  /// Validates HTTP/HTTPS URLs
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.url('https://example.com');
  /// // Success('https://example.com')
  ///
  /// final result2 = InputValidators.url('not-a-url');
  /// // Failure(ValidationFailure('Invalid URL'))
  /// ```
  static Result<String> url(
    String value, {
    String? message,
  }) {
    final schema = z.string().url(message: message ?? 'Invalid URL').trim();

    return schema.parseSafe(value);
  }

  /// HTTP URL validator (only HTTP/HTTPS)
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.httpUrl('https://example.com');
  /// // Success('https://example.com')
  ///
  /// final result2 = InputValidators.httpUrl('ftp://example.com');
  /// // Failure(ValidationFailure('Invalid HTTP(S) URL'))
  /// ```
  static Result<String> httpUrl(
    String value, {
    String? message,
  }) {
    final schema = z.string().httpUrl(message: message ?? 'Invalid HTTP(S) URL').trim();

    return schema.parseSafe(value);
  }

  /// Hostname validator
  ///
  /// Validates hostname format (e.g., api.example.com)
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.hostname('api.example.com');
  /// // Success('api.example.com')
  ///
  /// final result2 = InputValidators.hostname('invalid hostname');
  /// // Failure(ValidationFailure('Invalid hostname'))
  /// ```
  static Result<String> hostname(
    String value, {
    String? message,
  }) {
    final schema = z.string().hostname(message: message ?? 'Invalid hostname').trim().toLowerCase();

    return schema.parseSafe(value);
  }

  /// IPv4 address validator
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.ipv4('192.168.1.1');
  /// // Success('192.168.1.1')
  ///
  /// final result2 = InputValidators.ipv4('256.0.0.1');
  /// // Failure(ValidationFailure('Invalid IPv4 address'))
  /// ```
  static Result<String> ipv4(
    String value, {
    String? message,
  }) {
    final schema = z.string().ipv4(message: message ?? 'Invalid IPv4 address').trim();

    return schema.parseSafe(value);
  }

  /// Port number validator (1-65535)
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.port(3306);
  /// // Success(3306)
  ///
  /// final result2 = InputValidators.port(0);
  /// // Failure(ValidationFailure('Port must be at least 1'))
  ///
  /// final result3 = InputValidators.port(70000);
  /// // Failure(ValidationFailure('Port must be at most 65535'))
  /// ```
  static Result<int> port(
    int value, {
    String? message,
  }) {
    final schema = z.int()
        .min(1, message: message ?? 'Port must be at least 1')
        .max(65535, message: message ?? 'Port must be at most 65535');

    return schema.parseSafe(value);
  }

  /// Non-empty string validator
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.nonEmptyString('hello');
  /// // Success('hello')
  ///
  /// final result2 = InputValidators.nonEmptyString('  ');
  /// // Failure(ValidationFailure('Value cannot be empty'))
  /// ```
  static Result<String> nonEmptyString(
    String value, {
    int? minLength,
    int? maxLength,
    String? message,
  }) {
    var schema = z.string().trim();

    if (minLength != null) {
      schema = schema.min(
        minLength,
        message: message ?? 'Value must be at least $minLength characters',
      );
    }

    if (maxLength != null) {
      schema = schema.max(
        maxLength,
        message: message ?? 'Value must be at most $maxLength characters',
      );
    }

    return schema.parseSafe(value);
  }

  /// Username validator (alphanumeric, underscores, hyphens)
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.username('user_123');
  /// // Success('user_123')
  ///
  /// final result2 = InputValidators.username('user@123');
  /// // Failure(ValidationFailure('Invalid username'))
  /// ```
  static Result<String> username(
    String value, {
    int minLength = 3,
    int maxLength = 50,
    String? message,
  }) {
    final schema = z
        .string()
        .min(minLength, message: message ?? 'Username must be at least $minLength characters')
        .max(maxLength, message: message ?? 'Username must be at most $maxLength characters')
        .trim()
        .toLowerCase()
        .refine(
          (val) => RegExp(r'^[a-z0-9_-]+$').hasMatch(val),
          message: message ?? 'Username can only contain letters, numbers, underscores, and hyphens',
        );

    return schema.parseSafe(value);
  }

  /// Database name validator
  ///
  /// Example:
  /// ```dart
  /// final result = InputValidators.databaseName('my_database');
  /// // Success('my_database')
  ///
  /// final result2 = InputValidators.databaseName('my database');
  /// // Failure(ValidationFailure('Invalid database name'))
  /// ```
  static Result<String> databaseName(
    String value, {
    int minLength = 1,
    int maxLength = 64,
    String? message,
  }) {
    final schema = z
        .string()
        .min(minLength, message: message ?? 'Database name must be at least $minLength character(s)')
        .max(maxLength, message: message ?? 'Database name must be at most $maxLength characters')
        .trim()
        .refine(
          (val) => RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(val),
          message: message ?? 'Database name can only contain letters, numbers, and underscores',
        );

    return schema.parseSafe(value);
  }
}
