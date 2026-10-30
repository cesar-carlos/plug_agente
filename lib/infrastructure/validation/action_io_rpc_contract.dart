import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/repositories/i_action_io_rpc_contract.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoRpcContract implements IActionIoRpcContract {
  ActionIoRpcContract(this._validator);
  final JsonSchemaContractValidator _validator;
  static const _catalog = RpcMethodSchemaCatalog();

  @override
  Result<Unit> validateParams(String method, Object? params) =>
      _validate(_catalog.paramsSchemaFor(method), params, false);

  @override
  Result<Unit> validateResult(String method, Object? result) =>
      _validate(_catalog.resultSchemaFor(method), result, true);

  Result<Unit> _validate(String? schema, Object? value, bool response) {
    if (schema == null || !_validator.isLoaded(schema)) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'The I/O contract is unavailable.',
          code: 'ACTION_IO_CONTRACT_UNAVAILABLE',
          context: {'retryable': false},
        ),
      );
    }
    final result = _validator.validate(schemaId: schema, payload: value, direction: response ? 'outbound' : 'inbound');
    if (result.isSuccess()) return const Success(unit);
    // Schema diagnostics can contain caller bytes; do not forward them.
    return Failure(
      response
          ? ActionRuntimeFailure.withContext(
              message: 'The I/O response does not match its contract.',
              code: 'ACTION_IO_RESPONSE_INVALID',
              context: {'retryable': false},
            )
          : ActionValidationFailure.withContext(
              message: 'Invalid I/O parameters.',
              code: 'ACTION_IO_INVALID_INPUT',
              context: {'retryable': false},
            ),
    );
  }
}
