import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:result_dart/result_dart.dart';

/// Adapts an [IAgentConfigRepository] to the [IQueryConfigSource] port.
///
/// Used when the ODBC gateway runs without an active-config resolver (legacy
/// and test wiring): an explicit id resolves by id metadata, otherwise the
/// current config metadata is used.
final class AgentConfigQueryConfigSource implements IQueryConfigSource {
  AgentConfigQueryConfigSource(this._repository);

  final IAgentConfigRepository _repository;

  @override
  Future<Result<Config>> resolveConfigForQuery(String? configId) {
    final normalized = configId?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return _repository.getByIdMetadata(normalized);
    }
    return _repository.getCurrentConfigMetadata();
  }

  @override
  Future<Result<Config>> resolveActiveConfig() {
    return _repository.getCurrentConfigMetadata();
  }
}
