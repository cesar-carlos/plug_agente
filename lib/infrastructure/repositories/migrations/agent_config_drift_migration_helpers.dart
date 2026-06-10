part of '../agent_config_drift_database.dart';

@visibleForTesting
IOdbcCredentialSecretStore Function()? migrationOdbcCredentialSecretStoreFactory;

mixin _AppDatabaseMigrationHelpers on _$AppDatabase {
  Future<void> migrateRemainingOdbcPasswordsBeforeColumnDrop() async {
    final columns = await readConfigTableColumnNames();
    if (!columns.contains('password')) {
      return;
    }

    final credentialSecretStore =
        migrationOdbcCredentialSecretStoreFactory?.call() ??
        FlutterSecureOdbcCredentialSecretStore();
    if (!credentialSecretStore.isAvailable) {
      return;
    }

    final rows = await customSelect(
      'SELECT id, password, connection_string FROM config_table',
      readsFrom: {configTable},
    ).get();

    for (final row in rows) {
      final configId = row.read<String>('id');
      final columnPassword = _normalizeMigrationSecret(row.readNullable<String>('password'));
      final connectionString = row.read<String>('connection_string');
      final embeddedPassword = OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
        connectionString,
      );
      final legacyPassword = columnPassword ?? embeddedPassword;
      if (legacyPassword == null) {
        continue;
      }

      final storedSecrets = await credentialSecretStore.readSecrets(configId);
      if (_normalizeMigrationSecret(storedSecrets.password) == null) {
        await credentialSecretStore.saveSecrets(
          configId,
          OdbcCredentialSecrets(password: legacyPassword),
        );
      }

      final redactedConnectionString = OdbcConnectionStringSecrets.stripPasswordFromConnectionString(
        connectionString,
      );
      if (redactedConnectionString != connectionString) {
        await (update(configTable)..where((tbl) => tbl.id.equals(configId))).write(
          ConfigTableCompanion(
            connectionString: Value<String>(redactedConnectionString),
          ),
        );
      }
    }
  }

  String? _normalizeMigrationSecret(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> addAgentProfileColumnsIfMissing(Migrator m) async {
    final existing = await readConfigTableColumnNames();
    final profileColumns = <GeneratedColumn<Object>>[
      configTable.nome as GeneratedColumn<Object>,
      configTable.nomeFantasia as GeneratedColumn<Object>,
      configTable.cnaeCnpjCpf as GeneratedColumn<Object>,
      configTable.telefone as GeneratedColumn<Object>,
      configTable.celular as GeneratedColumn<Object>,
      configTable.email as GeneratedColumn<Object>,
      configTable.endereco as GeneratedColumn<Object>,
      configTable.numeroEndereco as GeneratedColumn<Object>,
      configTable.bairro as GeneratedColumn<Object>,
      configTable.cep as GeneratedColumn<Object>,
      configTable.nomeMunicipio as GeneratedColumn<Object>,
      configTable.ufMunicipio as GeneratedColumn<Object>,
      configTable.observacao as GeneratedColumn<Object>,
    ];
    for (final column in profileColumns) {
      final sqlName = column.name;
      if (existing.contains(sqlName)) {
        continue;
      }
      await m.addColumn(configTable, column);
      existing.add(sqlName);
    }
  }

  Future<Set<String>> readConfigTableColumnNames() async {
    final rows = await customSelect(
      'PRAGMA table_info("config_table")',
      readsFrom: {configTable},
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<void> addClientTokenNameColumnIfMissing(Migrator m) async {
    final existing = await readClientTokenTableColumnNames();
    final sqlName = clientTokenCacheTable.name.name;
    if (existing.contains(sqlName)) {
      return;
    }
    await m.addColumn(clientTokenCacheTable, clientTokenCacheTable.name);
  }

  Future<void> addClientTokenGlobalPermissionsColumnIfMissing(
    Migrator m,
  ) async {
    final existing = await readClientTokenTableColumnNames();
    final sqlName = clientTokenCacheTable.globalPermissionsJson.name;
    if (existing.contains(sqlName)) {
      return;
    }
    await m.addColumn(
      clientTokenCacheTable,
      clientTokenCacheTable.globalPermissionsJson,
    );
  }

  Future<Set<String>> readClientTokenTableColumnNames() async {
    final rows = await customSelect(
      'PRAGMA table_info("client_token_cache_table")',
      readsFrom: {clientTokenCacheTable},
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<void> addAgentActionExecutionTriggerColumnsIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionExecutionTableColumnNames();
    final triggerColumns = <GeneratedColumn<Object>>[
      agentActionExecutionTable.triggerId as GeneratedColumn<Object>,
      agentActionExecutionTable.triggerType as GeneratedColumn<Object>,
      agentActionExecutionTable.scheduledAt as GeneratedColumn<Object>,
      agentActionExecutionTable.triggeredAt as GeneratedColumn<Object>,
    ];
    for (final column in triggerColumns) {
      final sqlName = column.name;
      if (existing.contains(sqlName)) {
        continue;
      }
      await m.addColumn(agentActionExecutionTable, column);
      existing.add(sqlName);
    }
  }

  Future<void> addAgentActionExecutionProcessIdentityColumnsIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionExecutionTableColumnNames();
    final identityColumns = <GeneratedColumn<Object>>[
      agentActionExecutionTable.processExecutable as GeneratedColumn<Object>,
      agentActionExecutionTable.processArgumentCount as GeneratedColumn<Object>,
      agentActionExecutionTable.processCommandPreview as GeneratedColumn<Object>,
    ];
    for (final column in identityColumns) {
      final sqlName = column.name;
      if (existing.contains(sqlName)) {
        continue;
      }
      await m.addColumn(agentActionExecutionTable, column);
      existing.add(sqlName);
    }
  }

  Future<void> addAgentActionExecutionFailurePhaseColumnIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionExecutionTableColumnNames();
    final failurePhaseColumn =
        agentActionExecutionTable.failurePhase as GeneratedColumn<Object>;
    final sqlName = failurePhaseColumn.name;
    if (!existing.contains(sqlName)) {
      await m.addColumn(agentActionExecutionTable, failurePhaseColumn);
    }
  }

  Future<void>
  addAgentActionDefinitionLastPreflightSnapshotHashColumnIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionDefinitionTableColumnNames();
    final column = agentActionDefinitionTable.lastPreflightSnapshotHash;
    final sqlName = column.name;
    if (!existing.contains(sqlName)) {
      await m.addColumn(agentActionDefinitionTable, column);
    }
  }

  Future<void> addAgentActionDefinitionLastPreflightValidatedAtColumnIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionDefinitionTableColumnNames();
    final column = agentActionDefinitionTable.lastPreflightValidatedAt;
    final sqlName = column.name;
    if (!existing.contains(sqlName)) {
      await m.addColumn(agentActionDefinitionTable, column);
    }
  }

  Future<Set<String>> readAgentActionDefinitionTableColumnNames() async {
    final rows = await customSelect(
      'PRAGMA table_info("agent_action_definition_table")',
      readsFrom: {agentActionDefinitionTable},
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<void> addAgentActionExecutionRuntimeIdentityColumnsIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionExecutionTableColumnNames();
    final columns = <GeneratedColumn<Object>>[
      agentActionExecutionTable.runtimeInstanceId as GeneratedColumn<Object>,
      agentActionExecutionTable.runtimeSessionId as GeneratedColumn<Object>,
    ];
    for (final column in columns) {
      final sqlName = column.name;
      if (existing.contains(sqlName)) {
        continue;
      }
      await m.addColumn(agentActionExecutionTable, column);
      existing.add(sqlName);
    }
  }

  Future<Set<String>> readAgentActionExecutionTableColumnNames() async {
    final rows = await customSelect(
      'PRAGMA table_info("agent_action_execution_table")',
      readsFrom: {agentActionExecutionTable},
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<void> addAgentActionExecutionCapturedOutputChunkColumnsIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionExecutionTableColumnNames();
    final columns = <GeneratedColumn<Object>>[
      agentActionExecutionTable.stdoutStoredInChunks as GeneratedColumn<Object>,
      agentActionExecutionTable.stderrStoredInChunks as GeneratedColumn<Object>,
    ];
    for (final column in columns) {
      final sqlName = column.name;
      if (existing.contains(sqlName)) {
        continue;
      }
      await m.addColumn(agentActionExecutionTable, column);
      existing.add(sqlName);
    }
  }

  Future<Set<String>> readAgentActionRemoteAuditTableColumnNames() async {
    final rows = await customSelect(
      'PRAGMA table_info("agent_action_remote_audit_table")',
      readsFrom: {agentActionRemoteAuditTable},
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<void> addAgentActionRemoteAuditClientColumnsIfMissing(
    Migrator m,
  ) async {
    var existing = await readAgentActionRemoteAuditTableColumnNames();
    final columns = <GeneratedColumn<Object>>[
      agentActionRemoteAuditTable.clientId as GeneratedColumn<Object>,
      agentActionRemoteAuditTable.tokenJti as GeneratedColumn<Object>,
    ];
    for (final column in columns) {
      final sqlName = column.name;
      if (existing.contains(sqlName)) {
        continue;
      }
      await m.addColumn(agentActionRemoteAuditTable, column);
      existing = {...existing, sqlName};
    }
  }

  Future<void> addAgentActionRemoteAuditRuntimeIdentityColumnsIfMissing(
    Migrator m,
  ) async {
    var existing = await readAgentActionRemoteAuditTableColumnNames();
    final columns = <GeneratedColumn<Object>>[
      agentActionRemoteAuditTable.runtimeInstanceId as GeneratedColumn<Object>,
      agentActionRemoteAuditTable.runtimeSessionId as GeneratedColumn<Object>,
    ];
    for (final column in columns) {
      final sqlName = column.name;
      if (existing.contains(sqlName)) {
        continue;
      }
      await m.addColumn(agentActionRemoteAuditTable, column);
      existing = {...existing, sqlName};
    }
  }

  Future<void> addAgentActionRemoteAuditIdempotencyKeyColumnIfMissing(
    Migrator m,
  ) async {
    final existing = await readAgentActionRemoteAuditTableColumnNames();
    final column =
        agentActionRemoteAuditTable.idempotencyKey as GeneratedColumn<Object>;
    if (existing.contains(column.name)) {
      return;
    }
    await m.addColumn(agentActionRemoteAuditTable, column);
  }

  Future<void> createRpcIdempotencyIndexes() async {
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_rpc_idempotency_expires
      ON rpc_idempotency_cache_table(expires_at)
      ''',
    );
  }

  Future<void> createAgentActionRemoteAuditIndexes() async {
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_remote_audit_occurred
      ON agent_action_remote_audit_table(occurred_at DESC)
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_remote_audit_method_occurred
      ON agent_action_remote_audit_table(rpc_method, occurred_at DESC)
      ''',
    );
  }

  Future<void> createClientTokenIndexes() async {
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_client_token_client_created
      ON client_token_cache_table(client_id, created_at DESC)
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_client_token_status_created
      ON client_token_cache_table(is_revoked, created_at DESC)
      ''',
    );
  }

  Future<void> createAgentActionCapturedOutputChunkIndexes() async {
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_captured_output_execution_stream
      ON agent_action_captured_output_chunk_table(execution_id, stream, chunk_index)
      ''',
    );
  }

  Future<void> createAgentActionIndexes() async {
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_definition_type_state
      ON agent_action_definition_table(type, state)
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_execution_action_requested
      ON agent_action_execution_table(action_id, requested_at DESC)
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_execution_status_requested
      ON agent_action_execution_table(status, requested_at DESC)
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_execution_idempotency
      ON agent_action_execution_table(idempotency_key)
      WHERE idempotency_key IS NOT NULL
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_execution_trigger
      ON agent_action_execution_table(trigger_id, scheduled_at)
      WHERE trigger_id IS NOT NULL
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_trigger_action_enabled
      ON agent_action_trigger_table(action_id, is_enabled)
      ''',
    );
    await customStatement(
      '''
      CREATE INDEX IF NOT EXISTS idx_agent_action_trigger_type_next
      ON agent_action_trigger_table(type, next_run_at)
      ''',
    );
  }
}
