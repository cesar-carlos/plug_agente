import 'dart:async';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

class OdbcErrorInspector {
  OdbcErrorInspector._();

  static OdbcError? structuredError(Object error, [Set<Object>? visited]) {
    final seen = visited ?? Set<Object>.identity();
    if (!seen.add(error)) return null;
    if (error is OdbcError) return error;
    if (error is OdbcErrorConvertible) return error.toOdbcError();
    if (error is domain.Failure) {
      final cause = error.cause;
      final nested = error.context['error'];
      return (cause == null ? null : structuredError(cause, seen)) ??
          (nested is Object ? structuredError(nested, seen) : null);
    }
    return null;
  }

  static bool outcomeUnknown(Object error, [Set<Object>? visited]) {
    final seen = visited ?? Set<Object>.identity();
    if (!seen.add(error)) return false;
    if (structuredError(error)?.details.outcomeUnknown ?? false) return true;
    if (error is domain.Failure) {
      if (error.context['outcome_unknown'] == true) return true;
      final cause = error.cause;
      final nested = error.context['error'];
      return (cause != null && outcomeUnknown(cause, seen)) || (nested is Object && outcomeUnknown(nested, seen));
    }
    return false;
  }

  static OdbcErrorCode? code(Object error) => structuredError(error)?.code;

  static String message(Object error) {
    final structured = structuredError(error);
    if (structured != null) return structured.message;
    if (error is OdbcError) {
      return error.message;
    }

    if (error is domain.Failure) {
      final cause = error.cause;
      if (cause is OdbcError) {
        return cause.message;
      }

      final nestedError = error.context['error'];
      if (nestedError is Object && !identical(nestedError, error)) {
        return message(nestedError);
      }
    }

    return error.toString();
  }

  static String? sqlState(Object error) {
    final structured = structuredError(error);
    if (structured != null) return _normalizeSqlState(structured.sqlState);
    if (error is domain.Failure) {
      final contextSqlState = _normalizeSqlState(error.context['odbc_sql_state']);
      if (contextSqlState != null) {
        return contextSqlState;
      }

      final cause = error.cause;
      if (cause != null && !identical(cause, error)) {
        final causeSqlState = sqlState(cause);
        if (causeSqlState != null) {
          return causeSqlState;
        }
      }

      final nestedError = error.context['error'];
      if (nestedError is Object && !identical(nestedError, error)) {
        return sqlState(nestedError);
      }

      return null;
    }

    if (error is OdbcError) {
      return _normalizeSqlState(error.sqlState);
    }

    return null;
  }

  static int? nativeCode(Object error) {
    final structured = structuredError(error);
    if (structured != null) return structured.nativeCode;
    if (error is domain.Failure) {
      final contextNativeCode = _normalizeNativeCode(
        error.context['odbc_native_code'],
      );
      if (contextNativeCode != null) {
        return contextNativeCode;
      }

      final cause = error.cause;
      if (cause != null && !identical(cause, error)) {
        final causeNativeCode = nativeCode(cause);
        if (causeNativeCode != null) {
          return causeNativeCode;
        }
      }

      final nestedError = error.context['error'];
      if (nestedError is Object && !identical(nestedError, error)) {
        return nativeCode(nestedError);
      }

      return null;
    }

    if (error is OdbcError) {
      return error.nativeCode;
    }

    return null;
  }

  static bool isTimeout(Object error) {
    final structured = structuredError(error);
    if (structured != null && structured.details.code != null) {
      return structured.code == OdbcErrorCode.timeout;
    }
    if (code(error) == OdbcErrorCode.timeout) return true;
    if (error is TimeoutException) {
      return true;
    }

    final extractedSqlState = sqlState(error);
    if (extractedSqlState == 'HYT00' || extractedSqlState == 'HYT01') {
      return true;
    }

    final normalizedMessage = message(error).toLowerCase();
    return normalizedMessage.contains('timeout') || normalizedMessage.contains('timed out');
  }

  static bool isInvalidConnectionId(Object error) {
    if (nativeCode(error) == 100000) {
      return true;
    }

    if (error is domain.Failure) {
      final cause = error.cause;
      if (cause != null && !identical(cause, error) && isInvalidConnectionId(cause)) {
        return true;
      }

      final nestedError = error.context['error'];
      if (nestedError is Object && !identical(nestedError, error) && isInvalidConnectionId(nestedError)) {
        return true;
      }

      return _messageLooksLikeInvalidConnectionId(error.message);
    }

    return _messageLooksLikeInvalidConnectionId(message(error));
  }

  static String? _normalizeSqlState(Object? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim().toUpperCase();
    return normalized.isEmpty ? null : normalized;
  }

  static int? _normalizeNativeCode(Object? value) {
    if (value case final num nativeCode) {
      return nativeCode.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  static bool _messageLooksLikeInvalidConnectionId(String message) {
    return message.toLowerCase().contains('invalid connection id');
  }
}
