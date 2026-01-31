import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:zard/zard.dart';

/// Extension to convert ZardResult to result_dart `Result<T>`.
extension ZardResultExtension<T extends Object> on ZardResult<T> {
  /// Converts Zard safeParse result to `Result<T>`.
  ///
  /// Example:
  /// ```dart
  /// final zardResult = schema.safeParse(value);
  /// final result = zardResult.toResult();
  /// ```
  Result<T> toResult() {
    if (success && data != null) {
      return Success(data!);
    }

    final errorMsg = error?.messages ?? error?.toString() ?? 'Validation failed';

    return Failure(domain.ValidationFailure(errorMsg));
  }
}

/// Extension to integrate Zard schemas directly with result_dart.
extension ZardSchemaExtension<T extends Object> on Schema<T> {
  /// Parse and return `Result<T>` instead of ZardResult.
  ///
  /// Example:
  /// ```dart
  /// final schema = z.string().min(3).email();
  /// final result = schema.parseSafe('user@example.com');
  /// ```
  Result<T> parseSafe(dynamic value) {
    final zardResult = safeParse(value);
    return zardResult.toResult();
  }
}

/// Adapter utilities for Zard integration with result_dart.
class ZardAdapter {
  ZardAdapter._();

  /// Creates a `Result<bool>` from Zard validation.
  static Result<bool> validateBool(ZardResult<dynamic> zardResult) {
    if (zardResult.success) {
      return const Success(true);
    }

    final errorMsg = zardResult.error?.messages ??
        zardResult.error?.toString() ??
        'Validation failed';

    return Failure(domain.ValidationFailure(errorMsg));
  }

  /// Creates a `Result<T>` from Zard parse result.
  static Result<T> validate<T extends Object>(ZardResult<T> zardResult) {
    if (zardResult.success && zardResult.data != null) {
      return Success(zardResult.data!);
    }

    final errorMsg = zardResult.error?.messages ??
        zardResult.error?.toString() ??
        'Validation failed';

    return Failure(domain.ValidationFailure(errorMsg));
  }
}
