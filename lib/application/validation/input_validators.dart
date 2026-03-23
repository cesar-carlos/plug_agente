import 'package:plug_agente/application/validation/zard_adapter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:zard/zard.dart';

class InputValidators {
  InputValidators._();

  static final RegExp _usernameCharClass = RegExp(r'^[a-z0-9_-]+$');
  static final RegExp _databaseNameCharClass = RegExp(r'^[a-zA-Z0-9_]+$');

  static Result<String> email(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .email(message: message ?? 'Invalid email address')
        .trim()
        .toLowerCase();

    return schema.parseSafe(value);
  }

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

  static Result<String> url(
    String value, {
    String? message,
  }) {
    final schema = z.string().url(message: message ?? 'Invalid URL').trim();

    return schema.parseSafe(value);
  }

  static Result<String> httpUrl(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .httpUrl(message: message ?? 'Invalid HTTP(S) URL')
        .trim();

    return schema.parseSafe(value);
  }

  static Result<String> hostname(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .hostname(message: message ?? 'Invalid hostname')
        .trim()
        .toLowerCase();

    return schema.parseSafe(value);
  }

  static Result<String> ipv4(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .ipv4(message: message ?? 'Invalid IPv4 address')
        .trim();

    return schema.parseSafe(value);
  }

  static Result<int> port(
    int value, {
    String? message,
  }) {
    final schema = z.int()
        .min(1, message: message ?? 'Port must be at least 1')
        .max(65535, message: message ?? 'Port must be at most 65535');

    return schema.parseSafe(value);
  }

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

  static Result<String> username(
    String value, {
    int minLength = 3,
    int maxLength = 50,
    String? message,
  }) {
    final schema = z
        .string()
        .min(
          minLength,
          message: message ?? 'Username must be at least $minLength characters',
        )
        .max(
          maxLength,
          message: message ?? 'Username must be at most $maxLength characters',
        )
        .trim()
        .toLowerCase()
        .refine(
          _usernameCharClass.hasMatch,
          message:
              message ??
              'Username can only contain letters, numbers, underscores, and hyphens',
        );

    return schema.parseSafe(value);
  }

  static Result<String> databaseName(
    String value, {
    int minLength = 1,
    int maxLength = 64,
    String? message,
  }) {
    final schema = z
        .string()
        .min(
          minLength,
          message:
              message ??
              'Database name must be at least $minLength character(s)',
        )
        .max(
          maxLength,
          message:
              message ?? 'Database name must be at most $maxLength characters',
        )
        .trim()
        .refine(
          _databaseNameCharClass.hasMatch,
          message:
              message ??
              'Database name can only contain letters, numbers, and underscores',
        );

    return schema.parseSafe(value);
  }
}
