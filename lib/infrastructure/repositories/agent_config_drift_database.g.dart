// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_config_drift_database.dart';

// ignore_for_file: type=lint
class $ConfigTableTable extends ConfigTable
    with TableInfo<$ConfigTableTable, ConfigData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConfigTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverUrlMeta = const VerificationMeta(
    'serverUrl',
  );
  @override
  late final GeneratedColumn<String> serverUrl = GeneratedColumn<String>(
    'server_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('https://api.example.com'),
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
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _authTokenMeta = const VerificationMeta(
    'authToken',
  );
  @override
  late final GeneratedColumn<String> authToken = GeneratedColumn<String>(
    'auth_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refreshTokenMeta = const VerificationMeta(
    'refreshToken',
  );
  @override
  late final GeneratedColumn<String> refreshToken = GeneratedColumn<String>(
    'refresh_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authUsernameMeta = const VerificationMeta(
    'authUsername',
  );
  @override
  late final GeneratedColumn<String> authUsername = GeneratedColumn<String>(
    'auth_username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authPasswordMeta = const VerificationMeta(
    'authPassword',
  );
  @override
  late final GeneratedColumn<String> authPassword = GeneratedColumn<String>(
    'auth_password',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _driverNameMeta = const VerificationMeta(
    'driverName',
  );
  @override
  late final GeneratedColumn<String> driverName = GeneratedColumn<String>(
    'driver_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _odbcDriverNameMeta = const VerificationMeta(
    'odbcDriverName',
  );
  @override
  late final GeneratedColumn<String> odbcDriverName = GeneratedColumn<String>(
    'odbc_driver_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _connectionStringMeta = const VerificationMeta(
    'connectionString',
  );
  @override
  late final GeneratedColumn<String> connectionString = GeneratedColumn<String>(
    'connection_string',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _databaseNameMeta = const VerificationMeta(
    'databaseName',
  );
  @override
  late final GeneratedColumn<String> databaseName = GeneratedColumn<String>(
    'database_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
    id,
    serverUrl,
    agentId,
    authToken,
    refreshToken,
    authUsername,
    authPassword,
    driverName,
    odbcDriverName,
    connectionString,
    username,
    password,
    databaseName,
    host,
    port,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'config_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConfigData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_url')) {
      context.handle(
        _serverUrlMeta,
        serverUrl.isAcceptableOrUnknown(data['server_url']!, _serverUrlMeta),
      );
    }
    if (data.containsKey('agent_id')) {
      context.handle(
        _agentIdMeta,
        agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta),
      );
    }
    if (data.containsKey('auth_token')) {
      context.handle(
        _authTokenMeta,
        authToken.isAcceptableOrUnknown(data['auth_token']!, _authTokenMeta),
      );
    }
    if (data.containsKey('refresh_token')) {
      context.handle(
        _refreshTokenMeta,
        refreshToken.isAcceptableOrUnknown(
          data['refresh_token']!,
          _refreshTokenMeta,
        ),
      );
    }
    if (data.containsKey('auth_username')) {
      context.handle(
        _authUsernameMeta,
        authUsername.isAcceptableOrUnknown(
          data['auth_username']!,
          _authUsernameMeta,
        ),
      );
    }
    if (data.containsKey('auth_password')) {
      context.handle(
        _authPasswordMeta,
        authPassword.isAcceptableOrUnknown(
          data['auth_password']!,
          _authPasswordMeta,
        ),
      );
    }
    if (data.containsKey('driver_name')) {
      context.handle(
        _driverNameMeta,
        driverName.isAcceptableOrUnknown(data['driver_name']!, _driverNameMeta),
      );
    } else if (isInserting) {
      context.missing(_driverNameMeta);
    }
    if (data.containsKey('odbc_driver_name')) {
      context.handle(
        _odbcDriverNameMeta,
        odbcDriverName.isAcceptableOrUnknown(
          data['odbc_driver_name']!,
          _odbcDriverNameMeta,
        ),
      );
    }
    if (data.containsKey('connection_string')) {
      context.handle(
        _connectionStringMeta,
        connectionString.isAcceptableOrUnknown(
          data['connection_string']!,
          _connectionStringMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionStringMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    }
    if (data.containsKey('database_name')) {
      context.handle(
        _databaseNameMeta,
        databaseName.isAcceptableOrUnknown(
          data['database_name']!,
          _databaseNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databaseNameMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConfigData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConfigData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_url'],
      )!,
      agentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_id'],
      )!,
      authToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_token'],
      ),
      refreshToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refresh_token'],
      ),
      authUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_username'],
      ),
      authPassword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_password'],
      ),
      driverName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}driver_name'],
      )!,
      odbcDriverName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}odbc_driver_name'],
      )!,
      connectionString: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_string'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      ),
      databaseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database_name'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConfigTableTable createAlias(String alias) {
    return $ConfigTableTable(attachedDatabase, alias);
  }
}

class ConfigData extends DataClass implements Insertable<ConfigData> {
  final String id;
  final String serverUrl;
  final String agentId;
  final String? authToken;
  final String? refreshToken;
  final String? authUsername;
  final String? authPassword;
  final String driverName;
  final String odbcDriverName;
  final String connectionString;
  final String username;
  final String? password;
  final String databaseName;
  final String host;
  final int port;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ConfigData({
    required this.id,
    required this.serverUrl,
    required this.agentId,
    this.authToken,
    this.refreshToken,
    this.authUsername,
    this.authPassword,
    required this.driverName,
    required this.odbcDriverName,
    required this.connectionString,
    required this.username,
    this.password,
    required this.databaseName,
    required this.host,
    required this.port,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['server_url'] = Variable<String>(serverUrl);
    map['agent_id'] = Variable<String>(agentId);
    if (!nullToAbsent || authToken != null) {
      map['auth_token'] = Variable<String>(authToken);
    }
    if (!nullToAbsent || refreshToken != null) {
      map['refresh_token'] = Variable<String>(refreshToken);
    }
    if (!nullToAbsent || authUsername != null) {
      map['auth_username'] = Variable<String>(authUsername);
    }
    if (!nullToAbsent || authPassword != null) {
      map['auth_password'] = Variable<String>(authPassword);
    }
    map['driver_name'] = Variable<String>(driverName);
    map['odbc_driver_name'] = Variable<String>(odbcDriverName);
    map['connection_string'] = Variable<String>(connectionString);
    map['username'] = Variable<String>(username);
    if (!nullToAbsent || password != null) {
      map['password'] = Variable<String>(password);
    }
    map['database_name'] = Variable<String>(databaseName);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConfigTableCompanion toCompanion(bool nullToAbsent) {
    return ConfigTableCompanion(
      id: Value(id),
      serverUrl: Value(serverUrl),
      agentId: Value(agentId),
      authToken: authToken == null && nullToAbsent
          ? const Value.absent()
          : Value(authToken),
      refreshToken: refreshToken == null && nullToAbsent
          ? const Value.absent()
          : Value(refreshToken),
      authUsername: authUsername == null && nullToAbsent
          ? const Value.absent()
          : Value(authUsername),
      authPassword: authPassword == null && nullToAbsent
          ? const Value.absent()
          : Value(authPassword),
      driverName: Value(driverName),
      odbcDriverName: Value(odbcDriverName),
      connectionString: Value(connectionString),
      username: Value(username),
      password: password == null && nullToAbsent
          ? const Value.absent()
          : Value(password),
      databaseName: Value(databaseName),
      host: Value(host),
      port: Value(port),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ConfigData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConfigData(
      id: serializer.fromJson<String>(json['id']),
      serverUrl: serializer.fromJson<String>(json['serverUrl']),
      agentId: serializer.fromJson<String>(json['agentId']),
      authToken: serializer.fromJson<String?>(json['authToken']),
      refreshToken: serializer.fromJson<String?>(json['refreshToken']),
      authUsername: serializer.fromJson<String?>(json['authUsername']),
      authPassword: serializer.fromJson<String?>(json['authPassword']),
      driverName: serializer.fromJson<String>(json['driverName']),
      odbcDriverName: serializer.fromJson<String>(json['odbcDriverName']),
      connectionString: serializer.fromJson<String>(json['connectionString']),
      username: serializer.fromJson<String>(json['username']),
      password: serializer.fromJson<String?>(json['password']),
      databaseName: serializer.fromJson<String>(json['databaseName']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverUrl': serializer.toJson<String>(serverUrl),
      'agentId': serializer.toJson<String>(agentId),
      'authToken': serializer.toJson<String?>(authToken),
      'refreshToken': serializer.toJson<String?>(refreshToken),
      'authUsername': serializer.toJson<String?>(authUsername),
      'authPassword': serializer.toJson<String?>(authPassword),
      'driverName': serializer.toJson<String>(driverName),
      'odbcDriverName': serializer.toJson<String>(odbcDriverName),
      'connectionString': serializer.toJson<String>(connectionString),
      'username': serializer.toJson<String>(username),
      'password': serializer.toJson<String?>(password),
      'databaseName': serializer.toJson<String>(databaseName),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ConfigData copyWith({
    String? id,
    String? serverUrl,
    String? agentId,
    Value<String?> authToken = const Value.absent(),
    Value<String?> refreshToken = const Value.absent(),
    Value<String?> authUsername = const Value.absent(),
    Value<String?> authPassword = const Value.absent(),
    String? driverName,
    String? odbcDriverName,
    String? connectionString,
    String? username,
    Value<String?> password = const Value.absent(),
    String? databaseName,
    String? host,
    int? port,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ConfigData(
    id: id ?? this.id,
    serverUrl: serverUrl ?? this.serverUrl,
    agentId: agentId ?? this.agentId,
    authToken: authToken.present ? authToken.value : this.authToken,
    refreshToken: refreshToken.present ? refreshToken.value : this.refreshToken,
    authUsername: authUsername.present ? authUsername.value : this.authUsername,
    authPassword: authPassword.present ? authPassword.value : this.authPassword,
    driverName: driverName ?? this.driverName,
    odbcDriverName: odbcDriverName ?? this.odbcDriverName,
    connectionString: connectionString ?? this.connectionString,
    username: username ?? this.username,
    password: password.present ? password.value : this.password,
    databaseName: databaseName ?? this.databaseName,
    host: host ?? this.host,
    port: port ?? this.port,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ConfigData copyWithCompanion(ConfigTableCompanion data) {
    return ConfigData(
      id: data.id.present ? data.id.value : this.id,
      serverUrl: data.serverUrl.present ? data.serverUrl.value : this.serverUrl,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      authToken: data.authToken.present ? data.authToken.value : this.authToken,
      refreshToken: data.refreshToken.present
          ? data.refreshToken.value
          : this.refreshToken,
      authUsername: data.authUsername.present
          ? data.authUsername.value
          : this.authUsername,
      authPassword: data.authPassword.present
          ? data.authPassword.value
          : this.authPassword,
      driverName: data.driverName.present
          ? data.driverName.value
          : this.driverName,
      odbcDriverName: data.odbcDriverName.present
          ? data.odbcDriverName.value
          : this.odbcDriverName,
      connectionString: data.connectionString.present
          ? data.connectionString.value
          : this.connectionString,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      databaseName: data.databaseName.present
          ? data.databaseName.value
          : this.databaseName,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConfigData(')
          ..write('id: $id, ')
          ..write('serverUrl: $serverUrl, ')
          ..write('agentId: $agentId, ')
          ..write('authToken: $authToken, ')
          ..write('refreshToken: $refreshToken, ')
          ..write('authUsername: $authUsername, ')
          ..write('authPassword: $authPassword, ')
          ..write('driverName: $driverName, ')
          ..write('odbcDriverName: $odbcDriverName, ')
          ..write('connectionString: $connectionString, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('databaseName: $databaseName, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverUrl,
    agentId,
    authToken,
    refreshToken,
    authUsername,
    authPassword,
    driverName,
    odbcDriverName,
    connectionString,
    username,
    password,
    databaseName,
    host,
    port,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConfigData &&
          other.id == this.id &&
          other.serverUrl == this.serverUrl &&
          other.agentId == this.agentId &&
          other.authToken == this.authToken &&
          other.refreshToken == this.refreshToken &&
          other.authUsername == this.authUsername &&
          other.authPassword == this.authPassword &&
          other.driverName == this.driverName &&
          other.odbcDriverName == this.odbcDriverName &&
          other.connectionString == this.connectionString &&
          other.username == this.username &&
          other.password == this.password &&
          other.databaseName == this.databaseName &&
          other.host == this.host &&
          other.port == this.port &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConfigTableCompanion extends UpdateCompanion<ConfigData> {
  final Value<String> id;
  final Value<String> serverUrl;
  final Value<String> agentId;
  final Value<String?> authToken;
  final Value<String?> refreshToken;
  final Value<String?> authUsername;
  final Value<String?> authPassword;
  final Value<String> driverName;
  final Value<String> odbcDriverName;
  final Value<String> connectionString;
  final Value<String> username;
  final Value<String?> password;
  final Value<String> databaseName;
  final Value<String> host;
  final Value<int> port;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ConfigTableCompanion({
    this.id = const Value.absent(),
    this.serverUrl = const Value.absent(),
    this.agentId = const Value.absent(),
    this.authToken = const Value.absent(),
    this.refreshToken = const Value.absent(),
    this.authUsername = const Value.absent(),
    this.authPassword = const Value.absent(),
    this.driverName = const Value.absent(),
    this.odbcDriverName = const Value.absent(),
    this.connectionString = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.databaseName = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConfigTableCompanion.insert({
    required String id,
    this.serverUrl = const Value.absent(),
    this.agentId = const Value.absent(),
    this.authToken = const Value.absent(),
    this.refreshToken = const Value.absent(),
    this.authUsername = const Value.absent(),
    this.authPassword = const Value.absent(),
    required String driverName,
    this.odbcDriverName = const Value.absent(),
    required String connectionString,
    required String username,
    this.password = const Value.absent(),
    required String databaseName,
    required String host,
    required int port,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       driverName = Value(driverName),
       connectionString = Value(connectionString),
       username = Value(username),
       databaseName = Value(databaseName),
       host = Value(host),
       port = Value(port),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ConfigData> custom({
    Expression<String>? id,
    Expression<String>? serverUrl,
    Expression<String>? agentId,
    Expression<String>? authToken,
    Expression<String>? refreshToken,
    Expression<String>? authUsername,
    Expression<String>? authPassword,
    Expression<String>? driverName,
    Expression<String>? odbcDriverName,
    Expression<String>? connectionString,
    Expression<String>? username,
    Expression<String>? password,
    Expression<String>? databaseName,
    Expression<String>? host,
    Expression<int>? port,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverUrl != null) 'server_url': serverUrl,
      if (agentId != null) 'agent_id': agentId,
      if (authToken != null) 'auth_token': authToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      if (authUsername != null) 'auth_username': authUsername,
      if (authPassword != null) 'auth_password': authPassword,
      if (driverName != null) 'driver_name': driverName,
      if (odbcDriverName != null) 'odbc_driver_name': odbcDriverName,
      if (connectionString != null) 'connection_string': connectionString,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (databaseName != null) 'database_name': databaseName,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConfigTableCompanion copyWith({
    Value<String>? id,
    Value<String>? serverUrl,
    Value<String>? agentId,
    Value<String?>? authToken,
    Value<String?>? refreshToken,
    Value<String?>? authUsername,
    Value<String?>? authPassword,
    Value<String>? driverName,
    Value<String>? odbcDriverName,
    Value<String>? connectionString,
    Value<String>? username,
    Value<String?>? password,
    Value<String>? databaseName,
    Value<String>? host,
    Value<int>? port,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConfigTableCompanion(
      id: id ?? this.id,
      serverUrl: serverUrl ?? this.serverUrl,
      agentId: agentId ?? this.agentId,
      authToken: authToken ?? this.authToken,
      refreshToken: refreshToken ?? this.refreshToken,
      authUsername: authUsername ?? this.authUsername,
      authPassword: authPassword ?? this.authPassword,
      driverName: driverName ?? this.driverName,
      odbcDriverName: odbcDriverName ?? this.odbcDriverName,
      connectionString: connectionString ?? this.connectionString,
      username: username ?? this.username,
      password: password ?? this.password,
      databaseName: databaseName ?? this.databaseName,
      host: host ?? this.host,
      port: port ?? this.port,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverUrl.present) {
      map['server_url'] = Variable<String>(serverUrl.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (authToken.present) {
      map['auth_token'] = Variable<String>(authToken.value);
    }
    if (refreshToken.present) {
      map['refresh_token'] = Variable<String>(refreshToken.value);
    }
    if (authUsername.present) {
      map['auth_username'] = Variable<String>(authUsername.value);
    }
    if (authPassword.present) {
      map['auth_password'] = Variable<String>(authPassword.value);
    }
    if (driverName.present) {
      map['driver_name'] = Variable<String>(driverName.value);
    }
    if (odbcDriverName.present) {
      map['odbc_driver_name'] = Variable<String>(odbcDriverName.value);
    }
    if (connectionString.present) {
      map['connection_string'] = Variable<String>(connectionString.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (databaseName.present) {
      map['database_name'] = Variable<String>(databaseName.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('ConfigTableCompanion(')
          ..write('id: $id, ')
          ..write('serverUrl: $serverUrl, ')
          ..write('agentId: $agentId, ')
          ..write('authToken: $authToken, ')
          ..write('refreshToken: $refreshToken, ')
          ..write('authUsername: $authUsername, ')
          ..write('authPassword: $authPassword, ')
          ..write('driverName: $driverName, ')
          ..write('odbcDriverName: $odbcDriverName, ')
          ..write('connectionString: $connectionString, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('databaseName: $databaseName, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientTokenCacheTableTable extends ClientTokenCacheTable
    with TableInfo<$ClientTokenCacheTableTable, ClientTokenCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientTokenCacheTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _isRevokedMeta = const VerificationMeta(
    'isRevoked',
  );
  @override
  late final GeneratedColumn<bool> isRevoked = GeneratedColumn<bool>(
    'is_revoked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_revoked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _agentIdMeta = const VerificationMeta(
    'agentId',
  );
  @override
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
    'agent_id',
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
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _allTablesMeta = const VerificationMeta(
    'allTables',
  );
  @override
  late final GeneratedColumn<bool> allTables = GeneratedColumn<bool>(
    'all_tables',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_tables" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _allViewsMeta = const VerificationMeta(
    'allViews',
  );
  @override
  late final GeneratedColumn<bool> allViews = GeneratedColumn<bool>(
    'all_views',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_views" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _allPermissionsMeta = const VerificationMeta(
    'allPermissions',
  );
  @override
  late final GeneratedColumn<bool> allPermissions = GeneratedColumn<bool>(
    'all_permissions',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_permissions" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _rulesJsonMeta = const VerificationMeta(
    'rulesJson',
  );
  @override
  late final GeneratedColumn<String> rulesJson = GeneratedColumn<String>(
    'rules_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenHashMeta = const VerificationMeta(
    'tokenHash',
  );
  @override
  late final GeneratedColumn<String> tokenHash = GeneratedColumn<String>(
    'token_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    isRevoked,
    agentId,
    createdAt,
    payloadJson,
    allTables,
    allViews,
    allPermissions,
    rulesJson,
    syncedAt,
    tokenHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_token_cache_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientTokenCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('is_revoked')) {
      context.handle(
        _isRevokedMeta,
        isRevoked.isAcceptableOrUnknown(data['is_revoked']!, _isRevokedMeta),
      );
    }
    if (data.containsKey('agent_id')) {
      context.handle(
        _agentIdMeta,
        agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta),
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
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('all_tables')) {
      context.handle(
        _allTablesMeta,
        allTables.isAcceptableOrUnknown(data['all_tables']!, _allTablesMeta),
      );
    }
    if (data.containsKey('all_views')) {
      context.handle(
        _allViewsMeta,
        allViews.isAcceptableOrUnknown(data['all_views']!, _allViewsMeta),
      );
    }
    if (data.containsKey('all_permissions')) {
      context.handle(
        _allPermissionsMeta,
        allPermissions.isAcceptableOrUnknown(
          data['all_permissions']!,
          _allPermissionsMeta,
        ),
      );
    }
    if (data.containsKey('rules_json')) {
      context.handle(
        _rulesJsonMeta,
        rulesJson.isAcceptableOrUnknown(data['rules_json']!, _rulesJsonMeta),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    if (data.containsKey('token_hash')) {
      context.handle(
        _tokenHashMeta,
        tokenHash.isAcceptableOrUnknown(data['token_hash']!, _tokenHashMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {tokenHash},
  ];
  @override
  ClientTokenCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientTokenCacheData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      isRevoked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_revoked'],
      )!,
      agentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      allTables: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_tables'],
      )!,
      allViews: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_views'],
      )!,
      allPermissions: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_permissions'],
      )!,
      rulesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rules_json'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      )!,
      tokenHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_hash'],
      )!,
    );
  }

  @override
  $ClientTokenCacheTableTable createAlias(String alias) {
    return $ClientTokenCacheTableTable(attachedDatabase, alias);
  }
}

class ClientTokenCacheData extends DataClass
    implements Insertable<ClientTokenCacheData> {
  final String id;
  final String clientId;
  final bool isRevoked;
  final String? agentId;
  final DateTime createdAt;
  final String payloadJson;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final String rulesJson;
  final DateTime syncedAt;
  final String tokenHash;
  const ClientTokenCacheData({
    required this.id,
    required this.clientId,
    required this.isRevoked,
    this.agentId,
    required this.createdAt,
    required this.payloadJson,
    required this.allTables,
    required this.allViews,
    required this.allPermissions,
    required this.rulesJson,
    required this.syncedAt,
    required this.tokenHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['is_revoked'] = Variable<bool>(isRevoked);
    if (!nullToAbsent || agentId != null) {
      map['agent_id'] = Variable<String>(agentId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['payload_json'] = Variable<String>(payloadJson);
    map['all_tables'] = Variable<bool>(allTables);
    map['all_views'] = Variable<bool>(allViews);
    map['all_permissions'] = Variable<bool>(allPermissions);
    map['rules_json'] = Variable<String>(rulesJson);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    map['token_hash'] = Variable<String>(tokenHash);
    return map;
  }

  ClientTokenCacheTableCompanion toCompanion(bool nullToAbsent) {
    return ClientTokenCacheTableCompanion(
      id: Value(id),
      clientId: Value(clientId),
      isRevoked: Value(isRevoked),
      agentId: agentId == null && nullToAbsent
          ? const Value.absent()
          : Value(agentId),
      createdAt: Value(createdAt),
      payloadJson: Value(payloadJson),
      allTables: Value(allTables),
      allViews: Value(allViews),
      allPermissions: Value(allPermissions),
      rulesJson: Value(rulesJson),
      syncedAt: Value(syncedAt),
      tokenHash: Value(tokenHash),
    );
  }

  factory ClientTokenCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientTokenCacheData(
      id: serializer.fromJson<String>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      isRevoked: serializer.fromJson<bool>(json['isRevoked']),
      agentId: serializer.fromJson<String?>(json['agentId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      allTables: serializer.fromJson<bool>(json['allTables']),
      allViews: serializer.fromJson<bool>(json['allViews']),
      allPermissions: serializer.fromJson<bool>(json['allPermissions']),
      rulesJson: serializer.fromJson<String>(json['rulesJson']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
      tokenHash: serializer.fromJson<String>(json['tokenHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientId': serializer.toJson<String>(clientId),
      'isRevoked': serializer.toJson<bool>(isRevoked),
      'agentId': serializer.toJson<String?>(agentId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'allTables': serializer.toJson<bool>(allTables),
      'allViews': serializer.toJson<bool>(allViews),
      'allPermissions': serializer.toJson<bool>(allPermissions),
      'rulesJson': serializer.toJson<String>(rulesJson),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
      'tokenHash': serializer.toJson<String>(tokenHash),
    };
  }

  ClientTokenCacheData copyWith({
    String? id,
    String? clientId,
    bool? isRevoked,
    Value<String?> agentId = const Value.absent(),
    DateTime? createdAt,
    String? payloadJson,
    bool? allTables,
    bool? allViews,
    bool? allPermissions,
    String? rulesJson,
    DateTime? syncedAt,
    String? tokenHash,
  }) => ClientTokenCacheData(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    isRevoked: isRevoked ?? this.isRevoked,
    agentId: agentId.present ? agentId.value : this.agentId,
    createdAt: createdAt ?? this.createdAt,
    payloadJson: payloadJson ?? this.payloadJson,
    allTables: allTables ?? this.allTables,
    allViews: allViews ?? this.allViews,
    allPermissions: allPermissions ?? this.allPermissions,
    rulesJson: rulesJson ?? this.rulesJson,
    syncedAt: syncedAt ?? this.syncedAt,
    tokenHash: tokenHash ?? this.tokenHash,
  );
  ClientTokenCacheData copyWithCompanion(ClientTokenCacheTableCompanion data) {
    return ClientTokenCacheData(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      isRevoked: data.isRevoked.present ? data.isRevoked.value : this.isRevoked,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      allTables: data.allTables.present ? data.allTables.value : this.allTables,
      allViews: data.allViews.present ? data.allViews.value : this.allViews,
      allPermissions: data.allPermissions.present
          ? data.allPermissions.value
          : this.allPermissions,
      rulesJson: data.rulesJson.present ? data.rulesJson.value : this.rulesJson,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      tokenHash: data.tokenHash.present ? data.tokenHash.value : this.tokenHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientTokenCacheData(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('isRevoked: $isRevoked, ')
          ..write('agentId: $agentId, ')
          ..write('createdAt: $createdAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('allTables: $allTables, ')
          ..write('allViews: $allViews, ')
          ..write('allPermissions: $allPermissions, ')
          ..write('rulesJson: $rulesJson, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('tokenHash: $tokenHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientId,
    isRevoked,
    agentId,
    createdAt,
    payloadJson,
    allTables,
    allViews,
    allPermissions,
    rulesJson,
    syncedAt,
    tokenHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientTokenCacheData &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.isRevoked == this.isRevoked &&
          other.agentId == this.agentId &&
          other.createdAt == this.createdAt &&
          other.payloadJson == this.payloadJson &&
          other.allTables == this.allTables &&
          other.allViews == this.allViews &&
          other.allPermissions == this.allPermissions &&
          other.rulesJson == this.rulesJson &&
          other.syncedAt == this.syncedAt &&
          other.tokenHash == this.tokenHash);
}

class ClientTokenCacheTableCompanion
    extends UpdateCompanion<ClientTokenCacheData> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<bool> isRevoked;
  final Value<String?> agentId;
  final Value<DateTime> createdAt;
  final Value<String> payloadJson;
  final Value<bool> allTables;
  final Value<bool> allViews;
  final Value<bool> allPermissions;
  final Value<String> rulesJson;
  final Value<DateTime> syncedAt;
  final Value<String> tokenHash;
  final Value<int> rowid;
  const ClientTokenCacheTableCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.isRevoked = const Value.absent(),
    this.agentId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.allTables = const Value.absent(),
    this.allViews = const Value.absent(),
    this.allPermissions = const Value.absent(),
    this.rulesJson = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientTokenCacheTableCompanion.insert({
    required String id,
    required String clientId,
    this.isRevoked = const Value.absent(),
    this.agentId = const Value.absent(),
    required DateTime createdAt,
    this.payloadJson = const Value.absent(),
    this.allTables = const Value.absent(),
    this.allViews = const Value.absent(),
    this.allPermissions = const Value.absent(),
    this.rulesJson = const Value.absent(),
    required DateTime syncedAt,
    this.tokenHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientId = Value(clientId),
       createdAt = Value(createdAt),
       syncedAt = Value(syncedAt);
  static Insertable<ClientTokenCacheData> custom({
    Expression<String>? id,
    Expression<String>? clientId,
    Expression<bool>? isRevoked,
    Expression<String>? agentId,
    Expression<DateTime>? createdAt,
    Expression<String>? payloadJson,
    Expression<bool>? allTables,
    Expression<bool>? allViews,
    Expression<bool>? allPermissions,
    Expression<String>? rulesJson,
    Expression<DateTime>? syncedAt,
    Expression<String>? tokenHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (isRevoked != null) 'is_revoked': isRevoked,
      if (agentId != null) 'agent_id': agentId,
      if (createdAt != null) 'created_at': createdAt,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (allTables != null) 'all_tables': allTables,
      if (allViews != null) 'all_views': allViews,
      if (allPermissions != null) 'all_permissions': allPermissions,
      if (rulesJson != null) 'rules_json': rulesJson,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (tokenHash != null) 'token_hash': tokenHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientTokenCacheTableCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<bool>? isRevoked,
    Value<String?>? agentId,
    Value<DateTime>? createdAt,
    Value<String>? payloadJson,
    Value<bool>? allTables,
    Value<bool>? allViews,
    Value<bool>? allPermissions,
    Value<String>? rulesJson,
    Value<DateTime>? syncedAt,
    Value<String>? tokenHash,
    Value<int>? rowid,
  }) {
    return ClientTokenCacheTableCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      isRevoked: isRevoked ?? this.isRevoked,
      agentId: agentId ?? this.agentId,
      createdAt: createdAt ?? this.createdAt,
      payloadJson: payloadJson ?? this.payloadJson,
      allTables: allTables ?? this.allTables,
      allViews: allViews ?? this.allViews,
      allPermissions: allPermissions ?? this.allPermissions,
      rulesJson: rulesJson ?? this.rulesJson,
      syncedAt: syncedAt ?? this.syncedAt,
      tokenHash: tokenHash ?? this.tokenHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (isRevoked.present) {
      map['is_revoked'] = Variable<bool>(isRevoked.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (allTables.present) {
      map['all_tables'] = Variable<bool>(allTables.value);
    }
    if (allViews.present) {
      map['all_views'] = Variable<bool>(allViews.value);
    }
    if (allPermissions.present) {
      map['all_permissions'] = Variable<bool>(allPermissions.value);
    }
    if (rulesJson.present) {
      map['rules_json'] = Variable<String>(rulesJson.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (tokenHash.present) {
      map['token_hash'] = Variable<String>(tokenHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientTokenCacheTableCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('isRevoked: $isRevoked, ')
          ..write('agentId: $agentId, ')
          ..write('createdAt: $createdAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('allTables: $allTables, ')
          ..write('allViews: $allViews, ')
          ..write('allPermissions: $allPermissions, ')
          ..write('rulesJson: $rulesJson, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConfigTableTable configTable = $ConfigTableTable(this);
  late final $ClientTokenCacheTableTable clientTokenCacheTable =
      $ClientTokenCacheTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    configTable,
    clientTokenCacheTable,
  ];
}

typedef $$ConfigTableTableCreateCompanionBuilder =
    ConfigTableCompanion Function({
      required String id,
      Value<String> serverUrl,
      Value<String> agentId,
      Value<String?> authToken,
      Value<String?> refreshToken,
      Value<String?> authUsername,
      Value<String?> authPassword,
      required String driverName,
      Value<String> odbcDriverName,
      required String connectionString,
      required String username,
      Value<String?> password,
      required String databaseName,
      required String host,
      required int port,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ConfigTableTableUpdateCompanionBuilder =
    ConfigTableCompanion Function({
      Value<String> id,
      Value<String> serverUrl,
      Value<String> agentId,
      Value<String?> authToken,
      Value<String?> refreshToken,
      Value<String?> authUsername,
      Value<String?> authPassword,
      Value<String> driverName,
      Value<String> odbcDriverName,
      Value<String> connectionString,
      Value<String> username,
      Value<String?> password,
      Value<String> databaseName,
      Value<String> host,
      Value<int> port,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ConfigTableTableFilterComposer
    extends Composer<_$AppDatabase, $ConfigTableTable> {
  $$ConfigTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverUrl => $composableBuilder(
    column: $table.serverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authToken => $composableBuilder(
    column: $table.authToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refreshToken => $composableBuilder(
    column: $table.refreshToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authUsername => $composableBuilder(
    column: $table.authUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authPassword => $composableBuilder(
    column: $table.authPassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get driverName => $composableBuilder(
    column: $table.driverName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get odbcDriverName => $composableBuilder(
    column: $table.odbcDriverName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionString => $composableBuilder(
    column: $table.connectionString,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConfigTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ConfigTableTable> {
  $$ConfigTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverUrl => $composableBuilder(
    column: $table.serverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authToken => $composableBuilder(
    column: $table.authToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refreshToken => $composableBuilder(
    column: $table.refreshToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authUsername => $composableBuilder(
    column: $table.authUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authPassword => $composableBuilder(
    column: $table.authPassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get driverName => $composableBuilder(
    column: $table.driverName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get odbcDriverName => $composableBuilder(
    column: $table.odbcDriverName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionString => $composableBuilder(
    column: $table.connectionString,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConfigTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConfigTableTable> {
  $$ConfigTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverUrl =>
      $composableBuilder(column: $table.serverUrl, builder: (column) => column);

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<String> get authToken =>
      $composableBuilder(column: $table.authToken, builder: (column) => column);

  GeneratedColumn<String> get refreshToken => $composableBuilder(
    column: $table.refreshToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authUsername => $composableBuilder(
    column: $table.authUsername,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authPassword => $composableBuilder(
    column: $table.authPassword,
    builder: (column) => column,
  );

  GeneratedColumn<String> get driverName => $composableBuilder(
    column: $table.driverName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get odbcDriverName => $composableBuilder(
    column: $table.odbcDriverName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get connectionString => $composableBuilder(
    column: $table.connectionString,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConfigTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConfigTableTable,
          ConfigData,
          $$ConfigTableTableFilterComposer,
          $$ConfigTableTableOrderingComposer,
          $$ConfigTableTableAnnotationComposer,
          $$ConfigTableTableCreateCompanionBuilder,
          $$ConfigTableTableUpdateCompanionBuilder,
          (
            ConfigData,
            BaseReferences<_$AppDatabase, $ConfigTableTable, ConfigData>,
          ),
          ConfigData,
          PrefetchHooks Function()
        > {
  $$ConfigTableTableTableManager(_$AppDatabase db, $ConfigTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConfigTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConfigTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConfigTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> serverUrl = const Value.absent(),
                Value<String> agentId = const Value.absent(),
                Value<String?> authToken = const Value.absent(),
                Value<String?> refreshToken = const Value.absent(),
                Value<String?> authUsername = const Value.absent(),
                Value<String?> authPassword = const Value.absent(),
                Value<String> driverName = const Value.absent(),
                Value<String> odbcDriverName = const Value.absent(),
                Value<String> connectionString = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String?> password = const Value.absent(),
                Value<String> databaseName = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConfigTableCompanion(
                id: id,
                serverUrl: serverUrl,
                agentId: agentId,
                authToken: authToken,
                refreshToken: refreshToken,
                authUsername: authUsername,
                authPassword: authPassword,
                driverName: driverName,
                odbcDriverName: odbcDriverName,
                connectionString: connectionString,
                username: username,
                password: password,
                databaseName: databaseName,
                host: host,
                port: port,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> serverUrl = const Value.absent(),
                Value<String> agentId = const Value.absent(),
                Value<String?> authToken = const Value.absent(),
                Value<String?> refreshToken = const Value.absent(),
                Value<String?> authUsername = const Value.absent(),
                Value<String?> authPassword = const Value.absent(),
                required String driverName,
                Value<String> odbcDriverName = const Value.absent(),
                required String connectionString,
                required String username,
                Value<String?> password = const Value.absent(),
                required String databaseName,
                required String host,
                required int port,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConfigTableCompanion.insert(
                id: id,
                serverUrl: serverUrl,
                agentId: agentId,
                authToken: authToken,
                refreshToken: refreshToken,
                authUsername: authUsername,
                authPassword: authPassword,
                driverName: driverName,
                odbcDriverName: odbcDriverName,
                connectionString: connectionString,
                username: username,
                password: password,
                databaseName: databaseName,
                host: host,
                port: port,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConfigTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConfigTableTable,
      ConfigData,
      $$ConfigTableTableFilterComposer,
      $$ConfigTableTableOrderingComposer,
      $$ConfigTableTableAnnotationComposer,
      $$ConfigTableTableCreateCompanionBuilder,
      $$ConfigTableTableUpdateCompanionBuilder,
      (
        ConfigData,
        BaseReferences<_$AppDatabase, $ConfigTableTable, ConfigData>,
      ),
      ConfigData,
      PrefetchHooks Function()
    >;
typedef $$ClientTokenCacheTableTableCreateCompanionBuilder =
    ClientTokenCacheTableCompanion Function({
      required String id,
      required String clientId,
      Value<bool> isRevoked,
      Value<String?> agentId,
      required DateTime createdAt,
      Value<String> payloadJson,
      Value<bool> allTables,
      Value<bool> allViews,
      Value<bool> allPermissions,
      Value<String> rulesJson,
      required DateTime syncedAt,
      Value<String> tokenHash,
      Value<int> rowid,
    });
typedef $$ClientTokenCacheTableTableUpdateCompanionBuilder =
    ClientTokenCacheTableCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<bool> isRevoked,
      Value<String?> agentId,
      Value<DateTime> createdAt,
      Value<String> payloadJson,
      Value<bool> allTables,
      Value<bool> allViews,
      Value<bool> allPermissions,
      Value<String> rulesJson,
      Value<DateTime> syncedAt,
      Value<String> tokenHash,
      Value<int> rowid,
    });

class $$ClientTokenCacheTableTableFilterComposer
    extends Composer<_$AppDatabase, $ClientTokenCacheTableTable> {
  $$ClientTokenCacheTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRevoked => $composableBuilder(
    column: $table.isRevoked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allTables => $composableBuilder(
    column: $table.allTables,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allViews => $composableBuilder(
    column: $table.allViews,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allPermissions => $composableBuilder(
    column: $table.allPermissions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rulesJson => $composableBuilder(
    column: $table.rulesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientTokenCacheTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientTokenCacheTableTable> {
  $$ClientTokenCacheTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRevoked => $composableBuilder(
    column: $table.isRevoked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allTables => $composableBuilder(
    column: $table.allTables,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allViews => $composableBuilder(
    column: $table.allViews,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allPermissions => $composableBuilder(
    column: $table.allPermissions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rulesJson => $composableBuilder(
    column: $table.rulesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientTokenCacheTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientTokenCacheTableTable> {
  $$ClientTokenCacheTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<bool> get isRevoked =>
      $composableBuilder(column: $table.isRevoked, builder: (column) => column);

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allTables =>
      $composableBuilder(column: $table.allTables, builder: (column) => column);

  GeneratedColumn<bool> get allViews =>
      $composableBuilder(column: $table.allViews, builder: (column) => column);

  GeneratedColumn<bool> get allPermissions => $composableBuilder(
    column: $table.allPermissions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rulesJson =>
      $composableBuilder(column: $table.rulesJson, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<String> get tokenHash =>
      $composableBuilder(column: $table.tokenHash, builder: (column) => column);
}

class $$ClientTokenCacheTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientTokenCacheTableTable,
          ClientTokenCacheData,
          $$ClientTokenCacheTableTableFilterComposer,
          $$ClientTokenCacheTableTableOrderingComposer,
          $$ClientTokenCacheTableTableAnnotationComposer,
          $$ClientTokenCacheTableTableCreateCompanionBuilder,
          $$ClientTokenCacheTableTableUpdateCompanionBuilder,
          (
            ClientTokenCacheData,
            BaseReferences<
              _$AppDatabase,
              $ClientTokenCacheTableTable,
              ClientTokenCacheData
            >,
          ),
          ClientTokenCacheData,
          PrefetchHooks Function()
        > {
  $$ClientTokenCacheTableTableTableManager(
    _$AppDatabase db,
    $ClientTokenCacheTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientTokenCacheTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ClientTokenCacheTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ClientTokenCacheTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<bool> isRevoked = const Value.absent(),
                Value<String?> agentId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<bool> allTables = const Value.absent(),
                Value<bool> allViews = const Value.absent(),
                Value<bool> allPermissions = const Value.absent(),
                Value<String> rulesJson = const Value.absent(),
                Value<DateTime> syncedAt = const Value.absent(),
                Value<String> tokenHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientTokenCacheTableCompanion(
                id: id,
                clientId: clientId,
                isRevoked: isRevoked,
                agentId: agentId,
                createdAt: createdAt,
                payloadJson: payloadJson,
                allTables: allTables,
                allViews: allViews,
                allPermissions: allPermissions,
                rulesJson: rulesJson,
                syncedAt: syncedAt,
                tokenHash: tokenHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                Value<bool> isRevoked = const Value.absent(),
                Value<String?> agentId = const Value.absent(),
                required DateTime createdAt,
                Value<String> payloadJson = const Value.absent(),
                Value<bool> allTables = const Value.absent(),
                Value<bool> allViews = const Value.absent(),
                Value<bool> allPermissions = const Value.absent(),
                Value<String> rulesJson = const Value.absent(),
                required DateTime syncedAt,
                Value<String> tokenHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientTokenCacheTableCompanion.insert(
                id: id,
                clientId: clientId,
                isRevoked: isRevoked,
                agentId: agentId,
                createdAt: createdAt,
                payloadJson: payloadJson,
                allTables: allTables,
                allViews: allViews,
                allPermissions: allPermissions,
                rulesJson: rulesJson,
                syncedAt: syncedAt,
                tokenHash: tokenHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientTokenCacheTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientTokenCacheTableTable,
      ClientTokenCacheData,
      $$ClientTokenCacheTableTableFilterComposer,
      $$ClientTokenCacheTableTableOrderingComposer,
      $$ClientTokenCacheTableTableAnnotationComposer,
      $$ClientTokenCacheTableTableCreateCompanionBuilder,
      $$ClientTokenCacheTableTableUpdateCompanionBuilder,
      (
        ClientTokenCacheData,
        BaseReferences<
          _$AppDatabase,
          $ClientTokenCacheTableTable,
          ClientTokenCacheData
        >,
      ),
      ClientTokenCacheData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConfigTableTableTableManager get configTable =>
      $$ConfigTableTableTableManager(_db, _db.configTable);
  $$ClientTokenCacheTableTableTableManager get clientTokenCacheTable =>
      $$ClientTokenCacheTableTableTableManager(_db, _db.clientTokenCacheTable);
}
