import 'package:drift/drift.dart';

@DataClassName('ConfigData')
class ConfigTable extends Table {
  TextColumn get id => text()();
  TextColumn get serverUrl => text().withDefault(const Constant('https://api.example.com'))();
  TextColumn get agentId => text().withDefault(const Constant(''))();
  TextColumn get authToken => text().nullable()();
  TextColumn get refreshToken => text().nullable()();
  TextColumn get authUsername => text().nullable()();
  TextColumn get authPassword => text().nullable()();
  TextColumn get driverName => text()();
  TextColumn get odbcDriverName => text().withDefault(const Constant(''))();
  TextColumn get connectionString => text()();
  TextColumn get username => text()();
  TextColumn get password => text().nullable()();
  TextColumn get databaseName => text()();
  TextColumn get host => text()();
  IntColumn get port => integer()();
  TextColumn get nome => text().withDefault(const Constant(''))();
  TextColumn get nomeFantasia => text().withDefault(const Constant(''))();
  TextColumn get cnaeCnpjCpf => text().withDefault(const Constant(''))();
  TextColumn get telefone => text().withDefault(const Constant(''))();
  TextColumn get celular => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get endereco => text().withDefault(const Constant(''))();
  TextColumn get numeroEndereco => text().withDefault(const Constant(''))();
  TextColumn get bairro => text().withDefault(const Constant(''))();
  TextColumn get cep => text().withDefault(const Constant(''))();
  TextColumn get nomeMunicipio => text().withDefault(const Constant(''))();
  TextColumn get ufMunicipio => text().withDefault(const Constant(''))();
  TextColumn get observacao => text().withDefault(const Constant(''))();
  IntColumn get hubProfileVersion => integer().nullable()();
  TextColumn get hubProfileUpdatedAt => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ClientTokenCacheData')
class ClientTokenCacheTable extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text()();
  // User-defined label for easy identification; empty string when not set.
  TextColumn get name => text().withDefault(const Constant(''))();
  BoolColumn get isRevoked => boolean().withDefault(const Constant(false))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get agentId => text().nullable()();
  TextColumn get tokenValue => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  BoolColumn get allTables => boolean().withDefault(const Constant(false))();
  BoolColumn get allViews => boolean().withDefault(const Constant(false))();
  BoolColumn get allPermissions => boolean().withDefault(const Constant(false))();
  TextColumn get globalPermissionsJson => text().withDefault(
    const Constant('{"read":false,"update":false,"delete":false,"ddl":false}'),
  )();
  TextColumn get rulesJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get syncedAt => dateTime()();
  TextColumn get tokenHash => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {tokenHash},
  ];
}

@DataClassName('AgentActionDefinitionData')
class AgentActionDefinitionTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get type => text()();
  TextColumn get state => text()();
  TextColumn get configJson => text()();
  TextColumn get policiesJson => text()();
  IntColumn get definitionVersion => integer().withDefault(const Constant(1))();
  TextColumn get definitionSnapshotHash => text().nullable()();
  TextColumn get lastPreflightSnapshotHash => text().nullable()();
  DateTimeColumn get lastPreflightValidatedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AgentActionTriggerData')
class AgentActionTriggerTable extends Table {
  TextColumn get id => text()();
  TextColumn get actionId =>
      text().references(AgentActionDefinitionTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()();
  TextColumn get name => text().nullable()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get scheduleJson => text()();
  DateTimeColumn get lastScheduledAt => dateTime().nullable()();
  DateTimeColumn get lastRunAt => dateTime().nullable()();
  DateTimeColumn get nextRunAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AgentActionExecutionData')
class AgentActionExecutionTable extends Table {
  TextColumn get id => text()();
  TextColumn get actionId => text()();
  TextColumn get actionType => text()();
  TextColumn get status => text()();
  DateTimeColumn get requestedAt => dateTime()();
  TextColumn get source => text()();
  TextColumn get idempotencyKey => text().nullable()();
  TextColumn get requestedBy => text().nullable()();
  TextColumn get traceId => text().nullable()();
  TextColumn get runtimeInstanceId => text().nullable()();
  TextColumn get runtimeSessionId => text().nullable()();
  TextColumn get triggerId => text().nullable()();
  TextColumn get triggerType => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  DateTimeColumn get triggeredAt => dateTime().nullable()();
  DateTimeColumn get queueStartedAt => dateTime().nullable()();
  DateTimeColumn get processStartedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  DateTimeColumn get timeoutAt => dateTime().nullable()();
  IntColumn get pid => integer().nullable()();
  IntColumn get exitCode => integer().nullable()();
  TextColumn get processExecutable => text().nullable()();
  IntColumn get processArgumentCount => integer().nullable()();
  TextColumn get processCommandPreview => text().nullable()();
  TextColumn get stdoutText => text().nullable()();
  TextColumn get stderrText => text().nullable()();
  BoolColumn get stdoutTruncated => boolean().withDefault(const Constant(false))();
  BoolColumn get stderrTruncated => boolean().withDefault(const Constant(false))();
  BoolColumn get stdoutStoredInChunks => boolean().withDefault(const Constant(false))();
  BoolColumn get stderrStoredInChunks => boolean().withDefault(const Constant(false))();
  TextColumn get definitionSnapshotHash => text().nullable()();
  TextColumn get contextHash => text().nullable()();
  BoolColumn get redactionApplied => boolean().withDefault(const Constant(false))();
  TextColumn get failureCode => text().nullable()();
  TextColumn get failurePhase => text().nullable()();
  TextColumn get failureMessage => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RpcIdempotencyCacheData')
class RpcIdempotencyCacheTable extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get responseJson => text()();
  TextColumn get requestFingerprint => text().nullable()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

@DataClassName('AgentActionCapturedOutputChunkData')
class AgentActionCapturedOutputChunkTable extends Table {
  TextColumn get executionId =>
      text().references(AgentActionExecutionTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get stream => text()();
  IntColumn get chunkIndex => integer()();
  IntColumn get utf8Offset => integer()();
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {executionId, stream, chunkIndex};
}

@DataClassName('AgentActionRemoteAuditData')
class AgentActionRemoteAuditTable extends Table {
  TextColumn get id => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get rpcMethod => text()();
  TextColumn get actionId => text().nullable()();
  TextColumn get executionId => text().nullable()();
  TextColumn get traceId => text().nullable()();
  TextColumn get requestedBy => text().nullable()();
  TextColumn get outcome => text()();
  TextColumn get reasonCode => text().nullable()();
  IntColumn get rpcErrorCode => integer().nullable()();
  BoolColumn get credentialPresent => boolean().withDefault(const Constant(false))();
  TextColumn get clientId => text().nullable()();
  TextColumn get tokenJti => text().nullable()();
  TextColumn get runtimeInstanceId => text().nullable()();
  TextColumn get runtimeSessionId => text().nullable()();
  TextColumn get idempotencyKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// AgentConfigDataSource interface is defined in agent_config_drift_database.dart
// where ConfigData (generated by Drift) is accessible via the .g.dart file
