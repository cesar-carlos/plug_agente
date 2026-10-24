import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';

class SourceSchemaRpcHandler implements RpcMethodHandler {
  const SourceSchemaRpcHandler(this.configs, this.tokens, this.probe);
  final IQueryConfigSource configs;
  final ClientTokenValidationService tokens;
  final ISourceSchemaProbe probe;
  @override
  String get method => 'sql.describeSchema';
  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    try {
      final token = context.clientToken;
      if (request.id == null ||
          context.negotiatedExtensions['sourceSchema'] != 1 ||
          context.negotiatedExtensions['sourceIdentity'] != 1 ||
          token == null ||
          token.isEmpty) {
        throw domain.ValidationFailure('Schema capability and credential required.');
      }
      final input = SourceSchemaRequest.fromJson(request.params);
      if ((request.params as Map)['client_token'] != null && (request.params as Map)['client_token'] != token) {
        throw domain.ValidationFailure('Credential binding mismatch.');
      }
      final policy = (await tokens.validate(token)).getOrThrow();
      final config = (await configs.resolveActiveConfig()).getOrThrow();
      if (policy.isRevoked ||
          policy.isCredentialExpiredAt(DateTime.now()) ||
          policy.agentId != context.agentId ||
          config.agentId != context.agentId ||
          policy.payloadDatabaseConstraint != input.database.trim().toLowerCase()) {
        throw domain.ValidationFailure('Source authorization unavailable.');
      }
      final result = (await probe.inspect(config, input, policy)).getOrThrow();
      final current = (await tokens.validate(token)).getOrThrow();
      final active = (await configs.resolveActiveConfig()).getOrThrow();
      if (current.isCredentialExpiredAt(DateTime.now()) ||
          current.toJson().toString() != policy.toJson().toString() ||
          active.id != config.id ||
          active.updatedAt != config.updatedAt ||
          active.connectionString != config.connectionString ||
          active.databaseName != config.databaseName ||
          active.host != config.host ||
          active.port != config.port ||
          active.driverName != config.driverName ||
          active.odbcDriverName != config.odbcDriverName ||
          active.username != config.username ||
          active.password != config.password ||
          active.agentId != config.agentId) {
        throw domain.ValidationFailure('Source authority changed during inspection.');
      }
      return RpcResponse.success(id: request.id, result: result);
    } on Object catch (error) {
      return RpcResponse.error(
        id: request.id,
        error: RpcError(
          code: -32000,
          message: 'Schema inspection unavailable or refused.',
          data: RpcErrorCode.buildErrorData(
            code: -32000,
            technicalMessage: 'Schema inspection unavailable or refused.',
            correlationId: request.meta?.requestId ?? request.id?.toString(),
            retryable: false,
            extra: {'failure_code': error is domain.Failure ? error.code : 'SOURCE_SCHEMA_UNAVAILABLE'},
          ),
        ),
      );
    }
  }
}
