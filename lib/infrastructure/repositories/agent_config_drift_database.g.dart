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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConfigTableTable configTable = $ConfigTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [configTable];
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConfigTableTableTableManager get configTable =>
      $$ConfigTableTableTableManager(_db, _db.configTable);
}
