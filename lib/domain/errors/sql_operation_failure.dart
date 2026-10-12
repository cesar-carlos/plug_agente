import 'package:plug_agente/domain/errors/failures.dart';

class SqlOperationFailure extends Failure {
  SqlOperationFailure({
    required String code,
    required super.message,
    super.cause,
    super.context,
  }) : super.withContext(defaultCode: code);
}
