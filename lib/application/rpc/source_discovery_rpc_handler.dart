import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/domain/entities/source_discovery.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';

class SourceDiscoveryRpcHandler implements RpcMethodHandler {
  const SourceDiscoveryRpcHandler(this.configs, this.tokens, this.probe);
  final IQueryConfigSource configs;
  final ClientTokenValidationService tokens;
  final ISourceDiscoveryProbe probe;
  @override
  String get method => 'sql.describeSource';
  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    try {
      final p = request.params;
      final token = context.clientToken;
      if (request.id == null ||
          context.negotiatedExtensions['sourceDiscovery'] != 1 ||
          token == null ||
          token.isEmpty ||
          p is! Map<String, dynamic> ||
          p.keys.any((k) => !['contractVersion', 'database', 'client_token'].contains(k)) ||
          p['contractVersion'] != 1 ||
          p['database'] is! String ||
          (p['client_token'] != null && p['client_token'] != token)) {
        return denied(request);
      }
      final database = p['database'] as String;
      if (database.isEmpty || database.length > 500 || RegExp(r'[;{}\r\n\x00]').hasMatch(database)) {
        return denied(request);
      }
      final policy = (await tokens.validate(token)).getOrThrow();
      final config = (await configs.resolveActiveConfig()).getOrThrow();
      if (policy.isRevoked ||
          policy.agentId != context.agentId ||
          config.agentId != context.agentId ||
          policy.payloadDatabaseConstraint != database.trim().toLowerCase()) {
        return denied(request);
      }
      final proof = (await probe.inspect(config, database)).getOrThrow();
      final current = (await tokens.validate(token)).getOrThrow();
      final currentConfig = (await configs.resolveActiveConfig()).getOrThrow();
      if (current.isRevoked ||
          current.agentId != context.agentId ||
          current.payloadDatabaseConstraint != database.trim().toLowerCase() ||
          currentConfig.id != config.id ||
          currentConfig.updatedAt != config.updatedAt ||
          currentConfig.connectionString != config.connectionString ||
          currentConfig.host != config.host ||
          currentConfig.port != config.port ||
          currentConfig.driverName != config.driverName ||
          currentConfig.odbcDriverName != config.odbcDriverName ||
          currentConfig.username != config.username ||
          currentConfig.password != config.password ||
          currentConfig.databaseName != config.databaseName ||
          currentConfig.agentId != config.agentId) {
        return denied(request);
      }
      return RpcResponse.success(id: request.id, result: proof.toJson());
    } on Object {
      return denied(request);
    }
  }

  RpcResponse denied(RpcRequest request) => RpcResponse.error(
    id: request.id,
    error: const RpcError(
      code: -32000,
      message: 'Source discovery unavailable or refused.',
      data: {'failure_code': 'SOURCE_DISCOVERY_UNAVAILABLE', 'retryable': false},
    ),
  );
}
