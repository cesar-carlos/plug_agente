import 'package:drift/drift.dart';

part 'action_io_journal_database.g.dart';

class ActionIoSessions extends Table {
  TextColumn get executionId => text()();
  TextColumn get installationId => text()();
  TextColumn get agentId => text()();
  TextColumn get clientId => text()();
  TextColumn get actionId => text()();
  TextColumn get idempotencyKey => text()();
  TextColumn get fingerprint => text()();
  TextColumn get triggerId => text()();
  TextColumn get actionType => text().nullable()();
  TextColumn get definitionHash => text()();
  TextColumn get processState => text()();
  TextColumn get stdinState => text()();
  TextColumn get captureState => text()();
  IntColumn get nextInputSequence => integer().withDefault(const Constant(0))();
  IntColumn get nextEventSequence => integer().withDefault(const Constant(1))();
  IntColumn get admittedInputBytes => integer().withDefault(const Constant(0))();
  IntColumn get stdoutBytes => integer().withDefault(const Constant(0))();
  IntColumn get stderrBytes => integer().withDefault(const Constant(0))();
  IntColumn get queuedInputBytes => integer().withDefault(const Constant(0))();
  IntColumn get queuedInputMessages => integer().withDefault(const Constant(0))();
  IntColumn get exitCode => integer().nullable()();
  TextColumn get failureCode => text().nullable()();
  TextColumn get diagnosticId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get terminalAt => dateTime().nullable()();
  DateTimeColumn get outputExpiresAt => dateTime().nullable()();
  DateTimeColumn get dedupeExpiresAt => dateTime().nullable()();
  BoolColumn get outputExpired => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {executionId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {installationId, agentId, clientId, actionId, idempotencyKey},
  ];
}

/// One nonce registry for all encrypted payloads, including across message/stream types.
class ActionIoPayloads extends Table {
  TextColumn get payloadId => text()();
  TextColumn get executionId => text().references(ActionIoSessions, #executionId)();
  TextColumn get keyId => text()();
  BlobColumn get nonce => blob()();
  BlobColumn get ciphertext => blob()();
  BlobColumn get authenticationTag => blob()();
  BlobColumn get authenticatedContext => blob()();
  IntColumn get plaintextBytes => integer()();

  @override
  Set<Column<Object>> get primaryKey => {payloadId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {keyId, nonce},
  ];
}

class ActionIoMessages extends Table {
  TextColumn get executionId => text().references(ActionIoSessions, #executionId)();
  TextColumn get messageId => text()();
  IntColumn get sequence => integer()();
  TextColumn get fingerprint => text()();
  BoolColumn get closesInput => boolean()();
  TextColumn get deliveryState => text()();
  IntColumn get confirmedBytes => integer().nullable()();
  IntColumn get inputBytes => integer()();
  TextColumn get payloadId => text().nullable().references(ActionIoPayloads, #payloadId)();
  TextColumn get failureCode => text().nullable()();
  DateTimeColumn get admittedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {executionId, messageId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {executionId, sequence},
  ];
}

class ActionIoEvents extends Table {
  TextColumn get executionId => text().references(ActionIoSessions, #executionId)();
  IntColumn get sequence => integer()();
  TextColumn get eventType => text()();
  TextColumn get stream => text().nullable()();
  IntColumn get byteOffset => integer().nullable()();
  TextColumn get payloadId => text().nullable().references(ActionIoPayloads, #payloadId)();
  IntColumn get exitCode => integer().nullable()();
  BoolColumn get outputComplete => boolean().nullable()();
  TextColumn get failureCode => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {executionId, sequence};
}

@DriftDatabase(tables: [ActionIoSessions, ActionIoPayloads, ActionIoMessages, ActionIoEvents])
class ActionIoJournalDatabase extends _$ActionIoJournalDatabase {
  ActionIoJournalDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await migrator.addColumn(actionIoSessions, actionIoSessions.actionType);
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = FULL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}
