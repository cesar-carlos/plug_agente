// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sql_operation_journal_database.dart';

// ignore_for_file: type=lint
class $SqlOperationJournalRecordsTable extends SqlOperationJournalRecords
    with
        TableInfo<$SqlOperationJournalRecordsTable, SqlOperationJournalRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SqlOperationJournalRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeHashMeta = const VerificationMeta(
    'scopeHash',
  );
  @override
  late final GeneratedColumn<String> scopeHash = GeneratedColumn<String>(
    'scope_hash',
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
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _directlyAffectedRowsMeta =
      const VerificationMeta('directlyAffectedRows');
  @override
  late final GeneratedColumn<int> directlyAffectedRows = GeneratedColumn<int>(
    'directly_affected_rows',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    scopeHash,
    fingerprint,
    contentHash,
    executionId,
    state,
    failureCode,
    directlyAffectedRows,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sql_operation_journal_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SqlOperationJournalRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('scope_hash')) {
      context.handle(
        _scopeHashMeta,
        scopeHash.isAcceptableOrUnknown(data['scope_hash']!, _scopeHashMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeHashMeta);
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
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
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
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
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
    if (data.containsKey('directly_affected_rows')) {
      context.handle(
        _directlyAffectedRowsMeta,
        directlyAffectedRows.isAcceptableOrUnknown(
          data['directly_affected_rows']!,
          _directlyAffectedRowsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  SqlOperationJournalRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SqlOperationJournalRecord(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      scopeHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_hash'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      directlyAffectedRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}directly_affected_rows'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SqlOperationJournalRecordsTable createAlias(String alias) {
    return $SqlOperationJournalRecordsTable(attachedDatabase, alias);
  }
}

class SqlOperationJournalRecord extends DataClass
    implements Insertable<SqlOperationJournalRecord> {
  final String operationId;
  final String scopeHash;
  final String fingerprint;
  final String? contentHash;
  final String executionId;
  final String state;
  final String? failureCode;
  final int? directlyAffectedRows;
  final DateTime updatedAt;
  const SqlOperationJournalRecord({
    required this.operationId,
    required this.scopeHash,
    required this.fingerprint,
    this.contentHash,
    required this.executionId,
    required this.state,
    this.failureCode,
    this.directlyAffectedRows,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['scope_hash'] = Variable<String>(scopeHash);
    map['fingerprint'] = Variable<String>(fingerprint);
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    map['execution_id'] = Variable<String>(executionId);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    if (!nullToAbsent || directlyAffectedRows != null) {
      map['directly_affected_rows'] = Variable<int>(directlyAffectedRows);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SqlOperationJournalRecordsCompanion toCompanion(bool nullToAbsent) {
    return SqlOperationJournalRecordsCompanion(
      operationId: Value(operationId),
      scopeHash: Value(scopeHash),
      fingerprint: Value(fingerprint),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      executionId: Value(executionId),
      state: Value(state),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      directlyAffectedRows: directlyAffectedRows == null && nullToAbsent
          ? const Value.absent()
          : Value(directlyAffectedRows),
      updatedAt: Value(updatedAt),
    );
  }

  factory SqlOperationJournalRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SqlOperationJournalRecord(
      operationId: serializer.fromJson<String>(json['operationId']),
      scopeHash: serializer.fromJson<String>(json['scopeHash']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      executionId: serializer.fromJson<String>(json['executionId']),
      state: serializer.fromJson<String>(json['state']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      directlyAffectedRows: serializer.fromJson<int?>(
        json['directlyAffectedRows'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'scopeHash': serializer.toJson<String>(scopeHash),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'contentHash': serializer.toJson<String?>(contentHash),
      'executionId': serializer.toJson<String>(executionId),
      'state': serializer.toJson<String>(state),
      'failureCode': serializer.toJson<String?>(failureCode),
      'directlyAffectedRows': serializer.toJson<int?>(directlyAffectedRows),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SqlOperationJournalRecord copyWith({
    String? operationId,
    String? scopeHash,
    String? fingerprint,
    Value<String?> contentHash = const Value.absent(),
    String? executionId,
    String? state,
    Value<String?> failureCode = const Value.absent(),
    Value<int?> directlyAffectedRows = const Value.absent(),
    DateTime? updatedAt,
  }) => SqlOperationJournalRecord(
    operationId: operationId ?? this.operationId,
    scopeHash: scopeHash ?? this.scopeHash,
    fingerprint: fingerprint ?? this.fingerprint,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    executionId: executionId ?? this.executionId,
    state: state ?? this.state,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    directlyAffectedRows: directlyAffectedRows.present
        ? directlyAffectedRows.value
        : this.directlyAffectedRows,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SqlOperationJournalRecord copyWithCompanion(
    SqlOperationJournalRecordsCompanion data,
  ) {
    return SqlOperationJournalRecord(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      scopeHash: data.scopeHash.present ? data.scopeHash.value : this.scopeHash,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      state: data.state.present ? data.state.value : this.state,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      directlyAffectedRows: data.directlyAffectedRows.present
          ? data.directlyAffectedRows.value
          : this.directlyAffectedRows,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SqlOperationJournalRecord(')
          ..write('operationId: $operationId, ')
          ..write('scopeHash: $scopeHash, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('contentHash: $contentHash, ')
          ..write('executionId: $executionId, ')
          ..write('state: $state, ')
          ..write('failureCode: $failureCode, ')
          ..write('directlyAffectedRows: $directlyAffectedRows, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    scopeHash,
    fingerprint,
    contentHash,
    executionId,
    state,
    failureCode,
    directlyAffectedRows,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SqlOperationJournalRecord &&
          other.operationId == this.operationId &&
          other.scopeHash == this.scopeHash &&
          other.fingerprint == this.fingerprint &&
          other.contentHash == this.contentHash &&
          other.executionId == this.executionId &&
          other.state == this.state &&
          other.failureCode == this.failureCode &&
          other.directlyAffectedRows == this.directlyAffectedRows &&
          other.updatedAt == this.updatedAt);
}

class SqlOperationJournalRecordsCompanion
    extends UpdateCompanion<SqlOperationJournalRecord> {
  final Value<String> operationId;
  final Value<String> scopeHash;
  final Value<String> fingerprint;
  final Value<String?> contentHash;
  final Value<String> executionId;
  final Value<String> state;
  final Value<String?> failureCode;
  final Value<int?> directlyAffectedRows;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SqlOperationJournalRecordsCompanion({
    this.operationId = const Value.absent(),
    this.scopeHash = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.executionId = const Value.absent(),
    this.state = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.directlyAffectedRows = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SqlOperationJournalRecordsCompanion.insert({
    required String operationId,
    required String scopeHash,
    required String fingerprint,
    this.contentHash = const Value.absent(),
    required String executionId,
    required String state,
    this.failureCode = const Value.absent(),
    this.directlyAffectedRows = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       scopeHash = Value(scopeHash),
       fingerprint = Value(fingerprint),
       executionId = Value(executionId),
       state = Value(state),
       updatedAt = Value(updatedAt);
  static Insertable<SqlOperationJournalRecord> custom({
    Expression<String>? operationId,
    Expression<String>? scopeHash,
    Expression<String>? fingerprint,
    Expression<String>? contentHash,
    Expression<String>? executionId,
    Expression<String>? state,
    Expression<String>? failureCode,
    Expression<int>? directlyAffectedRows,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (scopeHash != null) 'scope_hash': scopeHash,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (contentHash != null) 'content_hash': contentHash,
      if (executionId != null) 'execution_id': executionId,
      if (state != null) 'state': state,
      if (failureCode != null) 'failure_code': failureCode,
      if (directlyAffectedRows != null)
        'directly_affected_rows': directlyAffectedRows,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SqlOperationJournalRecordsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? scopeHash,
    Value<String>? fingerprint,
    Value<String?>? contentHash,
    Value<String>? executionId,
    Value<String>? state,
    Value<String?>? failureCode,
    Value<int?>? directlyAffectedRows,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SqlOperationJournalRecordsCompanion(
      operationId: operationId ?? this.operationId,
      scopeHash: scopeHash ?? this.scopeHash,
      fingerprint: fingerprint ?? this.fingerprint,
      contentHash: contentHash ?? this.contentHash,
      executionId: executionId ?? this.executionId,
      state: state ?? this.state,
      failureCode: failureCode ?? this.failureCode,
      directlyAffectedRows: directlyAffectedRows ?? this.directlyAffectedRows,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (scopeHash.present) {
      map['scope_hash'] = Variable<String>(scopeHash.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (directlyAffectedRows.present) {
      map['directly_affected_rows'] = Variable<int>(directlyAffectedRows.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SqlOperationJournalRecordsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('scopeHash: $scopeHash, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('contentHash: $contentHash, ')
          ..write('executionId: $executionId, ')
          ..write('state: $state, ')
          ..write('failureCode: $failureCode, ')
          ..write('directlyAffectedRows: $directlyAffectedRows, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SqlOperationJournalDatabase extends GeneratedDatabase {
  _$SqlOperationJournalDatabase(QueryExecutor e) : super(e);
  $SqlOperationJournalDatabaseManager get managers =>
      $SqlOperationJournalDatabaseManager(this);
  late final $SqlOperationJournalRecordsTable sqlOperationJournalRecords =
      $SqlOperationJournalRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sqlOperationJournalRecords,
  ];
}

typedef $$SqlOperationJournalRecordsTableCreateCompanionBuilder =
    SqlOperationJournalRecordsCompanion Function({
      required String operationId,
      required String scopeHash,
      required String fingerprint,
      Value<String?> contentHash,
      required String executionId,
      required String state,
      Value<String?> failureCode,
      Value<int?> directlyAffectedRows,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SqlOperationJournalRecordsTableUpdateCompanionBuilder =
    SqlOperationJournalRecordsCompanion Function({
      Value<String> operationId,
      Value<String> scopeHash,
      Value<String> fingerprint,
      Value<String?> contentHash,
      Value<String> executionId,
      Value<String> state,
      Value<String?> failureCode,
      Value<int?> directlyAffectedRows,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SqlOperationJournalRecordsTableFilterComposer
    extends
        Composer<
          _$SqlOperationJournalDatabase,
          $SqlOperationJournalRecordsTable
        > {
  $$SqlOperationJournalRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeHash => $composableBuilder(
    column: $table.scopeHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get directlyAffectedRows => $composableBuilder(
    column: $table.directlyAffectedRows,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SqlOperationJournalRecordsTableOrderingComposer
    extends
        Composer<
          _$SqlOperationJournalDatabase,
          $SqlOperationJournalRecordsTable
        > {
  $$SqlOperationJournalRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeHash => $composableBuilder(
    column: $table.scopeHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get directlyAffectedRows => $composableBuilder(
    column: $table.directlyAffectedRows,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SqlOperationJournalRecordsTableAnnotationComposer
    extends
        Composer<
          _$SqlOperationJournalDatabase,
          $SqlOperationJournalRecordsTable
        > {
  $$SqlOperationJournalRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scopeHash =>
      $composableBuilder(column: $table.scopeHash, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get directlyAffectedRows => $composableBuilder(
    column: $table.directlyAffectedRows,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SqlOperationJournalRecordsTableTableManager
    extends
        RootTableManager<
          _$SqlOperationJournalDatabase,
          $SqlOperationJournalRecordsTable,
          SqlOperationJournalRecord,
          $$SqlOperationJournalRecordsTableFilterComposer,
          $$SqlOperationJournalRecordsTableOrderingComposer,
          $$SqlOperationJournalRecordsTableAnnotationComposer,
          $$SqlOperationJournalRecordsTableCreateCompanionBuilder,
          $$SqlOperationJournalRecordsTableUpdateCompanionBuilder,
          (
            SqlOperationJournalRecord,
            BaseReferences<
              _$SqlOperationJournalDatabase,
              $SqlOperationJournalRecordsTable,
              SqlOperationJournalRecord
            >,
          ),
          SqlOperationJournalRecord,
          PrefetchHooks Function()
        > {
  $$SqlOperationJournalRecordsTableTableManager(
    _$SqlOperationJournalDatabase db,
    $SqlOperationJournalRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SqlOperationJournalRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SqlOperationJournalRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SqlOperationJournalRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> scopeHash = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<String> executionId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<int?> directlyAffectedRows = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SqlOperationJournalRecordsCompanion(
                operationId: operationId,
                scopeHash: scopeHash,
                fingerprint: fingerprint,
                contentHash: contentHash,
                executionId: executionId,
                state: state,
                failureCode: failureCode,
                directlyAffectedRows: directlyAffectedRows,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String scopeHash,
                required String fingerprint,
                Value<String?> contentHash = const Value.absent(),
                required String executionId,
                required String state,
                Value<String?> failureCode = const Value.absent(),
                Value<int?> directlyAffectedRows = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SqlOperationJournalRecordsCompanion.insert(
                operationId: operationId,
                scopeHash: scopeHash,
                fingerprint: fingerprint,
                contentHash: contentHash,
                executionId: executionId,
                state: state,
                failureCode: failureCode,
                directlyAffectedRows: directlyAffectedRows,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $SqlOperationJournalRecordsTable,
                    SqlOperationJournalRecord
                  >(table),
                  BaseReferences<
                    _$SqlOperationJournalDatabase,
                    $SqlOperationJournalRecordsTable,
                    SqlOperationJournalRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SqlOperationJournalRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$SqlOperationJournalDatabase,
      $SqlOperationJournalRecordsTable,
      SqlOperationJournalRecord,
      $$SqlOperationJournalRecordsTableFilterComposer,
      $$SqlOperationJournalRecordsTableOrderingComposer,
      $$SqlOperationJournalRecordsTableAnnotationComposer,
      $$SqlOperationJournalRecordsTableCreateCompanionBuilder,
      $$SqlOperationJournalRecordsTableUpdateCompanionBuilder,
      (
        SqlOperationJournalRecord,
        BaseReferences<
          _$SqlOperationJournalDatabase,
          $SqlOperationJournalRecordsTable,
          SqlOperationJournalRecord
        >,
      ),
      SqlOperationJournalRecord,
      PrefetchHooks Function()
    >;

class $SqlOperationJournalDatabaseManager {
  final _$SqlOperationJournalDatabase _db;
  $SqlOperationJournalDatabaseManager(this._db);
  $$SqlOperationJournalRecordsTableTableManager
  get sqlOperationJournalRecords =>
      $$SqlOperationJournalRecordsTableTableManager(
        _db,
        _db.sqlOperationJournalRecords,
      );
}
