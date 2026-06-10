import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_developer_data7_connection_gateway.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_config_locator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:result_dart/result_dart.dart';

class DeveloperData7ConnectionGateway implements IDeveloperData7ConnectionGateway {
  DeveloperData7ConnectionGateway({
    required DeveloperData7ConfigLocator configLocator,
    required DeveloperData7ConnectionCatalog connectionCatalog,
  }) : _configLocator = configLocator,
       _connectionCatalog = connectionCatalog;

  final DeveloperData7ConfigLocator _configLocator;
  final DeveloperData7ConnectionCatalog _connectionCatalog;

  @override
  Future<Result<DeveloperData7ConnectionLookupResult>> listConnections(
    DeveloperData7ConnectionLookupRequest request,
  ) async {
    final locatedPathResult = await _configLocator.locate(
      actionId: request.actionId,
      configuredPath: request.data7ConfigPath,
      pathPolicy: request.pathPolicy,
      phase: 'definition_validation',
      enforceWorkingDirectoryAllowlist: false,
    );
    if (locatedPathResult.isError()) {
      return Failure(locatedPathResult.exceptionOrNull()!);
    }
    final locatedPath = locatedPathResult.getOrThrow();

    final catalogResult = await _connectionCatalog.load(
      actionId: request.actionId,
      configPath: locatedPath.path.canonicalPath,
      phase: 'definition_validation',
    );
    if (catalogResult.isError()) {
      return Failure(catalogResult.exceptionOrNull()!);
    }
    final catalog = catalogResult.getOrThrow();

    return Success(
      DeveloperData7ConnectionLookupResult(
        resolvedConfigPath: AgentActionPathReference(
          originalPath: locatedPath.path.originalPath,
          canonicalPath: locatedPath.path.canonicalPath,
          existsAtValidation: true,
        ),
        usedDefaultLocation: locatedPath.usedDefaultLocation,
        connections: catalog.connections
            .map(
              (connection) => DeveloperData7ConnectionOption(
                id: connection.id,
                label: connection.label,
                snapshotHash: connection.snapshotHash,
              ),
            )
            .toList(growable: false),
        selectedConnectionId: request.selectedConnectionId,
      ),
    );
  }
}
