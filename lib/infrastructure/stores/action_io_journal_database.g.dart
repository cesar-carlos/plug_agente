// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_io_journal_database.dart';

// ignore_for_file: type=lint
class $ActionIoSessionsTable extends ActionIoSessions
    with TableInfo<$ActionIoSessionsTable, ActionIoSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionIoSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _executionIdMeta = const VerificationMeta(
    'executionId',
  );
  @override
  late final GeneratedColumn<String> executionId = GeneratedColumn<String>(
    'execution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installationIdMeta = const VerificationMeta(
    'installationId',
  );
  @override
  late final GeneratedColumn<String> installationId = GeneratedColumn<String>(
    'installation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _agentIdMeta = const VerificationMeta(
    'agentId',
  );
  @override
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
    'agent_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  @override
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triggerIdMeta = const VerificationMeta(
    'triggerId',
  );
  @override
  late final GeneratedColumn<String> triggerId = GeneratedColumn<String>(
    'trigger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionTypeMeta = const VerificationMeta(
    'actionType',
  );
  @override
  late final GeneratedColumn<String> actionType = GeneratedColumn<String>(
    'action_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _definitionHashMeta = const VerificationMeta(
    'definitionHash',
  );
  @override
  late final GeneratedColumn<String> definitionHash = GeneratedColumn<String>(
    'definition_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _processStateMeta = const VerificationMeta(
    'processState',
  );
  @override
  late final GeneratedColumn<String> processState = GeneratedColumn<String>(
    'process_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stdinStateMeta = const VerificationMeta(
    'stdinState',
  );
  @override
  late final GeneratedColumn<String> stdinState = GeneratedColumn<String>(
    'stdin_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captureStateMeta = const VerificationMeta(
    'captureState',
  );
  @override
  late final GeneratedColumn<String> captureState = GeneratedColumn<String>(
    'capture_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextInputSequenceMeta = const VerificationMeta(
    'nextInputSequence',
  );
  @override
  late final GeneratedColumn<int> nextInputSequence = GeneratedColumn<int>(
    'next_input_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextEventSequenceMeta = const VerificationMeta(
    'nextEventSequence',
  );
  @override
  late final GeneratedColumn<int> nextEventSequence = GeneratedColumn<int>(
    'next_event_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _admittedInputBytesMeta =
      const VerificationMeta('admittedInputBytes');
  @override
  late final GeneratedColumn<int> admittedInputBytes = GeneratedColumn<int>(
    'admitted_input_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stdoutBytesMeta = const VerificationMeta(
    'stdoutBytes',
  );
  @override
  late final GeneratedColumn<int> stdoutBytes = GeneratedColumn<int>(
    'stdout_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stderrBytesMeta = const VerificationMeta(
    'stderrBytes',
  );
  @override
  late final GeneratedColumn<int> stderrBytes = GeneratedColumn<int>(
    'stderr_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _queuedInputBytesMeta = const VerificationMeta(
    'queuedInputBytes',
  );
  @override
  late final GeneratedColumn<int> queuedInputBytes = GeneratedColumn<int>(
    'queued_input_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _queuedInputMessagesMeta =
      const VerificationMeta('queuedInputMessages');
  @override
  late final GeneratedColumn<int> queuedInputMessages = GeneratedColumn<int>(
    'queued_input_messages',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _exitCodeMeta = const VerificationMeta(
    'exitCode',
  );
  @override
  late final GeneratedColumn<int> exitCode = GeneratedColumn<int>(
    'exit_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _diagnosticIdMeta = const VerificationMeta(
    'diagnosticId',
  );
  @override
  late final GeneratedColumn<String> diagnosticId = GeneratedColumn<String>(
    'diagnostic_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _terminalAtMeta = const VerificationMeta(
    'terminalAt',
  );
  @override
  late final GeneratedColumn<DateTime> terminalAt = GeneratedColumn<DateTime>(
    'terminal_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outputExpiresAtMeta = const VerificationMeta(
    'outputExpiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> outputExpiresAt =
      GeneratedColumn<DateTime>(
        'output_expires_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dedupeExpiresAtMeta = const VerificationMeta(
    'dedupeExpiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> dedupeExpiresAt =
      GeneratedColumn<DateTime>(
        'dedupe_expires_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _outputExpiredMeta = const VerificationMeta(
    'outputExpired',
  );
  @override
  late final GeneratedColumn<bool> outputExpired = GeneratedColumn<bool>(
    'output_expired',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("output_expired" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    executionId,
    installationId,
    agentId,
    clientId,
    actionId,
    idempotencyKey,
    fingerprint,
    triggerId,
    actionType,
    definitionHash,
    processState,
    stdinState,
    captureState,
    nextInputSequence,
    nextEventSequence,
    admittedInputBytes,
    stdoutBytes,
    stderrBytes,
    queuedInputBytes,
    queuedInputMessages,
    exitCode,
    failureCode,
    diagnosticId,
    createdAt,
    terminalAt,
    outputExpiresAt,
    dedupeExpiresAt,
    outputExpired,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_io_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionIoSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('execution_id')) {
      context.handle(
        _executionIdMeta,
        executionId.isAcceptableOrUnknown(
          data['execution_id']!,
          _executionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_executionIdMeta);
    }
    if (data.containsKey('installation_id')) {
      context.handle(
        _installationIdMeta,
        installationId.isAcceptableOrUnknown(
          data['installation_id']!,
          _installationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installationIdMeta);
    }
    if (data.containsKey('agent_id')) {
      context.handle(
        _agentIdMeta,
        agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_agentIdMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('trigger_id')) {
      context.handle(
        _triggerIdMeta,
        triggerId.isAcceptableOrUnknown(data['trigger_id']!, _triggerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_triggerIdMeta);
    }
    if (data.containsKey('action_type')) {
      context.handle(
        _actionTypeMeta,
        actionType.isAcceptableOrUnknown(data['action_type']!, _actionTypeMeta),
      );
    }
    if (data.containsKey('definition_hash')) {
      context.handle(
        _definitionHashMeta,
        definitionHash.isAcceptableOrUnknown(
          data['definition_hash']!,
          _definitionHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_definitionHashMeta);
    }
    if (data.containsKey('process_state')) {
      context.handle(
        _processStateMeta,
        processState.isAcceptableOrUnknown(
          data['process_state']!,
          _processStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_processStateMeta);
    }
    if (data.containsKey('stdin_state')) {
      context.handle(
        _stdinStateMeta,
        stdinState.isAcceptableOrUnknown(data['stdin_state']!, _stdinStateMeta),
      );
    } else if (isInserting) {
      context.missing(_stdinStateMeta);
    }
    if (data.containsKey('capture_state')) {
      context.handle(
        _captureStateMeta,
        captureState.isAcceptableOrUnknown(
          data['capture_state']!,
          _captureStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_captureStateMeta);
    }
    if (data.containsKey('next_input_sequence')) {
      context.handle(
        _nextInputSequenceMeta,
        nextInputSequence.isAcceptableOrUnknown(
          data['next_input_sequence']!,
          _nextInputSequenceMeta,
        ),
      );
    }
    if (data.containsKey('next_event_sequence')) {
      context.handle(
        _nextEventSequenceMeta,
        nextEventSequence.isAcceptableOrUnknown(
          data['next_event_sequence']!,
          _nextEventSequenceMeta,
        ),
      );
    }
    if (data.containsKey('admitted_input_bytes')) {
      context.handle(
        _admittedInputBytesMeta,
        admittedInputBytes.isAcceptableOrUnknown(
          data['admitted_input_bytes']!,
          _admittedInputBytesMeta,
        ),
      );
    }
    if (data.containsKey('stdout_bytes')) {
      context.handle(
        _stdoutBytesMeta,
        stdoutBytes.isAcceptableOrUnknown(
          data['stdout_bytes']!,
          _stdoutBytesMeta,
        ),
      );
    }
    if (data.containsKey('stderr_bytes')) {
      context.handle(
        _stderrBytesMeta,
        stderrBytes.isAcceptableOrUnknown(
          data['stderr_bytes']!,
          _stderrBytesMeta,
        ),
      );
    }
    if (data.containsKey('queued_input_bytes')) {
      context.handle(
        _queuedInputBytesMeta,
        queuedInputBytes.isAcceptableOrUnknown(
          data['queued_input_bytes']!,
          _queuedInputBytesMeta,
        ),
      );
    }
    if (data.containsKey('queued_input_messages')) {
      context.handle(
        _queuedInputMessagesMeta,
        queuedInputMessages.isAcceptableOrUnknown(
          data['queued_input_messages']!,
          _queuedInputMessagesMeta,
        ),
      );
    }
    if (data.containsKey('exit_code')) {
      context.handle(
        _exitCodeMeta,
        exitCode.isAcceptableOrUnknown(data['exit_code']!, _exitCodeMeta),
      );
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    if (data.containsKey('diagnostic_id')) {
      context.handle(
        _diagnosticIdMeta,
        diagnosticId.isAcceptableOrUnknown(
          data['diagnostic_id']!,
          _diagnosticIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('terminal_at')) {
      context.handle(
        _terminalAtMeta,
        terminalAt.isAcceptableOrUnknown(data['terminal_at']!, _terminalAtMeta),
      );
    }
    if (data.containsKey('output_expires_at')) {
      context.handle(
        _outputExpiresAtMeta,
        outputExpiresAt.isAcceptableOrUnknown(
          data['output_expires_at']!,
          _outputExpiresAtMeta,
        ),
      );
    }
    if (data.containsKey('dedupe_expires_at')) {
      context.handle(
        _dedupeExpiresAtMeta,
        dedupeExpiresAt.isAcceptableOrUnknown(
          data['dedupe_expires_at']!,
          _dedupeExpiresAtMeta,
        ),
      );
    }
    if (data.containsKey('output_expired')) {
      context.handle(
        _outputExpiredMeta,
        outputExpired.isAcceptableOrUnknown(
          data['output_expired']!,
          _outputExpiredMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {executionId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {installationId, agentId, clientId, actionId, idempotencyKey},
  ];
  @override
  ActionIoSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionIoSession(
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      installationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}installation_id'],
      )!,
      agentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      triggerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_id'],
      )!,
      actionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_type'],
      ),
      definitionHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}definition_hash'],
      )!,
      processState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}process_state'],
      )!,
      stdinState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stdin_state'],
      )!,
      captureState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_state'],
      )!,
      nextInputSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_input_sequence'],
      )!,
      nextEventSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_event_sequence'],
      )!,
      admittedInputBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}admitted_input_bytes'],
      )!,
      stdoutBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stdout_bytes'],
      )!,
      stderrBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stderr_bytes'],
      )!,
      queuedInputBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queued_input_bytes'],
      )!,
      queuedInputMessages: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queued_input_messages'],
      )!,
      exitCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exit_code'],
      ),
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      diagnosticId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diagnostic_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      terminalAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}terminal_at'],
      ),
      outputExpiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}output_expires_at'],
      ),
      dedupeExpiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}dedupe_expires_at'],
      ),
      outputExpired: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}output_expired'],
      )!,
    );
  }

  @override
  $ActionIoSessionsTable createAlias(String alias) {
    return $ActionIoSessionsTable(attachedDatabase, alias);
  }
}

class ActionIoSession extends DataClass implements Insertable<ActionIoSession> {
  final String executionId;
  final String installationId;
  final String agentId;
  final String clientId;
  final String actionId;
  final String idempotencyKey;
  final String fingerprint;
  final String triggerId;
  final String? actionType;
  final String definitionHash;
  final String processState;
  final String stdinState;
  final String captureState;
  final int nextInputSequence;
  final int nextEventSequence;
  final int admittedInputBytes;
  final int stdoutBytes;
  final int stderrBytes;
  final int queuedInputBytes;
  final int queuedInputMessages;
  final int? exitCode;
  final String? failureCode;
  final String? diagnosticId;
  final DateTime createdAt;
  final DateTime? terminalAt;
  final DateTime? outputExpiresAt;
  final DateTime? dedupeExpiresAt;
  final bool outputExpired;
  const ActionIoSession({
    required this.executionId,
    required this.installationId,
    required this.agentId,
    required this.clientId,
    required this.actionId,
    required this.idempotencyKey,
    required this.fingerprint,
    required this.triggerId,
    this.actionType,
    required this.definitionHash,
    required this.processState,
    required this.stdinState,
    required this.captureState,
    required this.nextInputSequence,
    required this.nextEventSequence,
    required this.admittedInputBytes,
    required this.stdoutBytes,
    required this.stderrBytes,
    required this.queuedInputBytes,
    required this.queuedInputMessages,
    this.exitCode,
    this.failureCode,
    this.diagnosticId,
    required this.createdAt,
    this.terminalAt,
    this.outputExpiresAt,
    this.dedupeExpiresAt,
    required this.outputExpired,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['execution_id'] = Variable<String>(executionId);
    map['installation_id'] = Variable<String>(installationId);
    map['agent_id'] = Variable<String>(agentId);
    map['client_id'] = Variable<String>(clientId);
    map['action_id'] = Variable<String>(actionId);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['trigger_id'] = Variable<String>(triggerId);
    if (!nullToAbsent || actionType != null) {
      map['action_type'] = Variable<String>(actionType);
    }
    map['definition_hash'] = Variable<String>(definitionHash);
    map['process_state'] = Variable<String>(processState);
    map['stdin_state'] = Variable<String>(stdinState);
    map['capture_state'] = Variable<String>(captureState);
    map['next_input_sequence'] = Variable<int>(nextInputSequence);
    map['next_event_sequence'] = Variable<int>(nextEventSequence);
    map['admitted_input_bytes'] = Variable<int>(admittedInputBytes);
    map['stdout_bytes'] = Variable<int>(stdoutBytes);
    map['stderr_bytes'] = Variable<int>(stderrBytes);
    map['queued_input_bytes'] = Variable<int>(queuedInputBytes);
    map['queued_input_messages'] = Variable<int>(queuedInputMessages);
    if (!nullToAbsent || exitCode != null) {
      map['exit_code'] = Variable<int>(exitCode);
    }
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    if (!nullToAbsent || diagnosticId != null) {
      map['diagnostic_id'] = Variable<String>(diagnosticId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || terminalAt != null) {
      map['terminal_at'] = Variable<DateTime>(terminalAt);
    }
    if (!nullToAbsent || outputExpiresAt != null) {
      map['output_expires_at'] = Variable<DateTime>(outputExpiresAt);
    }
    if (!nullToAbsent || dedupeExpiresAt != null) {
      map['dedupe_expires_at'] = Variable<DateTime>(dedupeExpiresAt);
    }
    map['output_expired'] = Variable<bool>(outputExpired);
    return map;
  }

  ActionIoSessionsCompanion toCompanion(bool nullToAbsent) {
    return ActionIoSessionsCompanion(
      executionId: Value(executionId),
      installationId: Value(installationId),
      agentId: Value(agentId),
      clientId: Value(clientId),
      actionId: Value(actionId),
      idempotencyKey: Value(idempotencyKey),
      fingerprint: Value(fingerprint),
      triggerId: Value(triggerId),
      actionType: actionType == null && nullToAbsent
          ? const Value.absent()
          : Value(actionType),
      definitionHash: Value(definitionHash),
      processState: Value(processState),
      stdinState: Value(stdinState),
      captureState: Value(captureState),
      nextInputSequence: Value(nextInputSequence),
      nextEventSequence: Value(nextEventSequence),
      admittedInputBytes: Value(admittedInputBytes),
      stdoutBytes: Value(stdoutBytes),
      stderrBytes: Value(stderrBytes),
      queuedInputBytes: Value(queuedInputBytes),
      queuedInputMessages: Value(queuedInputMessages),
      exitCode: exitCode == null && nullToAbsent
          ? const Value.absent()
          : Value(exitCode),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      diagnosticId: diagnosticId == null && nullToAbsent
          ? const Value.absent()
          : Value(diagnosticId),
      createdAt: Value(createdAt),
      terminalAt: terminalAt == null && nullToAbsent
          ? const Value.absent()
          : Value(terminalAt),
      outputExpiresAt: outputExpiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(outputExpiresAt),
      dedupeExpiresAt: dedupeExpiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dedupeExpiresAt),
      outputExpired: Value(outputExpired),
    );
  }

  factory ActionIoSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionIoSession(
      executionId: serializer.fromJson<String>(json['executionId']),
      installationId: serializer.fromJson<String>(json['installationId']),
      agentId: serializer.fromJson<String>(json['agentId']),
      clientId: serializer.fromJson<String>(json['clientId']),
      actionId: serializer.fromJson<String>(json['actionId']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      triggerId: serializer.fromJson<String>(json['triggerId']),
      actionType: serializer.fromJson<String?>(json['actionType']),
      definitionHash: serializer.fromJson<String>(json['definitionHash']),
      processState: serializer.fromJson<String>(json['processState']),
      stdinState: serializer.fromJson<String>(json['stdinState']),
      captureState: serializer.fromJson<String>(json['captureState']),
      nextInputSequence: serializer.fromJson<int>(json['nextInputSequence']),
      nextEventSequence: serializer.fromJson<int>(json['nextEventSequence']),
      admittedInputBytes: serializer.fromJson<int>(json['admittedInputBytes']),
      stdoutBytes: serializer.fromJson<int>(json['stdoutBytes']),
      stderrBytes: serializer.fromJson<int>(json['stderrBytes']),
      queuedInputBytes: serializer.fromJson<int>(json['queuedInputBytes']),
      queuedInputMessages: serializer.fromJson<int>(
        json['queuedInputMessages'],
      ),
      exitCode: serializer.fromJson<int?>(json['exitCode']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      diagnosticId: serializer.fromJson<String?>(json['diagnosticId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      terminalAt: serializer.fromJson<DateTime?>(json['terminalAt']),
      outputExpiresAt: serializer.fromJson<DateTime?>(json['outputExpiresAt']),
      dedupeExpiresAt: serializer.fromJson<DateTime?>(json['dedupeExpiresAt']),
      outputExpired: serializer.fromJson<bool>(json['outputExpired']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'executionId': serializer.toJson<String>(executionId),
      'installationId': serializer.toJson<String>(installationId),
      'agentId': serializer.toJson<String>(agentId),
      'clientId': serializer.toJson<String>(clientId),
      'actionId': serializer.toJson<String>(actionId),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'triggerId': serializer.toJson<String>(triggerId),
      'actionType': serializer.toJson<String?>(actionType),
      'definitionHash': serializer.toJson<String>(definitionHash),
      'processState': serializer.toJson<String>(processState),
      'stdinState': serializer.toJson<String>(stdinState),
      'captureState': serializer.toJson<String>(captureState),
      'nextInputSequence': serializer.toJson<int>(nextInputSequence),
      'nextEventSequence': serializer.toJson<int>(nextEventSequence),
      'admittedInputBytes': serializer.toJson<int>(admittedInputBytes),
      'stdoutBytes': serializer.toJson<int>(stdoutBytes),
      'stderrBytes': serializer.toJson<int>(stderrBytes),
      'queuedInputBytes': serializer.toJson<int>(queuedInputBytes),
      'queuedInputMessages': serializer.toJson<int>(queuedInputMessages),
      'exitCode': serializer.toJson<int?>(exitCode),
      'failureCode': serializer.toJson<String?>(failureCode),
      'diagnosticId': serializer.toJson<String?>(diagnosticId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'terminalAt': serializer.toJson<DateTime?>(terminalAt),
      'outputExpiresAt': serializer.toJson<DateTime?>(outputExpiresAt),
      'dedupeExpiresAt': serializer.toJson<DateTime?>(dedupeExpiresAt),
      'outputExpired': serializer.toJson<bool>(outputExpired),
    };
  }

  ActionIoSession copyWith({
    String? executionId,
    String? installationId,
    String? agentId,
    String? clientId,
    String? actionId,
    String? idempotencyKey,
    String? fingerprint,
    String? triggerId,
    Value<String?> actionType = const Value.absent(),
    String? definitionHash,
    String? processState,
    String? stdinState,
    String? captureState,
    int? nextInputSequence,
    int? nextEventSequence,
    int? admittedInputBytes,
    int? stdoutBytes,
    int? stderrBytes,
    int? queuedInputBytes,
    int? queuedInputMessages,
    Value<int?> exitCode = const Value.absent(),
    Value<String?> failureCode = const Value.absent(),
    Value<String?> diagnosticId = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> terminalAt = const Value.absent(),
    Value<DateTime?> outputExpiresAt = const Value.absent(),
    Value<DateTime?> dedupeExpiresAt = const Value.absent(),
    bool? outputExpired,
  }) => ActionIoSession(
    executionId: executionId ?? this.executionId,
    installationId: installationId ?? this.installationId,
    agentId: agentId ?? this.agentId,
    clientId: clientId ?? this.clientId,
    actionId: actionId ?? this.actionId,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    fingerprint: fingerprint ?? this.fingerprint,
    triggerId: triggerId ?? this.triggerId,
    actionType: actionType.present ? actionType.value : this.actionType,
    definitionHash: definitionHash ?? this.definitionHash,
    processState: processState ?? this.processState,
    stdinState: stdinState ?? this.stdinState,
    captureState: captureState ?? this.captureState,
    nextInputSequence: nextInputSequence ?? this.nextInputSequence,
    nextEventSequence: nextEventSequence ?? this.nextEventSequence,
    admittedInputBytes: admittedInputBytes ?? this.admittedInputBytes,
    stdoutBytes: stdoutBytes ?? this.stdoutBytes,
    stderrBytes: stderrBytes ?? this.stderrBytes,
    queuedInputBytes: queuedInputBytes ?? this.queuedInputBytes,
    queuedInputMessages: queuedInputMessages ?? this.queuedInputMessages,
    exitCode: exitCode.present ? exitCode.value : this.exitCode,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    diagnosticId: diagnosticId.present ? diagnosticId.value : this.diagnosticId,
    createdAt: createdAt ?? this.createdAt,
    terminalAt: terminalAt.present ? terminalAt.value : this.terminalAt,
    outputExpiresAt: outputExpiresAt.present
        ? outputExpiresAt.value
        : this.outputExpiresAt,
    dedupeExpiresAt: dedupeExpiresAt.present
        ? dedupeExpiresAt.value
        : this.dedupeExpiresAt,
    outputExpired: outputExpired ?? this.outputExpired,
  );
  ActionIoSession copyWithCompanion(ActionIoSessionsCompanion data) {
    return ActionIoSession(
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      installationId: data.installationId.present
          ? data.installationId.value
          : this.installationId,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      triggerId: data.triggerId.present ? data.triggerId.value : this.triggerId,
      actionType: data.actionType.present
          ? data.actionType.value
          : this.actionType,
      definitionHash: data.definitionHash.present
          ? data.definitionHash.value
          : this.definitionHash,
      processState: data.processState.present
          ? data.processState.value
          : this.processState,
      stdinState: data.stdinState.present
          ? data.stdinState.value
          : this.stdinState,
      captureState: data.captureState.present
          ? data.captureState.value
          : this.captureState,
      nextInputSequence: data.nextInputSequence.present
          ? data.nextInputSequence.value
          : this.nextInputSequence,
      nextEventSequence: data.nextEventSequence.present
          ? data.nextEventSequence.value
          : this.nextEventSequence,
      admittedInputBytes: data.admittedInputBytes.present
          ? data.admittedInputBytes.value
          : this.admittedInputBytes,
      stdoutBytes: data.stdoutBytes.present
          ? data.stdoutBytes.value
          : this.stdoutBytes,
      stderrBytes: data.stderrBytes.present
          ? data.stderrBytes.value
          : this.stderrBytes,
      queuedInputBytes: data.queuedInputBytes.present
          ? data.queuedInputBytes.value
          : this.queuedInputBytes,
      queuedInputMessages: data.queuedInputMessages.present
          ? data.queuedInputMessages.value
          : this.queuedInputMessages,
      exitCode: data.exitCode.present ? data.exitCode.value : this.exitCode,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      diagnosticId: data.diagnosticId.present
          ? data.diagnosticId.value
          : this.diagnosticId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      terminalAt: data.terminalAt.present
          ? data.terminalAt.value
          : this.terminalAt,
      outputExpiresAt: data.outputExpiresAt.present
          ? data.outputExpiresAt.value
          : this.outputExpiresAt,
      dedupeExpiresAt: data.dedupeExpiresAt.present
          ? data.dedupeExpiresAt.value
          : this.dedupeExpiresAt,
      outputExpired: data.outputExpired.present
          ? data.outputExpired.value
          : this.outputExpired,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoSession(')
          ..write('executionId: $executionId, ')
          ..write('installationId: $installationId, ')
          ..write('agentId: $agentId, ')
          ..write('clientId: $clientId, ')
          ..write('actionId: $actionId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('triggerId: $triggerId, ')
          ..write('actionType: $actionType, ')
          ..write('definitionHash: $definitionHash, ')
          ..write('processState: $processState, ')
          ..write('stdinState: $stdinState, ')
          ..write('captureState: $captureState, ')
          ..write('nextInputSequence: $nextInputSequence, ')
          ..write('nextEventSequence: $nextEventSequence, ')
          ..write('admittedInputBytes: $admittedInputBytes, ')
          ..write('stdoutBytes: $stdoutBytes, ')
          ..write('stderrBytes: $stderrBytes, ')
          ..write('queuedInputBytes: $queuedInputBytes, ')
          ..write('queuedInputMessages: $queuedInputMessages, ')
          ..write('exitCode: $exitCode, ')
          ..write('failureCode: $failureCode, ')
          ..write('diagnosticId: $diagnosticId, ')
          ..write('createdAt: $createdAt, ')
          ..write('terminalAt: $terminalAt, ')
          ..write('outputExpiresAt: $outputExpiresAt, ')
          ..write('dedupeExpiresAt: $dedupeExpiresAt, ')
          ..write('outputExpired: $outputExpired')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    executionId,
    installationId,
    agentId,
    clientId,
    actionId,
    idempotencyKey,
    fingerprint,
    triggerId,
    actionType,
    definitionHash,
    processState,
    stdinState,
    captureState,
    nextInputSequence,
    nextEventSequence,
    admittedInputBytes,
    stdoutBytes,
    stderrBytes,
    queuedInputBytes,
    queuedInputMessages,
    exitCode,
    failureCode,
    diagnosticId,
    createdAt,
    terminalAt,
    outputExpiresAt,
    dedupeExpiresAt,
    outputExpired,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionIoSession &&
          other.executionId == this.executionId &&
          other.installationId == this.installationId &&
          other.agentId == this.agentId &&
          other.clientId == this.clientId &&
          other.actionId == this.actionId &&
          other.idempotencyKey == this.idempotencyKey &&
          other.fingerprint == this.fingerprint &&
          other.triggerId == this.triggerId &&
          other.actionType == this.actionType &&
          other.definitionHash == this.definitionHash &&
          other.processState == this.processState &&
          other.stdinState == this.stdinState &&
          other.captureState == this.captureState &&
          other.nextInputSequence == this.nextInputSequence &&
          other.nextEventSequence == this.nextEventSequence &&
          other.admittedInputBytes == this.admittedInputBytes &&
          other.stdoutBytes == this.stdoutBytes &&
          other.stderrBytes == this.stderrBytes &&
          other.queuedInputBytes == this.queuedInputBytes &&
          other.queuedInputMessages == this.queuedInputMessages &&
          other.exitCode == this.exitCode &&
          other.failureCode == this.failureCode &&
          other.diagnosticId == this.diagnosticId &&
          other.createdAt == this.createdAt &&
          other.terminalAt == this.terminalAt &&
          other.outputExpiresAt == this.outputExpiresAt &&
          other.dedupeExpiresAt == this.dedupeExpiresAt &&
          other.outputExpired == this.outputExpired);
}

class ActionIoSessionsCompanion extends UpdateCompanion<ActionIoSession> {
  final Value<String> executionId;
  final Value<String> installationId;
  final Value<String> agentId;
  final Value<String> clientId;
  final Value<String> actionId;
  final Value<String> idempotencyKey;
  final Value<String> fingerprint;
  final Value<String> triggerId;
  final Value<String?> actionType;
  final Value<String> definitionHash;
  final Value<String> processState;
  final Value<String> stdinState;
  final Value<String> captureState;
  final Value<int> nextInputSequence;
  final Value<int> nextEventSequence;
  final Value<int> admittedInputBytes;
  final Value<int> stdoutBytes;
  final Value<int> stderrBytes;
  final Value<int> queuedInputBytes;
  final Value<int> queuedInputMessages;
  final Value<int?> exitCode;
  final Value<String?> failureCode;
  final Value<String?> diagnosticId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> terminalAt;
  final Value<DateTime?> outputExpiresAt;
  final Value<DateTime?> dedupeExpiresAt;
  final Value<bool> outputExpired;
  final Value<int> rowid;
  const ActionIoSessionsCompanion({
    this.executionId = const Value.absent(),
    this.installationId = const Value.absent(),
    this.agentId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.actionId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.triggerId = const Value.absent(),
    this.actionType = const Value.absent(),
    this.definitionHash = const Value.absent(),
    this.processState = const Value.absent(),
    this.stdinState = const Value.absent(),
    this.captureState = const Value.absent(),
    this.nextInputSequence = const Value.absent(),
    this.nextEventSequence = const Value.absent(),
    this.admittedInputBytes = const Value.absent(),
    this.stdoutBytes = const Value.absent(),
    this.stderrBytes = const Value.absent(),
    this.queuedInputBytes = const Value.absent(),
    this.queuedInputMessages = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.diagnosticId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.terminalAt = const Value.absent(),
    this.outputExpiresAt = const Value.absent(),
    this.dedupeExpiresAt = const Value.absent(),
    this.outputExpired = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionIoSessionsCompanion.insert({
    required String executionId,
    required String installationId,
    required String agentId,
    required String clientId,
    required String actionId,
    required String idempotencyKey,
    required String fingerprint,
    required String triggerId,
    this.actionType = const Value.absent(),
    required String definitionHash,
    required String processState,
    required String stdinState,
    required String captureState,
    this.nextInputSequence = const Value.absent(),
    this.nextEventSequence = const Value.absent(),
    this.admittedInputBytes = const Value.absent(),
    this.stdoutBytes = const Value.absent(),
    this.stderrBytes = const Value.absent(),
    this.queuedInputBytes = const Value.absent(),
    this.queuedInputMessages = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.diagnosticId = const Value.absent(),
    required DateTime createdAt,
    this.terminalAt = const Value.absent(),
    this.outputExpiresAt = const Value.absent(),
    this.dedupeExpiresAt = const Value.absent(),
    this.outputExpired = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : executionId = Value(executionId),
       installationId = Value(installationId),
       agentId = Value(agentId),
       clientId = Value(clientId),
       actionId = Value(actionId),
       idempotencyKey = Value(idempotencyKey),
       fingerprint = Value(fingerprint),
       triggerId = Value(triggerId),
       definitionHash = Value(definitionHash),
       processState = Value(processState),
       stdinState = Value(stdinState),
       captureState = Value(captureState),
       createdAt = Value(createdAt);
  static Insertable<ActionIoSession> custom({
    Expression<String>? executionId,
    Expression<String>? installationId,
    Expression<String>? agentId,
    Expression<String>? clientId,
    Expression<String>? actionId,
    Expression<String>? idempotencyKey,
    Expression<String>? fingerprint,
    Expression<String>? triggerId,
    Expression<String>? actionType,
    Expression<String>? definitionHash,
    Expression<String>? processState,
    Expression<String>? stdinState,
    Expression<String>? captureState,
    Expression<int>? nextInputSequence,
    Expression<int>? nextEventSequence,
    Expression<int>? admittedInputBytes,
    Expression<int>? stdoutBytes,
    Expression<int>? stderrBytes,
    Expression<int>? queuedInputBytes,
    Expression<int>? queuedInputMessages,
    Expression<int>? exitCode,
    Expression<String>? failureCode,
    Expression<String>? diagnosticId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? terminalAt,
    Expression<DateTime>? outputExpiresAt,
    Expression<DateTime>? dedupeExpiresAt,
    Expression<bool>? outputExpired,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (executionId != null) 'execution_id': executionId,
      if (installationId != null) 'installation_id': installationId,
      if (agentId != null) 'agent_id': agentId,
      if (clientId != null) 'client_id': clientId,
      if (actionId != null) 'action_id': actionId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (triggerId != null) 'trigger_id': triggerId,
      if (actionType != null) 'action_type': actionType,
      if (definitionHash != null) 'definition_hash': definitionHash,
      if (processState != null) 'process_state': processState,
      if (stdinState != null) 'stdin_state': stdinState,
      if (captureState != null) 'capture_state': captureState,
      if (nextInputSequence != null) 'next_input_sequence': nextInputSequence,
      if (nextEventSequence != null) 'next_event_sequence': nextEventSequence,
      if (admittedInputBytes != null)
        'admitted_input_bytes': admittedInputBytes,
      if (stdoutBytes != null) 'stdout_bytes': stdoutBytes,
      if (stderrBytes != null) 'stderr_bytes': stderrBytes,
      if (queuedInputBytes != null) 'queued_input_bytes': queuedInputBytes,
      if (queuedInputMessages != null)
        'queued_input_messages': queuedInputMessages,
      if (exitCode != null) 'exit_code': exitCode,
      if (failureCode != null) 'failure_code': failureCode,
      if (diagnosticId != null) 'diagnostic_id': diagnosticId,
      if (createdAt != null) 'created_at': createdAt,
      if (terminalAt != null) 'terminal_at': terminalAt,
      if (outputExpiresAt != null) 'output_expires_at': outputExpiresAt,
      if (dedupeExpiresAt != null) 'dedupe_expires_at': dedupeExpiresAt,
      if (outputExpired != null) 'output_expired': outputExpired,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionIoSessionsCompanion copyWith({
    Value<String>? executionId,
    Value<String>? installationId,
    Value<String>? agentId,
    Value<String>? clientId,
    Value<String>? actionId,
    Value<String>? idempotencyKey,
    Value<String>? fingerprint,
    Value<String>? triggerId,
    Value<String?>? actionType,
    Value<String>? definitionHash,
    Value<String>? processState,
    Value<String>? stdinState,
    Value<String>? captureState,
    Value<int>? nextInputSequence,
    Value<int>? nextEventSequence,
    Value<int>? admittedInputBytes,
    Value<int>? stdoutBytes,
    Value<int>? stderrBytes,
    Value<int>? queuedInputBytes,
    Value<int>? queuedInputMessages,
    Value<int?>? exitCode,
    Value<String?>? failureCode,
    Value<String?>? diagnosticId,
    Value<DateTime>? createdAt,
    Value<DateTime?>? terminalAt,
    Value<DateTime?>? outputExpiresAt,
    Value<DateTime?>? dedupeExpiresAt,
    Value<bool>? outputExpired,
    Value<int>? rowid,
  }) {
    return ActionIoSessionsCompanion(
      executionId: executionId ?? this.executionId,
      installationId: installationId ?? this.installationId,
      agentId: agentId ?? this.agentId,
      clientId: clientId ?? this.clientId,
      actionId: actionId ?? this.actionId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      fingerprint: fingerprint ?? this.fingerprint,
      triggerId: triggerId ?? this.triggerId,
      actionType: actionType ?? this.actionType,
      definitionHash: definitionHash ?? this.definitionHash,
      processState: processState ?? this.processState,
      stdinState: stdinState ?? this.stdinState,
      captureState: captureState ?? this.captureState,
      nextInputSequence: nextInputSequence ?? this.nextInputSequence,
      nextEventSequence: nextEventSequence ?? this.nextEventSequence,
      admittedInputBytes: admittedInputBytes ?? this.admittedInputBytes,
      stdoutBytes: stdoutBytes ?? this.stdoutBytes,
      stderrBytes: stderrBytes ?? this.stderrBytes,
      queuedInputBytes: queuedInputBytes ?? this.queuedInputBytes,
      queuedInputMessages: queuedInputMessages ?? this.queuedInputMessages,
      exitCode: exitCode ?? this.exitCode,
      failureCode: failureCode ?? this.failureCode,
      diagnosticId: diagnosticId ?? this.diagnosticId,
      createdAt: createdAt ?? this.createdAt,
      terminalAt: terminalAt ?? this.terminalAt,
      outputExpiresAt: outputExpiresAt ?? this.outputExpiresAt,
      dedupeExpiresAt: dedupeExpiresAt ?? this.dedupeExpiresAt,
      outputExpired: outputExpired ?? this.outputExpired,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (installationId.present) {
      map['installation_id'] = Variable<String>(installationId.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (triggerId.present) {
      map['trigger_id'] = Variable<String>(triggerId.value);
    }
    if (actionType.present) {
      map['action_type'] = Variable<String>(actionType.value);
    }
    if (definitionHash.present) {
      map['definition_hash'] = Variable<String>(definitionHash.value);
    }
    if (processState.present) {
      map['process_state'] = Variable<String>(processState.value);
    }
    if (stdinState.present) {
      map['stdin_state'] = Variable<String>(stdinState.value);
    }
    if (captureState.present) {
      map['capture_state'] = Variable<String>(captureState.value);
    }
    if (nextInputSequence.present) {
      map['next_input_sequence'] = Variable<int>(nextInputSequence.value);
    }
    if (nextEventSequence.present) {
      map['next_event_sequence'] = Variable<int>(nextEventSequence.value);
    }
    if (admittedInputBytes.present) {
      map['admitted_input_bytes'] = Variable<int>(admittedInputBytes.value);
    }
    if (stdoutBytes.present) {
      map['stdout_bytes'] = Variable<int>(stdoutBytes.value);
    }
    if (stderrBytes.present) {
      map['stderr_bytes'] = Variable<int>(stderrBytes.value);
    }
    if (queuedInputBytes.present) {
      map['queued_input_bytes'] = Variable<int>(queuedInputBytes.value);
    }
    if (queuedInputMessages.present) {
      map['queued_input_messages'] = Variable<int>(queuedInputMessages.value);
    }
    if (exitCode.present) {
      map['exit_code'] = Variable<int>(exitCode.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (diagnosticId.present) {
      map['diagnostic_id'] = Variable<String>(diagnosticId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (terminalAt.present) {
      map['terminal_at'] = Variable<DateTime>(terminalAt.value);
    }
    if (outputExpiresAt.present) {
      map['output_expires_at'] = Variable<DateTime>(outputExpiresAt.value);
    }
    if (dedupeExpiresAt.present) {
      map['dedupe_expires_at'] = Variable<DateTime>(dedupeExpiresAt.value);
    }
    if (outputExpired.present) {
      map['output_expired'] = Variable<bool>(outputExpired.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoSessionsCompanion(')
          ..write('executionId: $executionId, ')
          ..write('installationId: $installationId, ')
          ..write('agentId: $agentId, ')
          ..write('clientId: $clientId, ')
          ..write('actionId: $actionId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('triggerId: $triggerId, ')
          ..write('actionType: $actionType, ')
          ..write('definitionHash: $definitionHash, ')
          ..write('processState: $processState, ')
          ..write('stdinState: $stdinState, ')
          ..write('captureState: $captureState, ')
          ..write('nextInputSequence: $nextInputSequence, ')
          ..write('nextEventSequence: $nextEventSequence, ')
          ..write('admittedInputBytes: $admittedInputBytes, ')
          ..write('stdoutBytes: $stdoutBytes, ')
          ..write('stderrBytes: $stderrBytes, ')
          ..write('queuedInputBytes: $queuedInputBytes, ')
          ..write('queuedInputMessages: $queuedInputMessages, ')
          ..write('exitCode: $exitCode, ')
          ..write('failureCode: $failureCode, ')
          ..write('diagnosticId: $diagnosticId, ')
          ..write('createdAt: $createdAt, ')
          ..write('terminalAt: $terminalAt, ')
          ..write('outputExpiresAt: $outputExpiresAt, ')
          ..write('dedupeExpiresAt: $dedupeExpiresAt, ')
          ..write('outputExpired: $outputExpired, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionIoPayloadsTable extends ActionIoPayloads
    with TableInfo<$ActionIoPayloadsTable, ActionIoPayload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionIoPayloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _payloadIdMeta = const VerificationMeta(
    'payloadId',
  );
  @override
  late final GeneratedColumn<String> payloadId = GeneratedColumn<String>(
    'payload_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _executionIdMeta = const VerificationMeta(
    'executionId',
  );
  @override
  late final GeneratedColumn<String> executionId = GeneratedColumn<String>(
    'execution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES action_io_sessions (execution_id)',
    ),
  );
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<String> keyId = GeneratedColumn<String>(
    'key_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<Uint8List> nonce = GeneratedColumn<Uint8List>(
    'nonce',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ciphertextMeta = const VerificationMeta(
    'ciphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> ciphertext = GeneratedColumn<Uint8List>(
    'ciphertext',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authenticationTagMeta = const VerificationMeta(
    'authenticationTag',
  );
  @override
  late final GeneratedColumn<Uint8List> authenticationTag =
      GeneratedColumn<Uint8List>(
        'authentication_tag',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _authenticatedContextMeta =
      const VerificationMeta('authenticatedContext');
  @override
  late final GeneratedColumn<Uint8List> authenticatedContext =
      GeneratedColumn<Uint8List>(
        'authenticated_context',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _plaintextBytesMeta = const VerificationMeta(
    'plaintextBytes',
  );
  @override
  late final GeneratedColumn<int> plaintextBytes = GeneratedColumn<int>(
    'plaintext_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    payloadId,
    executionId,
    keyId,
    nonce,
    ciphertext,
    authenticationTag,
    authenticatedContext,
    plaintextBytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_io_payloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionIoPayload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('payload_id')) {
      context.handle(
        _payloadIdMeta,
        payloadId.isAcceptableOrUnknown(data['payload_id']!, _payloadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadIdMeta);
    }
    if (data.containsKey('execution_id')) {
      context.handle(
        _executionIdMeta,
        executionId.isAcceptableOrUnknown(
          data['execution_id']!,
          _executionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_executionIdMeta);
    }
    if (data.containsKey('key_id')) {
      context.handle(
        _keyIdMeta,
        keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_keyIdMeta);
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    } else if (isInserting) {
      context.missing(_nonceMeta);
    }
    if (data.containsKey('ciphertext')) {
      context.handle(
        _ciphertextMeta,
        ciphertext.isAcceptableOrUnknown(data['ciphertext']!, _ciphertextMeta),
      );
    } else if (isInserting) {
      context.missing(_ciphertextMeta);
    }
    if (data.containsKey('authentication_tag')) {
      context.handle(
        _authenticationTagMeta,
        authenticationTag.isAcceptableOrUnknown(
          data['authentication_tag']!,
          _authenticationTagMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authenticationTagMeta);
    }
    if (data.containsKey('authenticated_context')) {
      context.handle(
        _authenticatedContextMeta,
        authenticatedContext.isAcceptableOrUnknown(
          data['authenticated_context']!,
          _authenticatedContextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authenticatedContextMeta);
    }
    if (data.containsKey('plaintext_bytes')) {
      context.handle(
        _plaintextBytesMeta,
        plaintextBytes.isAcceptableOrUnknown(
          data['plaintext_bytes']!,
          _plaintextBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_plaintextBytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {payloadId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {keyId, nonce},
  ];
  @override
  ActionIoPayload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionIoPayload(
      payloadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_id'],
      )!,
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      keyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_id'],
      )!,
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}nonce'],
      )!,
      ciphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}ciphertext'],
      )!,
      authenticationTag: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}authentication_tag'],
      )!,
      authenticatedContext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}authenticated_context'],
      )!,
      plaintextBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}plaintext_bytes'],
      )!,
    );
  }

  @override
  $ActionIoPayloadsTable createAlias(String alias) {
    return $ActionIoPayloadsTable(attachedDatabase, alias);
  }
}

class ActionIoPayload extends DataClass implements Insertable<ActionIoPayload> {
  final String payloadId;
  final String executionId;
  final String keyId;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List authenticationTag;
  final Uint8List authenticatedContext;
  final int plaintextBytes;
  const ActionIoPayload({
    required this.payloadId,
    required this.executionId,
    required this.keyId,
    required this.nonce,
    required this.ciphertext,
    required this.authenticationTag,
    required this.authenticatedContext,
    required this.plaintextBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['payload_id'] = Variable<String>(payloadId);
    map['execution_id'] = Variable<String>(executionId);
    map['key_id'] = Variable<String>(keyId);
    map['nonce'] = Variable<Uint8List>(nonce);
    map['ciphertext'] = Variable<Uint8List>(ciphertext);
    map['authentication_tag'] = Variable<Uint8List>(authenticationTag);
    map['authenticated_context'] = Variable<Uint8List>(authenticatedContext);
    map['plaintext_bytes'] = Variable<int>(plaintextBytes);
    return map;
  }

  ActionIoPayloadsCompanion toCompanion(bool nullToAbsent) {
    return ActionIoPayloadsCompanion(
      payloadId: Value(payloadId),
      executionId: Value(executionId),
      keyId: Value(keyId),
      nonce: Value(nonce),
      ciphertext: Value(ciphertext),
      authenticationTag: Value(authenticationTag),
      authenticatedContext: Value(authenticatedContext),
      plaintextBytes: Value(plaintextBytes),
    );
  }

  factory ActionIoPayload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionIoPayload(
      payloadId: serializer.fromJson<String>(json['payloadId']),
      executionId: serializer.fromJson<String>(json['executionId']),
      keyId: serializer.fromJson<String>(json['keyId']),
      nonce: serializer.fromJson<Uint8List>(json['nonce']),
      ciphertext: serializer.fromJson<Uint8List>(json['ciphertext']),
      authenticationTag: serializer.fromJson<Uint8List>(
        json['authenticationTag'],
      ),
      authenticatedContext: serializer.fromJson<Uint8List>(
        json['authenticatedContext'],
      ),
      plaintextBytes: serializer.fromJson<int>(json['plaintextBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'payloadId': serializer.toJson<String>(payloadId),
      'executionId': serializer.toJson<String>(executionId),
      'keyId': serializer.toJson<String>(keyId),
      'nonce': serializer.toJson<Uint8List>(nonce),
      'ciphertext': serializer.toJson<Uint8List>(ciphertext),
      'authenticationTag': serializer.toJson<Uint8List>(authenticationTag),
      'authenticatedContext': serializer.toJson<Uint8List>(
        authenticatedContext,
      ),
      'plaintextBytes': serializer.toJson<int>(plaintextBytes),
    };
  }

  ActionIoPayload copyWith({
    String? payloadId,
    String? executionId,
    String? keyId,
    Uint8List? nonce,
    Uint8List? ciphertext,
    Uint8List? authenticationTag,
    Uint8List? authenticatedContext,
    int? plaintextBytes,
  }) => ActionIoPayload(
    payloadId: payloadId ?? this.payloadId,
    executionId: executionId ?? this.executionId,
    keyId: keyId ?? this.keyId,
    nonce: nonce ?? this.nonce,
    ciphertext: ciphertext ?? this.ciphertext,
    authenticationTag: authenticationTag ?? this.authenticationTag,
    authenticatedContext: authenticatedContext ?? this.authenticatedContext,
    plaintextBytes: plaintextBytes ?? this.plaintextBytes,
  );
  ActionIoPayload copyWithCompanion(ActionIoPayloadsCompanion data) {
    return ActionIoPayload(
      payloadId: data.payloadId.present ? data.payloadId.value : this.payloadId,
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      ciphertext: data.ciphertext.present
          ? data.ciphertext.value
          : this.ciphertext,
      authenticationTag: data.authenticationTag.present
          ? data.authenticationTag.value
          : this.authenticationTag,
      authenticatedContext: data.authenticatedContext.present
          ? data.authenticatedContext.value
          : this.authenticatedContext,
      plaintextBytes: data.plaintextBytes.present
          ? data.plaintextBytes.value
          : this.plaintextBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoPayload(')
          ..write('payloadId: $payloadId, ')
          ..write('executionId: $executionId, ')
          ..write('keyId: $keyId, ')
          ..write('nonce: $nonce, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('authenticationTag: $authenticationTag, ')
          ..write('authenticatedContext: $authenticatedContext, ')
          ..write('plaintextBytes: $plaintextBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    payloadId,
    executionId,
    keyId,
    $driftBlobEquality.hash(nonce),
    $driftBlobEquality.hash(ciphertext),
    $driftBlobEquality.hash(authenticationTag),
    $driftBlobEquality.hash(authenticatedContext),
    plaintextBytes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionIoPayload &&
          other.payloadId == this.payloadId &&
          other.executionId == this.executionId &&
          other.keyId == this.keyId &&
          $driftBlobEquality.equals(other.nonce, this.nonce) &&
          $driftBlobEquality.equals(other.ciphertext, this.ciphertext) &&
          $driftBlobEquality.equals(
            other.authenticationTag,
            this.authenticationTag,
          ) &&
          $driftBlobEquality.equals(
            other.authenticatedContext,
            this.authenticatedContext,
          ) &&
          other.plaintextBytes == this.plaintextBytes);
}

class ActionIoPayloadsCompanion extends UpdateCompanion<ActionIoPayload> {
  final Value<String> payloadId;
  final Value<String> executionId;
  final Value<String> keyId;
  final Value<Uint8List> nonce;
  final Value<Uint8List> ciphertext;
  final Value<Uint8List> authenticationTag;
  final Value<Uint8List> authenticatedContext;
  final Value<int> plaintextBytes;
  final Value<int> rowid;
  const ActionIoPayloadsCompanion({
    this.payloadId = const Value.absent(),
    this.executionId = const Value.absent(),
    this.keyId = const Value.absent(),
    this.nonce = const Value.absent(),
    this.ciphertext = const Value.absent(),
    this.authenticationTag = const Value.absent(),
    this.authenticatedContext = const Value.absent(),
    this.plaintextBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionIoPayloadsCompanion.insert({
    required String payloadId,
    required String executionId,
    required String keyId,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List authenticationTag,
    required Uint8List authenticatedContext,
    required int plaintextBytes,
    this.rowid = const Value.absent(),
  }) : payloadId = Value(payloadId),
       executionId = Value(executionId),
       keyId = Value(keyId),
       nonce = Value(nonce),
       ciphertext = Value(ciphertext),
       authenticationTag = Value(authenticationTag),
       authenticatedContext = Value(authenticatedContext),
       plaintextBytes = Value(plaintextBytes);
  static Insertable<ActionIoPayload> custom({
    Expression<String>? payloadId,
    Expression<String>? executionId,
    Expression<String>? keyId,
    Expression<Uint8List>? nonce,
    Expression<Uint8List>? ciphertext,
    Expression<Uint8List>? authenticationTag,
    Expression<Uint8List>? authenticatedContext,
    Expression<int>? plaintextBytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (payloadId != null) 'payload_id': payloadId,
      if (executionId != null) 'execution_id': executionId,
      if (keyId != null) 'key_id': keyId,
      if (nonce != null) 'nonce': nonce,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (authenticationTag != null) 'authentication_tag': authenticationTag,
      if (authenticatedContext != null)
        'authenticated_context': authenticatedContext,
      if (plaintextBytes != null) 'plaintext_bytes': plaintextBytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionIoPayloadsCompanion copyWith({
    Value<String>? payloadId,
    Value<String>? executionId,
    Value<String>? keyId,
    Value<Uint8List>? nonce,
    Value<Uint8List>? ciphertext,
    Value<Uint8List>? authenticationTag,
    Value<Uint8List>? authenticatedContext,
    Value<int>? plaintextBytes,
    Value<int>? rowid,
  }) {
    return ActionIoPayloadsCompanion(
      payloadId: payloadId ?? this.payloadId,
      executionId: executionId ?? this.executionId,
      keyId: keyId ?? this.keyId,
      nonce: nonce ?? this.nonce,
      ciphertext: ciphertext ?? this.ciphertext,
      authenticationTag: authenticationTag ?? this.authenticationTag,
      authenticatedContext: authenticatedContext ?? this.authenticatedContext,
      plaintextBytes: plaintextBytes ?? this.plaintextBytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (payloadId.present) {
      map['payload_id'] = Variable<String>(payloadId.value);
    }
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (keyId.present) {
      map['key_id'] = Variable<String>(keyId.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<Uint8List>(nonce.value);
    }
    if (ciphertext.present) {
      map['ciphertext'] = Variable<Uint8List>(ciphertext.value);
    }
    if (authenticationTag.present) {
      map['authentication_tag'] = Variable<Uint8List>(authenticationTag.value);
    }
    if (authenticatedContext.present) {
      map['authenticated_context'] = Variable<Uint8List>(
        authenticatedContext.value,
      );
    }
    if (plaintextBytes.present) {
      map['plaintext_bytes'] = Variable<int>(plaintextBytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoPayloadsCompanion(')
          ..write('payloadId: $payloadId, ')
          ..write('executionId: $executionId, ')
          ..write('keyId: $keyId, ')
          ..write('nonce: $nonce, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('authenticationTag: $authenticationTag, ')
          ..write('authenticatedContext: $authenticatedContext, ')
          ..write('plaintextBytes: $plaintextBytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionIoMessagesTable extends ActionIoMessages
    with TableInfo<$ActionIoMessagesTable, ActionIoMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionIoMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _executionIdMeta = const VerificationMeta(
    'executionId',
  );
  @override
  late final GeneratedColumn<String> executionId = GeneratedColumn<String>(
    'execution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES action_io_sessions (execution_id)',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closesInputMeta = const VerificationMeta(
    'closesInput',
  );
  @override
  late final GeneratedColumn<bool> closesInput = GeneratedColumn<bool>(
    'closes_input',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("closes_input" IN (0, 1))',
    ),
  );
  static const VerificationMeta _deliveryStateMeta = const VerificationMeta(
    'deliveryState',
  );
  @override
  late final GeneratedColumn<String> deliveryState = GeneratedColumn<String>(
    'delivery_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmedBytesMeta = const VerificationMeta(
    'confirmedBytes',
  );
  @override
  late final GeneratedColumn<int> confirmedBytes = GeneratedColumn<int>(
    'confirmed_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inputBytesMeta = const VerificationMeta(
    'inputBytes',
  );
  @override
  late final GeneratedColumn<int> inputBytes = GeneratedColumn<int>(
    'input_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadIdMeta = const VerificationMeta(
    'payloadId',
  );
  @override
  late final GeneratedColumn<String> payloadId = GeneratedColumn<String>(
    'payload_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES action_io_payloads (payload_id)',
    ),
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _admittedAtMeta = const VerificationMeta(
    'admittedAt',
  );
  @override
  late final GeneratedColumn<DateTime> admittedAt = GeneratedColumn<DateTime>(
    'admitted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    executionId,
    messageId,
    sequence,
    fingerprint,
    closesInput,
    deliveryState,
    confirmedBytes,
    inputBytes,
    payloadId,
    failureCode,
    admittedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_io_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionIoMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('execution_id')) {
      context.handle(
        _executionIdMeta,
        executionId.isAcceptableOrUnknown(
          data['execution_id']!,
          _executionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_executionIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('closes_input')) {
      context.handle(
        _closesInputMeta,
        closesInput.isAcceptableOrUnknown(
          data['closes_input']!,
          _closesInputMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_closesInputMeta);
    }
    if (data.containsKey('delivery_state')) {
      context.handle(
        _deliveryStateMeta,
        deliveryState.isAcceptableOrUnknown(
          data['delivery_state']!,
          _deliveryStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deliveryStateMeta);
    }
    if (data.containsKey('confirmed_bytes')) {
      context.handle(
        _confirmedBytesMeta,
        confirmedBytes.isAcceptableOrUnknown(
          data['confirmed_bytes']!,
          _confirmedBytesMeta,
        ),
      );
    }
    if (data.containsKey('input_bytes')) {
      context.handle(
        _inputBytesMeta,
        inputBytes.isAcceptableOrUnknown(data['input_bytes']!, _inputBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_inputBytesMeta);
    }
    if (data.containsKey('payload_id')) {
      context.handle(
        _payloadIdMeta,
        payloadId.isAcceptableOrUnknown(data['payload_id']!, _payloadIdMeta),
      );
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    if (data.containsKey('admitted_at')) {
      context.handle(
        _admittedAtMeta,
        admittedAt.isAcceptableOrUnknown(data['admitted_at']!, _admittedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_admittedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {executionId, messageId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {executionId, sequence},
  ];
  @override
  ActionIoMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionIoMessage(
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      closesInput: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}closes_input'],
      )!,
      deliveryState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_state'],
      )!,
      confirmedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_bytes'],
      ),
      inputBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}input_bytes'],
      )!,
      payloadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_id'],
      ),
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      admittedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}admitted_at'],
      )!,
    );
  }

  @override
  $ActionIoMessagesTable createAlias(String alias) {
    return $ActionIoMessagesTable(attachedDatabase, alias);
  }
}

class ActionIoMessage extends DataClass implements Insertable<ActionIoMessage> {
  final String executionId;
  final String messageId;
  final int sequence;
  final String fingerprint;
  final bool closesInput;
  final String deliveryState;
  final int? confirmedBytes;
  final int inputBytes;
  final String? payloadId;
  final String? failureCode;
  final DateTime admittedAt;
  const ActionIoMessage({
    required this.executionId,
    required this.messageId,
    required this.sequence,
    required this.fingerprint,
    required this.closesInput,
    required this.deliveryState,
    this.confirmedBytes,
    required this.inputBytes,
    this.payloadId,
    this.failureCode,
    required this.admittedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['execution_id'] = Variable<String>(executionId);
    map['message_id'] = Variable<String>(messageId);
    map['sequence'] = Variable<int>(sequence);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['closes_input'] = Variable<bool>(closesInput);
    map['delivery_state'] = Variable<String>(deliveryState);
    if (!nullToAbsent || confirmedBytes != null) {
      map['confirmed_bytes'] = Variable<int>(confirmedBytes);
    }
    map['input_bytes'] = Variable<int>(inputBytes);
    if (!nullToAbsent || payloadId != null) {
      map['payload_id'] = Variable<String>(payloadId);
    }
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    map['admitted_at'] = Variable<DateTime>(admittedAt);
    return map;
  }

  ActionIoMessagesCompanion toCompanion(bool nullToAbsent) {
    return ActionIoMessagesCompanion(
      executionId: Value(executionId),
      messageId: Value(messageId),
      sequence: Value(sequence),
      fingerprint: Value(fingerprint),
      closesInput: Value(closesInput),
      deliveryState: Value(deliveryState),
      confirmedBytes: confirmedBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedBytes),
      inputBytes: Value(inputBytes),
      payloadId: payloadId == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadId),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      admittedAt: Value(admittedAt),
    );
  }

  factory ActionIoMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionIoMessage(
      executionId: serializer.fromJson<String>(json['executionId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      closesInput: serializer.fromJson<bool>(json['closesInput']),
      deliveryState: serializer.fromJson<String>(json['deliveryState']),
      confirmedBytes: serializer.fromJson<int?>(json['confirmedBytes']),
      inputBytes: serializer.fromJson<int>(json['inputBytes']),
      payloadId: serializer.fromJson<String?>(json['payloadId']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      admittedAt: serializer.fromJson<DateTime>(json['admittedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'executionId': serializer.toJson<String>(executionId),
      'messageId': serializer.toJson<String>(messageId),
      'sequence': serializer.toJson<int>(sequence),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'closesInput': serializer.toJson<bool>(closesInput),
      'deliveryState': serializer.toJson<String>(deliveryState),
      'confirmedBytes': serializer.toJson<int?>(confirmedBytes),
      'inputBytes': serializer.toJson<int>(inputBytes),
      'payloadId': serializer.toJson<String?>(payloadId),
      'failureCode': serializer.toJson<String?>(failureCode),
      'admittedAt': serializer.toJson<DateTime>(admittedAt),
    };
  }

  ActionIoMessage copyWith({
    String? executionId,
    String? messageId,
    int? sequence,
    String? fingerprint,
    bool? closesInput,
    String? deliveryState,
    Value<int?> confirmedBytes = const Value.absent(),
    int? inputBytes,
    Value<String?> payloadId = const Value.absent(),
    Value<String?> failureCode = const Value.absent(),
    DateTime? admittedAt,
  }) => ActionIoMessage(
    executionId: executionId ?? this.executionId,
    messageId: messageId ?? this.messageId,
    sequence: sequence ?? this.sequence,
    fingerprint: fingerprint ?? this.fingerprint,
    closesInput: closesInput ?? this.closesInput,
    deliveryState: deliveryState ?? this.deliveryState,
    confirmedBytes: confirmedBytes.present
        ? confirmedBytes.value
        : this.confirmedBytes,
    inputBytes: inputBytes ?? this.inputBytes,
    payloadId: payloadId.present ? payloadId.value : this.payloadId,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    admittedAt: admittedAt ?? this.admittedAt,
  );
  ActionIoMessage copyWithCompanion(ActionIoMessagesCompanion data) {
    return ActionIoMessage(
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      closesInput: data.closesInput.present
          ? data.closesInput.value
          : this.closesInput,
      deliveryState: data.deliveryState.present
          ? data.deliveryState.value
          : this.deliveryState,
      confirmedBytes: data.confirmedBytes.present
          ? data.confirmedBytes.value
          : this.confirmedBytes,
      inputBytes: data.inputBytes.present
          ? data.inputBytes.value
          : this.inputBytes,
      payloadId: data.payloadId.present ? data.payloadId.value : this.payloadId,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      admittedAt: data.admittedAt.present
          ? data.admittedAt.value
          : this.admittedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoMessage(')
          ..write('executionId: $executionId, ')
          ..write('messageId: $messageId, ')
          ..write('sequence: $sequence, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('closesInput: $closesInput, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('confirmedBytes: $confirmedBytes, ')
          ..write('inputBytes: $inputBytes, ')
          ..write('payloadId: $payloadId, ')
          ..write('failureCode: $failureCode, ')
          ..write('admittedAt: $admittedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    executionId,
    messageId,
    sequence,
    fingerprint,
    closesInput,
    deliveryState,
    confirmedBytes,
    inputBytes,
    payloadId,
    failureCode,
    admittedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionIoMessage &&
          other.executionId == this.executionId &&
          other.messageId == this.messageId &&
          other.sequence == this.sequence &&
          other.fingerprint == this.fingerprint &&
          other.closesInput == this.closesInput &&
          other.deliveryState == this.deliveryState &&
          other.confirmedBytes == this.confirmedBytes &&
          other.inputBytes == this.inputBytes &&
          other.payloadId == this.payloadId &&
          other.failureCode == this.failureCode &&
          other.admittedAt == this.admittedAt);
}

class ActionIoMessagesCompanion extends UpdateCompanion<ActionIoMessage> {
  final Value<String> executionId;
  final Value<String> messageId;
  final Value<int> sequence;
  final Value<String> fingerprint;
  final Value<bool> closesInput;
  final Value<String> deliveryState;
  final Value<int?> confirmedBytes;
  final Value<int> inputBytes;
  final Value<String?> payloadId;
  final Value<String?> failureCode;
  final Value<DateTime> admittedAt;
  final Value<int> rowid;
  const ActionIoMessagesCompanion({
    this.executionId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.closesInput = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.confirmedBytes = const Value.absent(),
    this.inputBytes = const Value.absent(),
    this.payloadId = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.admittedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionIoMessagesCompanion.insert({
    required String executionId,
    required String messageId,
    required int sequence,
    required String fingerprint,
    required bool closesInput,
    required String deliveryState,
    this.confirmedBytes = const Value.absent(),
    required int inputBytes,
    this.payloadId = const Value.absent(),
    this.failureCode = const Value.absent(),
    required DateTime admittedAt,
    this.rowid = const Value.absent(),
  }) : executionId = Value(executionId),
       messageId = Value(messageId),
       sequence = Value(sequence),
       fingerprint = Value(fingerprint),
       closesInput = Value(closesInput),
       deliveryState = Value(deliveryState),
       inputBytes = Value(inputBytes),
       admittedAt = Value(admittedAt);
  static Insertable<ActionIoMessage> custom({
    Expression<String>? executionId,
    Expression<String>? messageId,
    Expression<int>? sequence,
    Expression<String>? fingerprint,
    Expression<bool>? closesInput,
    Expression<String>? deliveryState,
    Expression<int>? confirmedBytes,
    Expression<int>? inputBytes,
    Expression<String>? payloadId,
    Expression<String>? failureCode,
    Expression<DateTime>? admittedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (executionId != null) 'execution_id': executionId,
      if (messageId != null) 'message_id': messageId,
      if (sequence != null) 'sequence': sequence,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (closesInput != null) 'closes_input': closesInput,
      if (deliveryState != null) 'delivery_state': deliveryState,
      if (confirmedBytes != null) 'confirmed_bytes': confirmedBytes,
      if (inputBytes != null) 'input_bytes': inputBytes,
      if (payloadId != null) 'payload_id': payloadId,
      if (failureCode != null) 'failure_code': failureCode,
      if (admittedAt != null) 'admitted_at': admittedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionIoMessagesCompanion copyWith({
    Value<String>? executionId,
    Value<String>? messageId,
    Value<int>? sequence,
    Value<String>? fingerprint,
    Value<bool>? closesInput,
    Value<String>? deliveryState,
    Value<int?>? confirmedBytes,
    Value<int>? inputBytes,
    Value<String?>? payloadId,
    Value<String?>? failureCode,
    Value<DateTime>? admittedAt,
    Value<int>? rowid,
  }) {
    return ActionIoMessagesCompanion(
      executionId: executionId ?? this.executionId,
      messageId: messageId ?? this.messageId,
      sequence: sequence ?? this.sequence,
      fingerprint: fingerprint ?? this.fingerprint,
      closesInput: closesInput ?? this.closesInput,
      deliveryState: deliveryState ?? this.deliveryState,
      confirmedBytes: confirmedBytes ?? this.confirmedBytes,
      inputBytes: inputBytes ?? this.inputBytes,
      payloadId: payloadId ?? this.payloadId,
      failureCode: failureCode ?? this.failureCode,
      admittedAt: admittedAt ?? this.admittedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (closesInput.present) {
      map['closes_input'] = Variable<bool>(closesInput.value);
    }
    if (deliveryState.present) {
      map['delivery_state'] = Variable<String>(deliveryState.value);
    }
    if (confirmedBytes.present) {
      map['confirmed_bytes'] = Variable<int>(confirmedBytes.value);
    }
    if (inputBytes.present) {
      map['input_bytes'] = Variable<int>(inputBytes.value);
    }
    if (payloadId.present) {
      map['payload_id'] = Variable<String>(payloadId.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (admittedAt.present) {
      map['admitted_at'] = Variable<DateTime>(admittedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoMessagesCompanion(')
          ..write('executionId: $executionId, ')
          ..write('messageId: $messageId, ')
          ..write('sequence: $sequence, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('closesInput: $closesInput, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('confirmedBytes: $confirmedBytes, ')
          ..write('inputBytes: $inputBytes, ')
          ..write('payloadId: $payloadId, ')
          ..write('failureCode: $failureCode, ')
          ..write('admittedAt: $admittedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionIoEventsTable extends ActionIoEvents
    with TableInfo<$ActionIoEventsTable, ActionIoEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionIoEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _executionIdMeta = const VerificationMeta(
    'executionId',
  );
  @override
  late final GeneratedColumn<String> executionId = GeneratedColumn<String>(
    'execution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES action_io_sessions (execution_id)',
    ),
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streamMeta = const VerificationMeta('stream');
  @override
  late final GeneratedColumn<String> stream = GeneratedColumn<String>(
    'stream',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteOffsetMeta = const VerificationMeta(
    'byteOffset',
  );
  @override
  late final GeneratedColumn<int> byteOffset = GeneratedColumn<int>(
    'byte_offset',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadIdMeta = const VerificationMeta(
    'payloadId',
  );
  @override
  late final GeneratedColumn<String> payloadId = GeneratedColumn<String>(
    'payload_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES action_io_payloads (payload_id)',
    ),
  );
  static const VerificationMeta _exitCodeMeta = const VerificationMeta(
    'exitCode',
  );
  @override
  late final GeneratedColumn<int> exitCode = GeneratedColumn<int>(
    'exit_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outputCompleteMeta = const VerificationMeta(
    'outputComplete',
  );
  @override
  late final GeneratedColumn<bool> outputComplete = GeneratedColumn<bool>(
    'output_complete',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("output_complete" IN (0, 1))',
    ),
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    executionId,
    sequence,
    eventType,
    stream,
    byteOffset,
    payloadId,
    exitCode,
    outputComplete,
    failureCode,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_io_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionIoEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('execution_id')) {
      context.handle(
        _executionIdMeta,
        executionId.isAcceptableOrUnknown(
          data['execution_id']!,
          _executionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_executionIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('stream')) {
      context.handle(
        _streamMeta,
        stream.isAcceptableOrUnknown(data['stream']!, _streamMeta),
      );
    }
    if (data.containsKey('byte_offset')) {
      context.handle(
        _byteOffsetMeta,
        byteOffset.isAcceptableOrUnknown(data['byte_offset']!, _byteOffsetMeta),
      );
    }
    if (data.containsKey('payload_id')) {
      context.handle(
        _payloadIdMeta,
        payloadId.isAcceptableOrUnknown(data['payload_id']!, _payloadIdMeta),
      );
    }
    if (data.containsKey('exit_code')) {
      context.handle(
        _exitCodeMeta,
        exitCode.isAcceptableOrUnknown(data['exit_code']!, _exitCodeMeta),
      );
    }
    if (data.containsKey('output_complete')) {
      context.handle(
        _outputCompleteMeta,
        outputComplete.isAcceptableOrUnknown(
          data['output_complete']!,
          _outputCompleteMeta,
        ),
      );
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {executionId, sequence};
  @override
  ActionIoEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionIoEvent(
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      stream: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream'],
      ),
      byteOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_offset'],
      ),
      payloadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_id'],
      ),
      exitCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exit_code'],
      ),
      outputComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}output_complete'],
      ),
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ActionIoEventsTable createAlias(String alias) {
    return $ActionIoEventsTable(attachedDatabase, alias);
  }
}

class ActionIoEvent extends DataClass implements Insertable<ActionIoEvent> {
  final String executionId;
  final int sequence;
  final String eventType;
  final String? stream;
  final int? byteOffset;
  final String? payloadId;
  final int? exitCode;
  final bool? outputComplete;
  final String? failureCode;
  final DateTime createdAt;
  const ActionIoEvent({
    required this.executionId,
    required this.sequence,
    required this.eventType,
    this.stream,
    this.byteOffset,
    this.payloadId,
    this.exitCode,
    this.outputComplete,
    this.failureCode,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['execution_id'] = Variable<String>(executionId);
    map['sequence'] = Variable<int>(sequence);
    map['event_type'] = Variable<String>(eventType);
    if (!nullToAbsent || stream != null) {
      map['stream'] = Variable<String>(stream);
    }
    if (!nullToAbsent || byteOffset != null) {
      map['byte_offset'] = Variable<int>(byteOffset);
    }
    if (!nullToAbsent || payloadId != null) {
      map['payload_id'] = Variable<String>(payloadId);
    }
    if (!nullToAbsent || exitCode != null) {
      map['exit_code'] = Variable<int>(exitCode);
    }
    if (!nullToAbsent || outputComplete != null) {
      map['output_complete'] = Variable<bool>(outputComplete);
    }
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ActionIoEventsCompanion toCompanion(bool nullToAbsent) {
    return ActionIoEventsCompanion(
      executionId: Value(executionId),
      sequence: Value(sequence),
      eventType: Value(eventType),
      stream: stream == null && nullToAbsent
          ? const Value.absent()
          : Value(stream),
      byteOffset: byteOffset == null && nullToAbsent
          ? const Value.absent()
          : Value(byteOffset),
      payloadId: payloadId == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadId),
      exitCode: exitCode == null && nullToAbsent
          ? const Value.absent()
          : Value(exitCode),
      outputComplete: outputComplete == null && nullToAbsent
          ? const Value.absent()
          : Value(outputComplete),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      createdAt: Value(createdAt),
    );
  }

  factory ActionIoEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionIoEvent(
      executionId: serializer.fromJson<String>(json['executionId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      eventType: serializer.fromJson<String>(json['eventType']),
      stream: serializer.fromJson<String?>(json['stream']),
      byteOffset: serializer.fromJson<int?>(json['byteOffset']),
      payloadId: serializer.fromJson<String?>(json['payloadId']),
      exitCode: serializer.fromJson<int?>(json['exitCode']),
      outputComplete: serializer.fromJson<bool?>(json['outputComplete']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'executionId': serializer.toJson<String>(executionId),
      'sequence': serializer.toJson<int>(sequence),
      'eventType': serializer.toJson<String>(eventType),
      'stream': serializer.toJson<String?>(stream),
      'byteOffset': serializer.toJson<int?>(byteOffset),
      'payloadId': serializer.toJson<String?>(payloadId),
      'exitCode': serializer.toJson<int?>(exitCode),
      'outputComplete': serializer.toJson<bool?>(outputComplete),
      'failureCode': serializer.toJson<String?>(failureCode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ActionIoEvent copyWith({
    String? executionId,
    int? sequence,
    String? eventType,
    Value<String?> stream = const Value.absent(),
    Value<int?> byteOffset = const Value.absent(),
    Value<String?> payloadId = const Value.absent(),
    Value<int?> exitCode = const Value.absent(),
    Value<bool?> outputComplete = const Value.absent(),
    Value<String?> failureCode = const Value.absent(),
    DateTime? createdAt,
  }) => ActionIoEvent(
    executionId: executionId ?? this.executionId,
    sequence: sequence ?? this.sequence,
    eventType: eventType ?? this.eventType,
    stream: stream.present ? stream.value : this.stream,
    byteOffset: byteOffset.present ? byteOffset.value : this.byteOffset,
    payloadId: payloadId.present ? payloadId.value : this.payloadId,
    exitCode: exitCode.present ? exitCode.value : this.exitCode,
    outputComplete: outputComplete.present
        ? outputComplete.value
        : this.outputComplete,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    createdAt: createdAt ?? this.createdAt,
  );
  ActionIoEvent copyWithCompanion(ActionIoEventsCompanion data) {
    return ActionIoEvent(
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      stream: data.stream.present ? data.stream.value : this.stream,
      byteOffset: data.byteOffset.present
          ? data.byteOffset.value
          : this.byteOffset,
      payloadId: data.payloadId.present ? data.payloadId.value : this.payloadId,
      exitCode: data.exitCode.present ? data.exitCode.value : this.exitCode,
      outputComplete: data.outputComplete.present
          ? data.outputComplete.value
          : this.outputComplete,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoEvent(')
          ..write('executionId: $executionId, ')
          ..write('sequence: $sequence, ')
          ..write('eventType: $eventType, ')
          ..write('stream: $stream, ')
          ..write('byteOffset: $byteOffset, ')
          ..write('payloadId: $payloadId, ')
          ..write('exitCode: $exitCode, ')
          ..write('outputComplete: $outputComplete, ')
          ..write('failureCode: $failureCode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    executionId,
    sequence,
    eventType,
    stream,
    byteOffset,
    payloadId,
    exitCode,
    outputComplete,
    failureCode,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionIoEvent &&
          other.executionId == this.executionId &&
          other.sequence == this.sequence &&
          other.eventType == this.eventType &&
          other.stream == this.stream &&
          other.byteOffset == this.byteOffset &&
          other.payloadId == this.payloadId &&
          other.exitCode == this.exitCode &&
          other.outputComplete == this.outputComplete &&
          other.failureCode == this.failureCode &&
          other.createdAt == this.createdAt);
}

class ActionIoEventsCompanion extends UpdateCompanion<ActionIoEvent> {
  final Value<String> executionId;
  final Value<int> sequence;
  final Value<String> eventType;
  final Value<String?> stream;
  final Value<int?> byteOffset;
  final Value<String?> payloadId;
  final Value<int?> exitCode;
  final Value<bool?> outputComplete;
  final Value<String?> failureCode;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ActionIoEventsCompanion({
    this.executionId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.eventType = const Value.absent(),
    this.stream = const Value.absent(),
    this.byteOffset = const Value.absent(),
    this.payloadId = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.outputComplete = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionIoEventsCompanion.insert({
    required String executionId,
    required int sequence,
    required String eventType,
    this.stream = const Value.absent(),
    this.byteOffset = const Value.absent(),
    this.payloadId = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.outputComplete = const Value.absent(),
    this.failureCode = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : executionId = Value(executionId),
       sequence = Value(sequence),
       eventType = Value(eventType),
       createdAt = Value(createdAt);
  static Insertable<ActionIoEvent> custom({
    Expression<String>? executionId,
    Expression<int>? sequence,
    Expression<String>? eventType,
    Expression<String>? stream,
    Expression<int>? byteOffset,
    Expression<String>? payloadId,
    Expression<int>? exitCode,
    Expression<bool>? outputComplete,
    Expression<String>? failureCode,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (executionId != null) 'execution_id': executionId,
      if (sequence != null) 'sequence': sequence,
      if (eventType != null) 'event_type': eventType,
      if (stream != null) 'stream': stream,
      if (byteOffset != null) 'byte_offset': byteOffset,
      if (payloadId != null) 'payload_id': payloadId,
      if (exitCode != null) 'exit_code': exitCode,
      if (outputComplete != null) 'output_complete': outputComplete,
      if (failureCode != null) 'failure_code': failureCode,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionIoEventsCompanion copyWith({
    Value<String>? executionId,
    Value<int>? sequence,
    Value<String>? eventType,
    Value<String?>? stream,
    Value<int?>? byteOffset,
    Value<String?>? payloadId,
    Value<int?>? exitCode,
    Value<bool?>? outputComplete,
    Value<String?>? failureCode,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ActionIoEventsCompanion(
      executionId: executionId ?? this.executionId,
      sequence: sequence ?? this.sequence,
      eventType: eventType ?? this.eventType,
      stream: stream ?? this.stream,
      byteOffset: byteOffset ?? this.byteOffset,
      payloadId: payloadId ?? this.payloadId,
      exitCode: exitCode ?? this.exitCode,
      outputComplete: outputComplete ?? this.outputComplete,
      failureCode: failureCode ?? this.failureCode,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (stream.present) {
      map['stream'] = Variable<String>(stream.value);
    }
    if (byteOffset.present) {
      map['byte_offset'] = Variable<int>(byteOffset.value);
    }
    if (payloadId.present) {
      map['payload_id'] = Variable<String>(payloadId.value);
    }
    if (exitCode.present) {
      map['exit_code'] = Variable<int>(exitCode.value);
    }
    if (outputComplete.present) {
      map['output_complete'] = Variable<bool>(outputComplete.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionIoEventsCompanion(')
          ..write('executionId: $executionId, ')
          ..write('sequence: $sequence, ')
          ..write('eventType: $eventType, ')
          ..write('stream: $stream, ')
          ..write('byteOffset: $byteOffset, ')
          ..write('payloadId: $payloadId, ')
          ..write('exitCode: $exitCode, ')
          ..write('outputComplete: $outputComplete, ')
          ..write('failureCode: $failureCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ActionIoJournalDatabase extends GeneratedDatabase {
  _$ActionIoJournalDatabase(QueryExecutor e) : super(e);
  $ActionIoJournalDatabaseManager get managers =>
      $ActionIoJournalDatabaseManager(this);
  late final $ActionIoSessionsTable actionIoSessions = $ActionIoSessionsTable(
    this,
  );
  late final $ActionIoPayloadsTable actionIoPayloads = $ActionIoPayloadsTable(
    this,
  );
  late final $ActionIoMessagesTable actionIoMessages = $ActionIoMessagesTable(
    this,
  );
  late final $ActionIoEventsTable actionIoEvents = $ActionIoEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    actionIoSessions,
    actionIoPayloads,
    actionIoMessages,
    actionIoEvents,
  ];
}

typedef $$ActionIoSessionsTableCreateCompanionBuilder =
    ActionIoSessionsCompanion Function({
      required String executionId,
      required String installationId,
      required String agentId,
      required String clientId,
      required String actionId,
      required String idempotencyKey,
      required String fingerprint,
      required String triggerId,
      Value<String?> actionType,
      required String definitionHash,
      required String processState,
      required String stdinState,
      required String captureState,
      Value<int> nextInputSequence,
      Value<int> nextEventSequence,
      Value<int> admittedInputBytes,
      Value<int> stdoutBytes,
      Value<int> stderrBytes,
      Value<int> queuedInputBytes,
      Value<int> queuedInputMessages,
      Value<int?> exitCode,
      Value<String?> failureCode,
      Value<String?> diagnosticId,
      required DateTime createdAt,
      Value<DateTime?> terminalAt,
      Value<DateTime?> outputExpiresAt,
      Value<DateTime?> dedupeExpiresAt,
      Value<bool> outputExpired,
      Value<int> rowid,
    });
typedef $$ActionIoSessionsTableUpdateCompanionBuilder =
    ActionIoSessionsCompanion Function({
      Value<String> executionId,
      Value<String> installationId,
      Value<String> agentId,
      Value<String> clientId,
      Value<String> actionId,
      Value<String> idempotencyKey,
      Value<String> fingerprint,
      Value<String> triggerId,
      Value<String?> actionType,
      Value<String> definitionHash,
      Value<String> processState,
      Value<String> stdinState,
      Value<String> captureState,
      Value<int> nextInputSequence,
      Value<int> nextEventSequence,
      Value<int> admittedInputBytes,
      Value<int> stdoutBytes,
      Value<int> stderrBytes,
      Value<int> queuedInputBytes,
      Value<int> queuedInputMessages,
      Value<int?> exitCode,
      Value<String?> failureCode,
      Value<String?> diagnosticId,
      Value<DateTime> createdAt,
      Value<DateTime?> terminalAt,
      Value<DateTime?> outputExpiresAt,
      Value<DateTime?> dedupeExpiresAt,
      Value<bool> outputExpired,
      Value<int> rowid,
    });

final class $$ActionIoSessionsTableReferences
    extends
        BaseReferences<
          _$ActionIoJournalDatabase,
          $ActionIoSessionsTable,
          ActionIoSession
        > {
  $$ActionIoSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ActionIoPayloadsTable, List<ActionIoPayload>>
  _actionIoPayloadsRefsTable(
    _$ActionIoJournalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.actionIoPayloads,
    aliasName:
        'action_io_sessions__execution_id__action_io_payloads__execution_id',
  );

  $$ActionIoPayloadsTableProcessedTableManager get actionIoPayloadsRefs {
    final manager =
        $$ActionIoPayloadsTableTableManager($_db, $_db.actionIoPayloads).filter(
          (f) => f.executionId.executionId.sqlEquals(
            $_itemColumn<String>('execution_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _actionIoPayloadsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ActionIoMessagesTable, List<ActionIoMessage>>
  _actionIoMessagesRefsTable(
    _$ActionIoJournalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.actionIoMessages,
    aliasName:
        'action_io_sessions__execution_id__action_io_messages__execution_id',
  );

  $$ActionIoMessagesTableProcessedTableManager get actionIoMessagesRefs {
    final manager =
        $$ActionIoMessagesTableTableManager($_db, $_db.actionIoMessages).filter(
          (f) => f.executionId.executionId.sqlEquals(
            $_itemColumn<String>('execution_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _actionIoMessagesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ActionIoEventsTable, List<ActionIoEvent>>
  _actionIoEventsRefsTable(_$ActionIoJournalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionIoEvents,
        aliasName:
            'action_io_sessions__execution_id__action_io_events__execution_id',
      );

  $$ActionIoEventsTableProcessedTableManager get actionIoEventsRefs {
    final manager = $$ActionIoEventsTableTableManager($_db, $_db.actionIoEvents)
        .filter(
          (f) => f.executionId.executionId.sqlEquals(
            $_itemColumn<String>('execution_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_actionIoEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActionIoSessionsTableFilterComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoSessionsTable> {
  $$ActionIoSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get installationId => $composableBuilder(
    column: $table.installationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerId => $composableBuilder(
    column: $table.triggerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get definitionHash => $composableBuilder(
    column: $table.definitionHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processState => $composableBuilder(
    column: $table.processState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stdinState => $composableBuilder(
    column: $table.stdinState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get captureState => $composableBuilder(
    column: $table.captureState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextInputSequence => $composableBuilder(
    column: $table.nextInputSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextEventSequence => $composableBuilder(
    column: $table.nextEventSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get admittedInputBytes => $composableBuilder(
    column: $table.admittedInputBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stdoutBytes => $composableBuilder(
    column: $table.stdoutBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stderrBytes => $composableBuilder(
    column: $table.stderrBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queuedInputBytes => $composableBuilder(
    column: $table.queuedInputBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queuedInputMessages => $composableBuilder(
    column: $table.queuedInputMessages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get diagnosticId => $composableBuilder(
    column: $table.diagnosticId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get terminalAt => $composableBuilder(
    column: $table.terminalAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get outputExpiresAt => $composableBuilder(
    column: $table.outputExpiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dedupeExpiresAt => $composableBuilder(
    column: $table.dedupeExpiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get outputExpired => $composableBuilder(
    column: $table.outputExpired,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> actionIoPayloadsRefs(
    Expression<bool> Function($$ActionIoPayloadsTableFilterComposer f) f,
  ) {
    final $$ActionIoPayloadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> actionIoMessagesRefs(
    Expression<bool> Function($$ActionIoMessagesTableFilterComposer f) f,
  ) {
    final $$ActionIoMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoMessages,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoMessagesTableFilterComposer(
            $db: $db,
            $table: $db.actionIoMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> actionIoEventsRefs(
    Expression<bool> Function($$ActionIoEventsTableFilterComposer f) f,
  ) {
    final $$ActionIoEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoEvents,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoEventsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionIoSessionsTableOrderingComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoSessionsTable> {
  $$ActionIoSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get installationId => $composableBuilder(
    column: $table.installationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerId => $composableBuilder(
    column: $table.triggerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get definitionHash => $composableBuilder(
    column: $table.definitionHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processState => $composableBuilder(
    column: $table.processState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stdinState => $composableBuilder(
    column: $table.stdinState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get captureState => $composableBuilder(
    column: $table.captureState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextInputSequence => $composableBuilder(
    column: $table.nextInputSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextEventSequence => $composableBuilder(
    column: $table.nextEventSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get admittedInputBytes => $composableBuilder(
    column: $table.admittedInputBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stdoutBytes => $composableBuilder(
    column: $table.stdoutBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stderrBytes => $composableBuilder(
    column: $table.stderrBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queuedInputBytes => $composableBuilder(
    column: $table.queuedInputBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queuedInputMessages => $composableBuilder(
    column: $table.queuedInputMessages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get diagnosticId => $composableBuilder(
    column: $table.diagnosticId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get terminalAt => $composableBuilder(
    column: $table.terminalAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get outputExpiresAt => $composableBuilder(
    column: $table.outputExpiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dedupeExpiresAt => $composableBuilder(
    column: $table.dedupeExpiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get outputExpired => $composableBuilder(
    column: $table.outputExpired,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActionIoSessionsTableAnnotationComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoSessionsTable> {
  $$ActionIoSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get installationId => $composableBuilder(
    column: $table.installationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get actionId =>
      $composableBuilder(column: $table.actionId, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get triggerId =>
      $composableBuilder(column: $table.triggerId, builder: (column) => column);

  GeneratedColumn<String> get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get definitionHash => $composableBuilder(
    column: $table.definitionHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processState => $composableBuilder(
    column: $table.processState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stdinState => $composableBuilder(
    column: $table.stdinState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get captureState => $composableBuilder(
    column: $table.captureState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextInputSequence => $composableBuilder(
    column: $table.nextInputSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextEventSequence => $composableBuilder(
    column: $table.nextEventSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get admittedInputBytes => $composableBuilder(
    column: $table.admittedInputBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stdoutBytes => $composableBuilder(
    column: $table.stdoutBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stderrBytes => $composableBuilder(
    column: $table.stderrBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queuedInputBytes => $composableBuilder(
    column: $table.queuedInputBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queuedInputMessages => $composableBuilder(
    column: $table.queuedInputMessages,
    builder: (column) => column,
  );

  GeneratedColumn<int> get exitCode =>
      $composableBuilder(column: $table.exitCode, builder: (column) => column);

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get diagnosticId => $composableBuilder(
    column: $table.diagnosticId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get terminalAt => $composableBuilder(
    column: $table.terminalAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get outputExpiresAt => $composableBuilder(
    column: $table.outputExpiresAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dedupeExpiresAt => $composableBuilder(
    column: $table.dedupeExpiresAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get outputExpired => $composableBuilder(
    column: $table.outputExpired,
    builder: (column) => column,
  );

  Expression<T> actionIoPayloadsRefs<T extends Object>(
    Expression<T> Function($$ActionIoPayloadsTableAnnotationComposer a) f,
  ) {
    final $$ActionIoPayloadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> actionIoMessagesRefs<T extends Object>(
    Expression<T> Function($$ActionIoMessagesTableAnnotationComposer a) f,
  ) {
    final $$ActionIoMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoMessages,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> actionIoEventsRefs<T extends Object>(
    Expression<T> Function($$ActionIoEventsTableAnnotationComposer a) f,
  ) {
    final $$ActionIoEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoEvents,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionIoSessionsTableTableManager
    extends
        RootTableManager<
          _$ActionIoJournalDatabase,
          $ActionIoSessionsTable,
          ActionIoSession,
          $$ActionIoSessionsTableFilterComposer,
          $$ActionIoSessionsTableOrderingComposer,
          $$ActionIoSessionsTableAnnotationComposer,
          $$ActionIoSessionsTableCreateCompanionBuilder,
          $$ActionIoSessionsTableUpdateCompanionBuilder,
          (ActionIoSession, $$ActionIoSessionsTableReferences),
          ActionIoSession,
          PrefetchHooks Function({
            bool actionIoPayloadsRefs,
            bool actionIoMessagesRefs,
            bool actionIoEventsRefs,
          })
        > {
  $$ActionIoSessionsTableTableManager(
    _$ActionIoJournalDatabase db,
    $ActionIoSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionIoSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionIoSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionIoSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> executionId = const Value.absent(),
                Value<String> installationId = const Value.absent(),
                Value<String> agentId = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> actionId = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String> triggerId = const Value.absent(),
                Value<String?> actionType = const Value.absent(),
                Value<String> definitionHash = const Value.absent(),
                Value<String> processState = const Value.absent(),
                Value<String> stdinState = const Value.absent(),
                Value<String> captureState = const Value.absent(),
                Value<int> nextInputSequence = const Value.absent(),
                Value<int> nextEventSequence = const Value.absent(),
                Value<int> admittedInputBytes = const Value.absent(),
                Value<int> stdoutBytes = const Value.absent(),
                Value<int> stderrBytes = const Value.absent(),
                Value<int> queuedInputBytes = const Value.absent(),
                Value<int> queuedInputMessages = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> diagnosticId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> terminalAt = const Value.absent(),
                Value<DateTime?> outputExpiresAt = const Value.absent(),
                Value<DateTime?> dedupeExpiresAt = const Value.absent(),
                Value<bool> outputExpired = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionIoSessionsCompanion(
                executionId: executionId,
                installationId: installationId,
                agentId: agentId,
                clientId: clientId,
                actionId: actionId,
                idempotencyKey: idempotencyKey,
                fingerprint: fingerprint,
                triggerId: triggerId,
                actionType: actionType,
                definitionHash: definitionHash,
                processState: processState,
                stdinState: stdinState,
                captureState: captureState,
                nextInputSequence: nextInputSequence,
                nextEventSequence: nextEventSequence,
                admittedInputBytes: admittedInputBytes,
                stdoutBytes: stdoutBytes,
                stderrBytes: stderrBytes,
                queuedInputBytes: queuedInputBytes,
                queuedInputMessages: queuedInputMessages,
                exitCode: exitCode,
                failureCode: failureCode,
                diagnosticId: diagnosticId,
                createdAt: createdAt,
                terminalAt: terminalAt,
                outputExpiresAt: outputExpiresAt,
                dedupeExpiresAt: dedupeExpiresAt,
                outputExpired: outputExpired,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String executionId,
                required String installationId,
                required String agentId,
                required String clientId,
                required String actionId,
                required String idempotencyKey,
                required String fingerprint,
                required String triggerId,
                Value<String?> actionType = const Value.absent(),
                required String definitionHash,
                required String processState,
                required String stdinState,
                required String captureState,
                Value<int> nextInputSequence = const Value.absent(),
                Value<int> nextEventSequence = const Value.absent(),
                Value<int> admittedInputBytes = const Value.absent(),
                Value<int> stdoutBytes = const Value.absent(),
                Value<int> stderrBytes = const Value.absent(),
                Value<int> queuedInputBytes = const Value.absent(),
                Value<int> queuedInputMessages = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> diagnosticId = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> terminalAt = const Value.absent(),
                Value<DateTime?> outputExpiresAt = const Value.absent(),
                Value<DateTime?> dedupeExpiresAt = const Value.absent(),
                Value<bool> outputExpired = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionIoSessionsCompanion.insert(
                executionId: executionId,
                installationId: installationId,
                agentId: agentId,
                clientId: clientId,
                actionId: actionId,
                idempotencyKey: idempotencyKey,
                fingerprint: fingerprint,
                triggerId: triggerId,
                actionType: actionType,
                definitionHash: definitionHash,
                processState: processState,
                stdinState: stdinState,
                captureState: captureState,
                nextInputSequence: nextInputSequence,
                nextEventSequence: nextEventSequence,
                admittedInputBytes: admittedInputBytes,
                stdoutBytes: stdoutBytes,
                stderrBytes: stderrBytes,
                queuedInputBytes: queuedInputBytes,
                queuedInputMessages: queuedInputMessages,
                exitCode: exitCode,
                failureCode: failureCode,
                diagnosticId: diagnosticId,
                createdAt: createdAt,
                terminalAt: terminalAt,
                outputExpiresAt: outputExpiresAt,
                dedupeExpiresAt: dedupeExpiresAt,
                outputExpired: outputExpired,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionIoSessionsTable, ActionIoSession>(table),
                  $$ActionIoSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                actionIoPayloadsRefs = false,
                actionIoMessagesRefs = false,
                actionIoEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (actionIoPayloadsRefs) db.actionIoPayloads,
                    if (actionIoMessagesRefs) db.actionIoMessages,
                    if (actionIoEventsRefs) db.actionIoEvents,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (actionIoPayloadsRefs)
                        await $_getPrefetchedData<
                          ActionIoSession,
                          $ActionIoSessionsTable,
                          ActionIoPayload
                        >(
                          currentTable: table,
                          referencedTable: $$ActionIoSessionsTableReferences
                              ._actionIoPayloadsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionIoSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).actionIoPayloadsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.executionId == item.executionId,
                              ),
                          typedResults: items,
                        ),
                      if (actionIoMessagesRefs)
                        await $_getPrefetchedData<
                          ActionIoSession,
                          $ActionIoSessionsTable,
                          ActionIoMessage
                        >(
                          currentTable: table,
                          referencedTable: $$ActionIoSessionsTableReferences
                              ._actionIoMessagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionIoSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).actionIoMessagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.executionId == item.executionId,
                              ),
                          typedResults: items,
                        ),
                      if (actionIoEventsRefs)
                        await $_getPrefetchedData<
                          ActionIoSession,
                          $ActionIoSessionsTable,
                          ActionIoEvent
                        >(
                          currentTable: table,
                          referencedTable: $$ActionIoSessionsTableReferences
                              ._actionIoEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionIoSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).actionIoEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.executionId == item.executionId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ActionIoSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$ActionIoJournalDatabase,
      $ActionIoSessionsTable,
      ActionIoSession,
      $$ActionIoSessionsTableFilterComposer,
      $$ActionIoSessionsTableOrderingComposer,
      $$ActionIoSessionsTableAnnotationComposer,
      $$ActionIoSessionsTableCreateCompanionBuilder,
      $$ActionIoSessionsTableUpdateCompanionBuilder,
      (ActionIoSession, $$ActionIoSessionsTableReferences),
      ActionIoSession,
      PrefetchHooks Function({
        bool actionIoPayloadsRefs,
        bool actionIoMessagesRefs,
        bool actionIoEventsRefs,
      })
    >;
typedef $$ActionIoPayloadsTableCreateCompanionBuilder =
    ActionIoPayloadsCompanion Function({
      required String payloadId,
      required String executionId,
      required String keyId,
      required Uint8List nonce,
      required Uint8List ciphertext,
      required Uint8List authenticationTag,
      required Uint8List authenticatedContext,
      required int plaintextBytes,
      Value<int> rowid,
    });
typedef $$ActionIoPayloadsTableUpdateCompanionBuilder =
    ActionIoPayloadsCompanion Function({
      Value<String> payloadId,
      Value<String> executionId,
      Value<String> keyId,
      Value<Uint8List> nonce,
      Value<Uint8List> ciphertext,
      Value<Uint8List> authenticationTag,
      Value<Uint8List> authenticatedContext,
      Value<int> plaintextBytes,
      Value<int> rowid,
    });

final class $$ActionIoPayloadsTableReferences
    extends
        BaseReferences<
          _$ActionIoJournalDatabase,
          $ActionIoPayloadsTable,
          ActionIoPayload
        > {
  $$ActionIoPayloadsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActionIoSessionsTable _executionIdTable(
    _$ActionIoJournalDatabase db,
  ) => db.actionIoSessions.createAlias(
    'action_io_payloads__execution_id__action_io_sessions__execution_id',
  );

  $$ActionIoSessionsTableProcessedTableManager get executionId {
    final $_column = $_itemColumn<String>('execution_id')!;

    final manager = $$ActionIoSessionsTableTableManager(
      $_db,
      $_db.actionIoSessions,
    ).filter((f) => f.executionId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_executionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ActionIoMessagesTable, List<ActionIoMessage>>
  _actionIoMessagesRefsTable(_$ActionIoJournalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionIoMessages,
        aliasName:
            'action_io_payloads__payload_id__action_io_messages__payload_id',
      );

  $$ActionIoMessagesTableProcessedTableManager get actionIoMessagesRefs {
    final manager =
        $$ActionIoMessagesTableTableManager($_db, $_db.actionIoMessages).filter(
          (f) => f.payloadId.payloadId.sqlEquals(
            $_itemColumn<String>('payload_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _actionIoMessagesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ActionIoEventsTable, List<ActionIoEvent>>
  _actionIoEventsRefsTable(_$ActionIoJournalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionIoEvents,
        aliasName:
            'action_io_payloads__payload_id__action_io_events__payload_id',
      );

  $$ActionIoEventsTableProcessedTableManager get actionIoEventsRefs {
    final manager = $$ActionIoEventsTableTableManager($_db, $_db.actionIoEvents)
        .filter(
          (f) => f.payloadId.payloadId.sqlEquals(
            $_itemColumn<String>('payload_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_actionIoEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActionIoPayloadsTableFilterComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoPayloadsTable> {
  $$ActionIoPayloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get payloadId => $composableBuilder(
    column: $table.payloadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get authenticationTag => $composableBuilder(
    column: $table.authenticationTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get authenticatedContext => $composableBuilder(
    column: $table.authenticatedContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plaintextBytes => $composableBuilder(
    column: $table.plaintextBytes,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionIoSessionsTableFilterComposer get executionId {
    final $$ActionIoSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> actionIoMessagesRefs(
    Expression<bool> Function($$ActionIoMessagesTableFilterComposer f) f,
  ) {
    final $$ActionIoMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoMessages,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoMessagesTableFilterComposer(
            $db: $db,
            $table: $db.actionIoMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> actionIoEventsRefs(
    Expression<bool> Function($$ActionIoEventsTableFilterComposer f) f,
  ) {
    final $$ActionIoEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoEvents,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoEventsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionIoPayloadsTableOrderingComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoPayloadsTable> {
  $$ActionIoPayloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get payloadId => $composableBuilder(
    column: $table.payloadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get authenticationTag => $composableBuilder(
    column: $table.authenticationTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get authenticatedContext => $composableBuilder(
    column: $table.authenticatedContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plaintextBytes => $composableBuilder(
    column: $table.plaintextBytes,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionIoSessionsTableOrderingComposer get executionId {
    final $$ActionIoSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionIoPayloadsTableAnnotationComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoPayloadsTable> {
  $$ActionIoPayloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get payloadId =>
      $composableBuilder(column: $table.payloadId, builder: (column) => column);

  GeneratedColumn<String> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<Uint8List> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<Uint8List> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get authenticationTag => $composableBuilder(
    column: $table.authenticationTag,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get authenticatedContext => $composableBuilder(
    column: $table.authenticatedContext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plaintextBytes => $composableBuilder(
    column: $table.plaintextBytes,
    builder: (column) => column,
  );

  $$ActionIoSessionsTableAnnotationComposer get executionId {
    final $$ActionIoSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> actionIoMessagesRefs<T extends Object>(
    Expression<T> Function($$ActionIoMessagesTableAnnotationComposer a) f,
  ) {
    final $$ActionIoMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoMessages,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> actionIoEventsRefs<T extends Object>(
    Expression<T> Function($$ActionIoEventsTableAnnotationComposer a) f,
  ) {
    final $$ActionIoEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoEvents,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActionIoPayloadsTableTableManager
    extends
        RootTableManager<
          _$ActionIoJournalDatabase,
          $ActionIoPayloadsTable,
          ActionIoPayload,
          $$ActionIoPayloadsTableFilterComposer,
          $$ActionIoPayloadsTableOrderingComposer,
          $$ActionIoPayloadsTableAnnotationComposer,
          $$ActionIoPayloadsTableCreateCompanionBuilder,
          $$ActionIoPayloadsTableUpdateCompanionBuilder,
          (ActionIoPayload, $$ActionIoPayloadsTableReferences),
          ActionIoPayload,
          PrefetchHooks Function({
            bool executionId,
            bool actionIoMessagesRefs,
            bool actionIoEventsRefs,
          })
        > {
  $$ActionIoPayloadsTableTableManager(
    _$ActionIoJournalDatabase db,
    $ActionIoPayloadsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionIoPayloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionIoPayloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionIoPayloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> payloadId = const Value.absent(),
                Value<String> executionId = const Value.absent(),
                Value<String> keyId = const Value.absent(),
                Value<Uint8List> nonce = const Value.absent(),
                Value<Uint8List> ciphertext = const Value.absent(),
                Value<Uint8List> authenticationTag = const Value.absent(),
                Value<Uint8List> authenticatedContext = const Value.absent(),
                Value<int> plaintextBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionIoPayloadsCompanion(
                payloadId: payloadId,
                executionId: executionId,
                keyId: keyId,
                nonce: nonce,
                ciphertext: ciphertext,
                authenticationTag: authenticationTag,
                authenticatedContext: authenticatedContext,
                plaintextBytes: plaintextBytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String payloadId,
                required String executionId,
                required String keyId,
                required Uint8List nonce,
                required Uint8List ciphertext,
                required Uint8List authenticationTag,
                required Uint8List authenticatedContext,
                required int plaintextBytes,
                Value<int> rowid = const Value.absent(),
              }) => ActionIoPayloadsCompanion.insert(
                payloadId: payloadId,
                executionId: executionId,
                keyId: keyId,
                nonce: nonce,
                ciphertext: ciphertext,
                authenticationTag: authenticationTag,
                authenticatedContext: authenticatedContext,
                plaintextBytes: plaintextBytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionIoPayloadsTable, ActionIoPayload>(table),
                  $$ActionIoPayloadsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                executionId = false,
                actionIoMessagesRefs = false,
                actionIoEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (actionIoMessagesRefs) db.actionIoMessages,
                    if (actionIoEventsRefs) db.actionIoEvents,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (executionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.executionId,
                                    referencedTable:
                                        $$ActionIoPayloadsTableReferences
                                            ._executionIdTable(db),
                                    referencedColumn:
                                        $$ActionIoPayloadsTableReferences
                                            ._executionIdTable(db)
                                            .executionId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (actionIoMessagesRefs)
                        await $_getPrefetchedData<
                          ActionIoPayload,
                          $ActionIoPayloadsTable,
                          ActionIoMessage
                        >(
                          currentTable: table,
                          referencedTable: $$ActionIoPayloadsTableReferences
                              ._actionIoMessagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionIoPayloadsTableReferences(
                                db,
                                table,
                                p0,
                              ).actionIoMessagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.payloadId == item.payloadId,
                              ),
                          typedResults: items,
                        ),
                      if (actionIoEventsRefs)
                        await $_getPrefetchedData<
                          ActionIoPayload,
                          $ActionIoPayloadsTable,
                          ActionIoEvent
                        >(
                          currentTable: table,
                          referencedTable: $$ActionIoPayloadsTableReferences
                              ._actionIoEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionIoPayloadsTableReferences(
                                db,
                                table,
                                p0,
                              ).actionIoEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.payloadId == item.payloadId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ActionIoPayloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$ActionIoJournalDatabase,
      $ActionIoPayloadsTable,
      ActionIoPayload,
      $$ActionIoPayloadsTableFilterComposer,
      $$ActionIoPayloadsTableOrderingComposer,
      $$ActionIoPayloadsTableAnnotationComposer,
      $$ActionIoPayloadsTableCreateCompanionBuilder,
      $$ActionIoPayloadsTableUpdateCompanionBuilder,
      (ActionIoPayload, $$ActionIoPayloadsTableReferences),
      ActionIoPayload,
      PrefetchHooks Function({
        bool executionId,
        bool actionIoMessagesRefs,
        bool actionIoEventsRefs,
      })
    >;
typedef $$ActionIoMessagesTableCreateCompanionBuilder =
    ActionIoMessagesCompanion Function({
      required String executionId,
      required String messageId,
      required int sequence,
      required String fingerprint,
      required bool closesInput,
      required String deliveryState,
      Value<int?> confirmedBytes,
      required int inputBytes,
      Value<String?> payloadId,
      Value<String?> failureCode,
      required DateTime admittedAt,
      Value<int> rowid,
    });
typedef $$ActionIoMessagesTableUpdateCompanionBuilder =
    ActionIoMessagesCompanion Function({
      Value<String> executionId,
      Value<String> messageId,
      Value<int> sequence,
      Value<String> fingerprint,
      Value<bool> closesInput,
      Value<String> deliveryState,
      Value<int?> confirmedBytes,
      Value<int> inputBytes,
      Value<String?> payloadId,
      Value<String?> failureCode,
      Value<DateTime> admittedAt,
      Value<int> rowid,
    });

final class $$ActionIoMessagesTableReferences
    extends
        BaseReferences<
          _$ActionIoJournalDatabase,
          $ActionIoMessagesTable,
          ActionIoMessage
        > {
  $$ActionIoMessagesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActionIoSessionsTable _executionIdTable(
    _$ActionIoJournalDatabase db,
  ) => db.actionIoSessions.createAlias(
    'action_io_messages__execution_id__action_io_sessions__execution_id',
  );

  $$ActionIoSessionsTableProcessedTableManager get executionId {
    final $_column = $_itemColumn<String>('execution_id')!;

    final manager = $$ActionIoSessionsTableTableManager(
      $_db,
      $_db.actionIoSessions,
    ).filter((f) => f.executionId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_executionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActionIoPayloadsTable _payloadIdTable(_$ActionIoJournalDatabase db) =>
      db.actionIoPayloads.createAlias(
        'action_io_messages__payload_id__action_io_payloads__payload_id',
      );

  $$ActionIoPayloadsTableProcessedTableManager? get payloadId {
    final $_column = $_itemColumn<String>('payload_id');
    if ($_column == null) return null;
    final manager = $$ActionIoPayloadsTableTableManager(
      $_db,
      $_db.actionIoPayloads,
    ).filter((f) => f.payloadId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_payloadIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActionIoMessagesTableFilterComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoMessagesTable> {
  $$ActionIoMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get closesInput => $composableBuilder(
    column: $table.closesInput,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedBytes => $composableBuilder(
    column: $table.confirmedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inputBytes => $composableBuilder(
    column: $table.inputBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get admittedAt => $composableBuilder(
    column: $table.admittedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionIoSessionsTableFilterComposer get executionId {
    final $$ActionIoSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionIoPayloadsTableFilterComposer get payloadId {
    final $$ActionIoPayloadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionIoMessagesTableOrderingComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoMessagesTable> {
  $$ActionIoMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get closesInput => $composableBuilder(
    column: $table.closesInput,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedBytes => $composableBuilder(
    column: $table.confirmedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inputBytes => $composableBuilder(
    column: $table.inputBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get admittedAt => $composableBuilder(
    column: $table.admittedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionIoSessionsTableOrderingComposer get executionId {
    final $$ActionIoSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionIoPayloadsTableOrderingComposer get payloadId {
    final $$ActionIoPayloadsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableOrderingComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionIoMessagesTableAnnotationComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoMessagesTable> {
  $$ActionIoMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get closesInput => $composableBuilder(
    column: $table.closesInput,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confirmedBytes => $composableBuilder(
    column: $table.confirmedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get inputBytes => $composableBuilder(
    column: $table.inputBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get admittedAt => $composableBuilder(
    column: $table.admittedAt,
    builder: (column) => column,
  );

  $$ActionIoSessionsTableAnnotationComposer get executionId {
    final $$ActionIoSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionIoPayloadsTableAnnotationComposer get payloadId {
    final $$ActionIoPayloadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionIoMessagesTableTableManager
    extends
        RootTableManager<
          _$ActionIoJournalDatabase,
          $ActionIoMessagesTable,
          ActionIoMessage,
          $$ActionIoMessagesTableFilterComposer,
          $$ActionIoMessagesTableOrderingComposer,
          $$ActionIoMessagesTableAnnotationComposer,
          $$ActionIoMessagesTableCreateCompanionBuilder,
          $$ActionIoMessagesTableUpdateCompanionBuilder,
          (ActionIoMessage, $$ActionIoMessagesTableReferences),
          ActionIoMessage,
          PrefetchHooks Function({bool executionId, bool payloadId})
        > {
  $$ActionIoMessagesTableTableManager(
    _$ActionIoJournalDatabase db,
    $ActionIoMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionIoMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionIoMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionIoMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> executionId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<bool> closesInput = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<int?> confirmedBytes = const Value.absent(),
                Value<int> inputBytes = const Value.absent(),
                Value<String?> payloadId = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<DateTime> admittedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionIoMessagesCompanion(
                executionId: executionId,
                messageId: messageId,
                sequence: sequence,
                fingerprint: fingerprint,
                closesInput: closesInput,
                deliveryState: deliveryState,
                confirmedBytes: confirmedBytes,
                inputBytes: inputBytes,
                payloadId: payloadId,
                failureCode: failureCode,
                admittedAt: admittedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String executionId,
                required String messageId,
                required int sequence,
                required String fingerprint,
                required bool closesInput,
                required String deliveryState,
                Value<int?> confirmedBytes = const Value.absent(),
                required int inputBytes,
                Value<String?> payloadId = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                required DateTime admittedAt,
                Value<int> rowid = const Value.absent(),
              }) => ActionIoMessagesCompanion.insert(
                executionId: executionId,
                messageId: messageId,
                sequence: sequence,
                fingerprint: fingerprint,
                closesInput: closesInput,
                deliveryState: deliveryState,
                confirmedBytes: confirmedBytes,
                inputBytes: inputBytes,
                payloadId: payloadId,
                failureCode: failureCode,
                admittedAt: admittedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionIoMessagesTable, ActionIoMessage>(table),
                  $$ActionIoMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({executionId = false, payloadId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (executionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.executionId,
                                referencedTable:
                                    $$ActionIoMessagesTableReferences
                                        ._executionIdTable(db),
                                referencedColumn:
                                    $$ActionIoMessagesTableReferences
                                        ._executionIdTable(db)
                                        .executionId,
                              )
                              as T;
                    }
                    if (payloadId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.payloadId,
                                referencedTable:
                                    $$ActionIoMessagesTableReferences
                                        ._payloadIdTable(db),
                                referencedColumn:
                                    $$ActionIoMessagesTableReferences
                                        ._payloadIdTable(db)
                                        .payloadId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActionIoMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$ActionIoJournalDatabase,
      $ActionIoMessagesTable,
      ActionIoMessage,
      $$ActionIoMessagesTableFilterComposer,
      $$ActionIoMessagesTableOrderingComposer,
      $$ActionIoMessagesTableAnnotationComposer,
      $$ActionIoMessagesTableCreateCompanionBuilder,
      $$ActionIoMessagesTableUpdateCompanionBuilder,
      (ActionIoMessage, $$ActionIoMessagesTableReferences),
      ActionIoMessage,
      PrefetchHooks Function({bool executionId, bool payloadId})
    >;
typedef $$ActionIoEventsTableCreateCompanionBuilder =
    ActionIoEventsCompanion Function({
      required String executionId,
      required int sequence,
      required String eventType,
      Value<String?> stream,
      Value<int?> byteOffset,
      Value<String?> payloadId,
      Value<int?> exitCode,
      Value<bool?> outputComplete,
      Value<String?> failureCode,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ActionIoEventsTableUpdateCompanionBuilder =
    ActionIoEventsCompanion Function({
      Value<String> executionId,
      Value<int> sequence,
      Value<String> eventType,
      Value<String?> stream,
      Value<int?> byteOffset,
      Value<String?> payloadId,
      Value<int?> exitCode,
      Value<bool?> outputComplete,
      Value<String?> failureCode,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ActionIoEventsTableReferences
    extends
        BaseReferences<
          _$ActionIoJournalDatabase,
          $ActionIoEventsTable,
          ActionIoEvent
        > {
  $$ActionIoEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActionIoSessionsTable _executionIdTable(
    _$ActionIoJournalDatabase db,
  ) => db.actionIoSessions.createAlias(
    'action_io_events__execution_id__action_io_sessions__execution_id',
  );

  $$ActionIoSessionsTableProcessedTableManager get executionId {
    final $_column = $_itemColumn<String>('execution_id')!;

    final manager = $$ActionIoSessionsTableTableManager(
      $_db,
      $_db.actionIoSessions,
    ).filter((f) => f.executionId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_executionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActionIoPayloadsTable _payloadIdTable(_$ActionIoJournalDatabase db) =>
      db.actionIoPayloads.createAlias(
        'action_io_events__payload_id__action_io_payloads__payload_id',
      );

  $$ActionIoPayloadsTableProcessedTableManager? get payloadId {
    final $_column = $_itemColumn<String>('payload_id');
    if ($_column == null) return null;
    final manager = $$ActionIoPayloadsTableTableManager(
      $_db,
      $_db.actionIoPayloads,
    ).filter((f) => f.payloadId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_payloadIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActionIoEventsTableFilterComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoEventsTable> {
  $$ActionIoEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stream => $composableBuilder(
    column: $table.stream,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteOffset => $composableBuilder(
    column: $table.byteOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get outputComplete => $composableBuilder(
    column: $table.outputComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionIoSessionsTableFilterComposer get executionId {
    final $$ActionIoSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionIoPayloadsTableFilterComposer get payloadId {
    final $$ActionIoPayloadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableFilterComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionIoEventsTableOrderingComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoEventsTable> {
  $$ActionIoEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stream => $composableBuilder(
    column: $table.stream,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteOffset => $composableBuilder(
    column: $table.byteOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get outputComplete => $composableBuilder(
    column: $table.outputComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionIoSessionsTableOrderingComposer get executionId {
    final $$ActionIoSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionIoPayloadsTableOrderingComposer get payloadId {
    final $$ActionIoPayloadsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableOrderingComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionIoEventsTableAnnotationComposer
    extends Composer<_$ActionIoJournalDatabase, $ActionIoEventsTable> {
  $$ActionIoEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get stream =>
      $composableBuilder(column: $table.stream, builder: (column) => column);

  GeneratedColumn<int> get byteOffset => $composableBuilder(
    column: $table.byteOffset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get exitCode =>
      $composableBuilder(column: $table.exitCode, builder: (column) => column);

  GeneratedColumn<bool> get outputComplete => $composableBuilder(
    column: $table.outputComplete,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ActionIoSessionsTableAnnotationComposer get executionId {
    final $$ActionIoSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.executionId,
      referencedTable: $db.actionIoSessions,
      getReferencedColumn: (t) => t.executionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionIoPayloadsTableAnnotationComposer get payloadId {
    final $$ActionIoPayloadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.payloadId,
      referencedTable: $db.actionIoPayloads,
      getReferencedColumn: (t) => t.payloadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionIoPayloadsTableAnnotationComposer(
            $db: $db,
            $table: $db.actionIoPayloads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionIoEventsTableTableManager
    extends
        RootTableManager<
          _$ActionIoJournalDatabase,
          $ActionIoEventsTable,
          ActionIoEvent,
          $$ActionIoEventsTableFilterComposer,
          $$ActionIoEventsTableOrderingComposer,
          $$ActionIoEventsTableAnnotationComposer,
          $$ActionIoEventsTableCreateCompanionBuilder,
          $$ActionIoEventsTableUpdateCompanionBuilder,
          (ActionIoEvent, $$ActionIoEventsTableReferences),
          ActionIoEvent,
          PrefetchHooks Function({bool executionId, bool payloadId})
        > {
  $$ActionIoEventsTableTableManager(
    _$ActionIoJournalDatabase db,
    $ActionIoEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionIoEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionIoEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionIoEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> executionId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String?> stream = const Value.absent(),
                Value<int?> byteOffset = const Value.absent(),
                Value<String?> payloadId = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<bool?> outputComplete = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionIoEventsCompanion(
                executionId: executionId,
                sequence: sequence,
                eventType: eventType,
                stream: stream,
                byteOffset: byteOffset,
                payloadId: payloadId,
                exitCode: exitCode,
                outputComplete: outputComplete,
                failureCode: failureCode,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String executionId,
                required int sequence,
                required String eventType,
                Value<String?> stream = const Value.absent(),
                Value<int?> byteOffset = const Value.absent(),
                Value<String?> payloadId = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<bool?> outputComplete = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ActionIoEventsCompanion.insert(
                executionId: executionId,
                sequence: sequence,
                eventType: eventType,
                stream: stream,
                byteOffset: byteOffset,
                payloadId: payloadId,
                exitCode: exitCode,
                outputComplete: outputComplete,
                failureCode: failureCode,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionIoEventsTable, ActionIoEvent>(table),
                  $$ActionIoEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({executionId = false, payloadId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (executionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.executionId,
                                referencedTable: $$ActionIoEventsTableReferences
                                    ._executionIdTable(db),
                                referencedColumn:
                                    $$ActionIoEventsTableReferences
                                        ._executionIdTable(db)
                                        .executionId,
                              )
                              as T;
                    }
                    if (payloadId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.payloadId,
                                referencedTable: $$ActionIoEventsTableReferences
                                    ._payloadIdTable(db),
                                referencedColumn:
                                    $$ActionIoEventsTableReferences
                                        ._payloadIdTable(db)
                                        .payloadId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActionIoEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$ActionIoJournalDatabase,
      $ActionIoEventsTable,
      ActionIoEvent,
      $$ActionIoEventsTableFilterComposer,
      $$ActionIoEventsTableOrderingComposer,
      $$ActionIoEventsTableAnnotationComposer,
      $$ActionIoEventsTableCreateCompanionBuilder,
      $$ActionIoEventsTableUpdateCompanionBuilder,
      (ActionIoEvent, $$ActionIoEventsTableReferences),
      ActionIoEvent,
      PrefetchHooks Function({bool executionId, bool payloadId})
    >;

class $ActionIoJournalDatabaseManager {
  final _$ActionIoJournalDatabase _db;
  $ActionIoJournalDatabaseManager(this._db);
  $$ActionIoSessionsTableTableManager get actionIoSessions =>
      $$ActionIoSessionsTableTableManager(_db, _db.actionIoSessions);
  $$ActionIoPayloadsTableTableManager get actionIoPayloads =>
      $$ActionIoPayloadsTableTableManager(_db, _db.actionIoPayloads);
  $$ActionIoMessagesTableTableManager get actionIoMessages =>
      $$ActionIoMessagesTableTableManager(_db, _db.actionIoMessages);
  $$ActionIoEventsTableTableManager get actionIoEvents =>
      $$ActionIoEventsTableTableManager(_db, _db.actionIoEvents);
}
