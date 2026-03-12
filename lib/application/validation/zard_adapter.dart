import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:zard/zard.dart';

extension ZardResultExtension<T extends Object> on ZardResult<T> {
  Result<T> toResult() {
    if (success && data != null) {
      return Success(data!);
    }

    final errorMsg =
        error?.messages ?? error?.toString() ?? 'Validation failed';
    return Failure(domain.ValidationFailure(errorMsg));
  }
}

extension ZardSchemaExtension<T extends Object> on Schema<T> {
  Result<T> parseSafe(dynamic value) {
    final zardResult = safeParse(value);
    return zardResult.toResult();
  }
}

class ZardAdapter {
  ZardAdapter._();

  static Result<bool> validateBool(ZardResult<dynamic> zardResult) {
    if (zardResult.success) {
      return const Success(true);
    }

    final errorMsg =
        zardResult.error?.messages ??
        zardResult.error?.toString() ??
        'Validation failed';

    return Failure(domain.ValidationFailure(errorMsg));
  }

  static Result<T> validate<T extends Object>(ZardResult<T> zardResult) {
    if (zardResult.success && zardResult.data != null) {
      return Success(zardResult.data!);
    }

    final errorMsg =
        zardResult.error?.messages ??
        zardResult.error?.toString() ??
        'Validation failed';
    return Failure(domain.ValidationFailure(errorMsg));
  }
}
