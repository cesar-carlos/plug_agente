import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/agent_action_developer_data7_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_preflight_metadata.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_config_locator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:plug_agente/infrastructure/actions/developer_executor_command_builder.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';
import 'package:result_dart/result_dart.dart';

class DeveloperData7ResolvedDefinition {
  const DeveloperData7ResolvedDefinition({
    required this.normalizedConfig,
    required this.executorPath,
    required this.projectPath,
    required this.data7ConfigPath,
    required this.connection,
    required this.catalogConnectionCount,
    required this.usedDefaultConfigPath,
    required this.workingDirectory,
  });

  final DeveloperActionConfig normalizedConfig;
  final AgentActionValidatedPath executorPath;
  final AgentActionValidatedPath projectPath;
  final AgentActionValidatedPath data7ConfigPath;
  final DeveloperData7ConnectionInfo connection;
  final int catalogConnectionCount;
  final bool usedDefaultConfigPath;
  final String workingDirectory;
}

class DeveloperData7PreparedExecution {
  const DeveloperData7PreparedExecution({
    required this.definition,
    required this.command,
    required this.redactedDiagnostics,
  });

  final DeveloperData7ResolvedDefinition definition;
  final DeveloperExecutorCommand command;
  final Map<String, Object?> redactedDiagnostics;
}

class DeveloperData7DefinitionResolver {
  DeveloperData7DefinitionResolver({
    ActionPathValidator? pathValidator,
    DeveloperData7ConfigLocator? configLocator,
    DeveloperData7ConnectionCatalog? connectionCatalog,
    DeveloperExecutorCommandBuilder commandBuilder = const DeveloperExecutorCommandBuilder(),
    DateTime Function()? now,
  }) : _pathValidator = pathValidator ?? ActionPathValidator(),
       _configLocator = configLocator ?? DeveloperData7ConfigLocator(pathValidator: pathValidator),
       _connectionCatalog = connectionCatalog ?? DeveloperData7ConnectionCatalog(),
       _commandBuilder = commandBuilder,
       _now = now ?? DateTime.now;

  final ActionPathValidator _pathValidator;
  final DeveloperData7ConfigLocator _configLocator;
  final DeveloperData7ConnectionCatalog _connectionCatalog;
  final DeveloperExecutorCommandBuilder _commandBuilder;
  final DateTime Function() _now;

  Future<Result<DeveloperData7ResolvedDefinition>> resolveDefinition({
    required AgentActionDefinition definition,
    String phase = 'definition_validation',
    bool compareSavedSnapshots = false,
  }) async {
    final configResult = _validateDeveloperConfig(definition, phase: phase);
    if (configResult.isError()) {
      return Failure(configResult.exceptionOrNull()!);
    }
    final config = configResult.getOrThrow();

    final connectionIdResult = _validateConnectionId(
      actionId: definition.id,
      connectionId: config.connectionId,
      phase: phase,
    );
    if (connectionIdResult.isError()) {
      return Failure(connectionIdResult.exceptionOrNull()!);
    }

    final executorValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'executorPath',
      path: config.executorPath,
      allowedExtensions: const {'.exe'},
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      phase: phase,
      requireLaunchAccess: WindowsExecutableLaunchAccessChecker.shouldValidateLaunchAccessForPath(
        phase: phase,
        path: config.executorPath.displayPath,
      ),
      invalidPathReason: AgentActionDeveloperData7Constants.developerExecutorInvalidPathReason,
      notFoundReason: AgentActionDeveloperData7Constants.developerExecutorNotFoundReason,
      extensionNotAllowedReason: AgentActionDeveloperData7Constants.developerExecutorExtensionNotAllowedReason,
      notAllowedReason: AgentActionDeveloperData7Constants.developerExecutorNotAllowedReason,
      invalidPathUserMessage: 'Informe um caminho valido para o Executor.exe.',
      notFoundUserMessage: 'Arquivo Executor.exe nao encontrado. Verifique o caminho informado.',
      extensionNotAllowedUserMessage: 'Selecione o arquivo Executor.exe correto para esta acao.',
      notAllowedUserMessage: 'O arquivo Executor.exe esta fora dos diretorios permitidos para esta acao.',
    );
    if (executorValidation.isError()) {
      return Failure(executorValidation.exceptionOrNull()!);
    }
    final executorPath = executorValidation.getOrThrow().path!;

    final executorFileNameResult = _validateExpectedFileName(
      actionId: definition.id,
      phase: phase,
      field: 'executorPath',
      path: executorPath.originalPath,
      expectedFileName: 'executor.exe',
      reason: AgentActionDeveloperData7Constants.developerExecutorFileNameInvalidReason,
      code: 'DEVELOPER_EXECUTOR_FILE_NAME_INVALID',
      userMessage: 'Selecione o arquivo Executor.exe correto para esta acao.',
    );
    if (executorFileNameResult.isError()) {
      return Failure(executorFileNameResult.exceptionOrNull()!);
    }

    final projectValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'projectPath',
      path: config.projectPath,
      allowedExtensions: const {'.7proj'},
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      phase: phase,
      invalidPathReason: AgentActionDeveloperData7Constants.developerProjectInvalidPathReason,
      notFoundReason: AgentActionDeveloperData7Constants.developerProjectNotFoundReason,
      extensionNotAllowedReason: AgentActionDeveloperData7Constants.developerProjectExtensionNotAllowedReason,
      notAllowedReason: AgentActionDeveloperData7Constants.developerProjectNotAllowedReason,
      invalidPathUserMessage: 'Informe um caminho valido para o arquivo .7Proj.',
      notFoundUserMessage: 'Arquivo .7Proj nao encontrado. Verifique se ele foi removido ou renomeado.',
      extensionNotAllowedUserMessage: 'Selecione um arquivo .7Proj valido para esta acao.',
      notAllowedUserMessage: 'O arquivo .7Proj esta fora dos diretorios permitidos para esta acao.',
    );
    if (projectValidation.isError()) {
      return Failure(projectValidation.exceptionOrNull()!);
    }
    final projectPath = projectValidation.getOrThrow().path!;

    final configPathResult = await _configLocator.locate(
      actionId: definition.id,
      configuredPath: config.data7ConfigPath,
      pathPolicy: definition.policies.path,
      phase: phase,
    );
    if (configPathResult.isError()) {
      return Failure(configPathResult.exceptionOrNull()!);
    }
    final locatedConfigPath = configPathResult.getOrThrow();

    final catalogResult = await _connectionCatalog.load(
      actionId: definition.id,
      configPath: locatedConfigPath.path.canonicalPath,
      phase: phase,
    );
    if (catalogResult.isError()) {
      return Failure(catalogResult.exceptionOrNull()!);
    }
    final catalog = catalogResult.getOrThrow();
    final connection = catalog.findById(config.connectionId);
    if (connection == null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 connection id was not found in the configuration file.',
          code: 'DEVELOPER_DATA7_CONNECTION_NOT_FOUND',
          context: {
            'action_id': definition.id,
            'field': 'connectionId',
            'phase': phase,
            'path': locatedConfigPath.path.canonicalPath,
            'connection_id': config.connectionId,
            'reason': AgentActionDeveloperData7Constants.developerData7ConnectionNotFoundReason,
            'user_message':
                'A conexao selecionada nao existe mais no arquivo Data7.Config. Recarregue e salve a acao novamente.',
          },
        ),
      );
    }

    final connectionSnapshotResult = _validateConnectionSnapshot(
      actionId: definition.id,
      config: config,
      connection: connection,
      phase: phase,
    );
    if (connectionSnapshotResult.isError()) {
      return Failure(connectionSnapshotResult.exceptionOrNull()!);
    }

    if (compareSavedSnapshots) {
      final executorSnapshotResult = _pathValidator.guardPathSnapshot(
        actionId: definition.id,
        field: 'executorPath',
        savedReference: config.executorPath,
        currentPath: executorPath,
        phase: phase,
      );
      if (executorSnapshotResult.isError()) {
        return Failure(executorSnapshotResult.exceptionOrNull()!);
      }

      final projectSnapshotResult = _pathValidator.guardPathSnapshot(
        actionId: definition.id,
        field: 'projectPath',
        savedReference: config.projectPath,
        currentPath: projectPath,
        phase: phase,
      );
      if (projectSnapshotResult.isError()) {
        return Failure(projectSnapshotResult.exceptionOrNull()!);
      }

      final data7ConfigSnapshotResult = _pathValidator.guardPathSnapshot(
        actionId: definition.id,
        field: 'data7ConfigPath',
        savedReference: config.data7ConfigPath,
        currentPath: locatedConfigPath.path,
        phase: phase,
      );
      if (data7ConfigSnapshotResult.isError()) {
        return Failure(data7ConfigSnapshotResult.exceptionOrNull()!);
      }
    }

    final normalizedConfig = DeveloperActionConfig.data7Executor(
      executorPath: _toPathReference(
        original: config.executorPath,
        validatedPath: executorPath,
      ),
      projectPath: _toPathReference(
        original: config.projectPath,
        validatedPath: projectPath,
      ),
      data7ConfigPath: _toPathReference(
        original: config.data7ConfigPath,
        validatedPath: locatedConfigPath.path,
      ),
      connectionId: connection.id,
      connectionLabel: connection.label,
      connectionSnapshotHash: connection.snapshotHash,
    );

    return Success(
      DeveloperData7ResolvedDefinition(
        normalizedConfig: normalizedConfig,
        executorPath: executorPath,
        projectPath: projectPath,
        data7ConfigPath: locatedConfigPath.path,
        connection: connection,
        catalogConnectionCount: catalog.connections.length,
        usedDefaultConfigPath: locatedConfigPath.usedDefaultLocation,
        workingDirectory: p.windows.dirname(executorPath.canonicalPath),
      ),
    );
  }

  Future<Result<DeveloperData7PreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final runtimeOverridesResult = _validateRuntimeOverrides(
      actionId: definition.id,
      request: request,
      phase: 'execution_preflight',
    );
    if (runtimeOverridesResult.isError()) {
      return Failure(runtimeOverridesResult.exceptionOrNull()!);
    }

    final resolvedResult = await resolveDefinition(
      definition: definition,
      phase: 'execution_preflight',
      compareSavedSnapshots: true,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();

    final command = _commandBuilder.build(
      executorPath: resolved.executorPath.canonicalPath,
      projectPath: resolved.projectPath.canonicalPath,
      connectionId: resolved.connection.id,
      workingDirectory: resolved.workingDirectory,
    );

    return Success(
      DeveloperData7PreparedExecution(
        definition: resolved,
        command: command,
        redactedDiagnostics: {
          'engine': resolved.normalizedConfig.engine.name,
          'connection_label': resolved.connection.label,
          'catalog_connection_count': resolved.catalogConnectionCount,
          'used_default_config_path': resolved.usedDefaultConfigPath,
          'executor_path': ActionPathPreflightMetadata.forValidatedPath(resolved.executorPath),
          'project_path': ActionPathPreflightMetadata.forValidatedPath(resolved.projectPath),
          'data7_config_path': ActionPathPreflightMetadata.forValidatedPath(resolved.data7ConfigPath),
        },
      ),
    );
  }

  Result<DeveloperActionConfig> _validateDeveloperConfig(
    AgentActionDefinition definition, {
    required String phase,
  }) {
    final config = definition.config;
    if (config is! DeveloperActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.developer.name,
            'phase': phase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao developer e invalida.',
          },
        ),
      );
    }
    if (config.engine != AgentActionDeveloperEngine.data7Executor) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer action engine is not supported.',
          code: 'DEVELOPER_ENGINE_NOT_SUPPORTED',
          context: {
            'action_id': definition.id,
            'field': 'engine',
            'phase': phase,
            'engine': config.engine.name,
            'reason': AgentActionDeveloperData7Constants.developerEngineNotSupportedReason,
            'user_message': 'O engine developer informado ainda nao e suportado.',
          },
        ),
      );
    }

    return Success(config);
  }

  Result<void> _validateConnectionId({
    required String actionId,
    required String connectionId,
    required String phase,
  }) {
    final trimmed = connectionId.trim();
    if (trimmed.isEmpty || !_guidPattern.hasMatch(trimmed)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 connection id must be a GUID.',
          code: 'DEVELOPER_DATA7_CONNECTION_ID_INVALID',
          context: {
            'action_id': actionId,
            'field': 'connectionId',
            'phase': phase,
            'reason': AgentActionDeveloperData7Constants.developerData7ConnectionIdInvalidReason,
            'user_message': 'Informe um ID de conexao Data7 valido para esta acao.',
          },
        ),
      );
    }

    return const Success(unit);
  }

  Result<void> _validateConnectionSnapshot({
    required String actionId,
    required DeveloperActionConfig config,
    required DeveloperData7ConnectionInfo connection,
    required String phase,
  }) {
    final savedSnapshotHash = config.connectionSnapshotHash?.trim();
    if (savedSnapshotHash == null || savedSnapshotHash.isEmpty) {
      return const Success(unit);
    }
    if (savedSnapshotHash == connection.snapshotHash) {
      return const Success(unit);
    }

    return Failure(
      ActionValidationFailure.withContext(
        message: 'Developer Data7 connection snapshot changed after the action was saved.',
        code: 'DEVELOPER_DATA7_CONNECTION_SNAPSHOT_MISMATCH',
        context: {
          'action_id': actionId,
          'field': 'connectionId',
          'phase': phase,
          'reason': AgentActionDeveloperData7Constants.developerData7ConnectionChangedAfterSaveReason,
          'connection_id': connection.id,
          'saved_snapshot_hash': savedSnapshotHash,
          'current_snapshot_hash': connection.snapshotHash,
          'user_message':
              'A conexao Data7 mudou desde a ultima validacao. Revise a configuracao e salve a acao novamente.',
        },
      ),
    );
  }

  Result<void> _validateExpectedFileName({
    required String actionId,
    required String phase,
    required String field,
    required String path,
    required String expectedFileName,
    required String reason,
    required String code,
    required String userMessage,
  }) {
    final normalizedPath = path.replaceAll(r'\', '/');
    final lastSeparator = normalizedPath.lastIndexOf('/');
    final fileName = lastSeparator >= 0 ? normalizedPath.substring(lastSeparator + 1) : normalizedPath;
    if (fileName.toLowerCase() == expectedFileName.toLowerCase()) {
      return const Success(unit);
    }

    return Failure(
      ActionValidationFailure.withContext(
        message: 'Developer action file name is invalid for the selected field.',
        code: code,
        context: {
          'action_id': actionId,
          'field': field,
          'phase': phase,
          'path': path,
          'expected_file_name': expectedFileName,
          'reason': reason,
          'user_message': userMessage,
        },
      ),
    );
  }

  Result<void> _validateRuntimeOverrides({
    required String actionId,
    required AgentActionExecutionRequest request,
    required String phase,
  }) {
    if (request.contextPath != null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 actions do not accept context file overrides.',
          code: 'DEVELOPER_DATA7_CONTEXT_NOT_SUPPORTED',
          context: {
            'action_id': actionId,
            'field': 'contextPath',
            'phase': phase,
            'reason': AgentActionDeveloperData7Constants.developerData7ContextNotSupportedReason,
            'user_message': 'A acao developer/Data7 nao aceita arquivo de contexto nesta fase.',
          },
        ),
      );
    }
    if (request.runtimeParameters.isNotEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 actions do not accept runtime parameter overrides.',
          code: 'DEVELOPER_DATA7_RUNTIME_PARAMETERS_NOT_SUPPORTED',
          context: {
            'action_id': actionId,
            'field': 'runtimeParameters',
            'phase': phase,
            'reason': AgentActionDeveloperData7Constants.developerData7RuntimeParametersNotSupportedReason,
            'user_message': 'A acao developer/Data7 nao aceita parametros runtime ad-hoc nesta fase.',
          },
        ),
      );
    }
    return const Success(unit);
  }

  AgentActionPathReference _toPathReference({
    required AgentActionPathReference original,
    required AgentActionValidatedPath validatedPath,
  }) {
    return AgentActionPathReference(
      originalPath: validatedPath.originalPath,
      canonicalPath: validatedPath.canonicalPath,
      existsAtValidation: true,
      validatedAt: _now().toUtc(),
      validationHash: validatedPath.contentHash ?? original.validationHash,
      pathChangePolicy: original.pathChangePolicy,
    );
  }

  static final RegExp _guidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
