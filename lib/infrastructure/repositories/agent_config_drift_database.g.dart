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
  static const VerificationMeta _nomeMeta = const VerificationMeta('nome');
  @override
  late final GeneratedColumn<String> nome = GeneratedColumn<String>(
    'nome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nomeFantasiaMeta = const VerificationMeta(
    'nomeFantasia',
  );
  @override
  late final GeneratedColumn<String> nomeFantasia = GeneratedColumn<String>(
    'nome_fantasia',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _cnaeCnpjCpfMeta = const VerificationMeta(
    'cnaeCnpjCpf',
  );
  @override
  late final GeneratedColumn<String> cnaeCnpjCpf = GeneratedColumn<String>(
    'cnae_cnpj_cpf',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _telefoneMeta = const VerificationMeta(
    'telefone',
  );
  @override
  late final GeneratedColumn<String> telefone = GeneratedColumn<String>(
    'telefone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _celularMeta = const VerificationMeta(
    'celular',
  );
  @override
  late final GeneratedColumn<String> celular = GeneratedColumn<String>(
    'celular',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _enderecoMeta = const VerificationMeta(
    'endereco',
  );
  @override
  late final GeneratedColumn<String> endereco = GeneratedColumn<String>(
    'endereco',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _numeroEnderecoMeta = const VerificationMeta(
    'numeroEndereco',
  );
  @override
  late final GeneratedColumn<String> numeroEndereco = GeneratedColumn<String>(
    'numero_endereco',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bairroMeta = const VerificationMeta('bairro');
  @override
  late final GeneratedColumn<String> bairro = GeneratedColumn<String>(
    'bairro',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _cepMeta = const VerificationMeta('cep');
  @override
  late final GeneratedColumn<String> cep = GeneratedColumn<String>(
    'cep',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nomeMunicipioMeta = const VerificationMeta(
    'nomeMunicipio',
  );
  @override
  late final GeneratedColumn<String> nomeMunicipio = GeneratedColumn<String>(
    'nome_municipio',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ufMunicipioMeta = const VerificationMeta(
    'ufMunicipio',
  );
  @override
  late final GeneratedColumn<String> ufMunicipio = GeneratedColumn<String>(
    'uf_municipio',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _observacaoMeta = const VerificationMeta(
    'observacao',
  );
  @override
  late final GeneratedColumn<String> observacao = GeneratedColumn<String>(
    'observacao',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _hubProfileVersionMeta = const VerificationMeta(
    'hubProfileVersion',
  );
  @override
  late final GeneratedColumn<int> hubProfileVersion = GeneratedColumn<int>(
    'hub_profile_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hubProfileUpdatedAtMeta =
      const VerificationMeta('hubProfileUpdatedAt');
  @override
  late final GeneratedColumn<String> hubProfileUpdatedAt =
      GeneratedColumn<String>(
        'hub_profile_updated_at',
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
    nome,
    nomeFantasia,
    cnaeCnpjCpf,
    telefone,
    celular,
    email,
    endereco,
    numeroEndereco,
    bairro,
    cep,
    nomeMunicipio,
    ufMunicipio,
    observacao,
    hubProfileVersion,
    hubProfileUpdatedAt,
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
    if (data.containsKey('nome')) {
      context.handle(
        _nomeMeta,
        nome.isAcceptableOrUnknown(data['nome']!, _nomeMeta),
      );
    }
    if (data.containsKey('nome_fantasia')) {
      context.handle(
        _nomeFantasiaMeta,
        nomeFantasia.isAcceptableOrUnknown(
          data['nome_fantasia']!,
          _nomeFantasiaMeta,
        ),
      );
    }
    if (data.containsKey('cnae_cnpj_cpf')) {
      context.handle(
        _cnaeCnpjCpfMeta,
        cnaeCnpjCpf.isAcceptableOrUnknown(
          data['cnae_cnpj_cpf']!,
          _cnaeCnpjCpfMeta,
        ),
      );
    }
    if (data.containsKey('telefone')) {
      context.handle(
        _telefoneMeta,
        telefone.isAcceptableOrUnknown(data['telefone']!, _telefoneMeta),
      );
    }
    if (data.containsKey('celular')) {
      context.handle(
        _celularMeta,
        celular.isAcceptableOrUnknown(data['celular']!, _celularMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('endereco')) {
      context.handle(
        _enderecoMeta,
        endereco.isAcceptableOrUnknown(data['endereco']!, _enderecoMeta),
      );
    }
    if (data.containsKey('numero_endereco')) {
      context.handle(
        _numeroEnderecoMeta,
        numeroEndereco.isAcceptableOrUnknown(
          data['numero_endereco']!,
          _numeroEnderecoMeta,
        ),
      );
    }
    if (data.containsKey('bairro')) {
      context.handle(
        _bairroMeta,
        bairro.isAcceptableOrUnknown(data['bairro']!, _bairroMeta),
      );
    }
    if (data.containsKey('cep')) {
      context.handle(
        _cepMeta,
        cep.isAcceptableOrUnknown(data['cep']!, _cepMeta),
      );
    }
    if (data.containsKey('nome_municipio')) {
      context.handle(
        _nomeMunicipioMeta,
        nomeMunicipio.isAcceptableOrUnknown(
          data['nome_municipio']!,
          _nomeMunicipioMeta,
        ),
      );
    }
    if (data.containsKey('uf_municipio')) {
      context.handle(
        _ufMunicipioMeta,
        ufMunicipio.isAcceptableOrUnknown(
          data['uf_municipio']!,
          _ufMunicipioMeta,
        ),
      );
    }
    if (data.containsKey('observacao')) {
      context.handle(
        _observacaoMeta,
        observacao.isAcceptableOrUnknown(data['observacao']!, _observacaoMeta),
      );
    }
    if (data.containsKey('hub_profile_version')) {
      context.handle(
        _hubProfileVersionMeta,
        hubProfileVersion.isAcceptableOrUnknown(
          data['hub_profile_version']!,
          _hubProfileVersionMeta,
        ),
      );
    }
    if (data.containsKey('hub_profile_updated_at')) {
      context.handle(
        _hubProfileUpdatedAtMeta,
        hubProfileUpdatedAt.isAcceptableOrUnknown(
          data['hub_profile_updated_at']!,
          _hubProfileUpdatedAtMeta,
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
      nome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nome'],
      )!,
      nomeFantasia: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nome_fantasia'],
      )!,
      cnaeCnpjCpf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cnae_cnpj_cpf'],
      )!,
      telefone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}telefone'],
      )!,
      celular: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}celular'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      endereco: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endereco'],
      )!,
      numeroEndereco: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}numero_endereco'],
      )!,
      bairro: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bairro'],
      )!,
      cep: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cep'],
      )!,
      nomeMunicipio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nome_municipio'],
      )!,
      ufMunicipio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uf_municipio'],
      )!,
      observacao: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observacao'],
      )!,
      hubProfileVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hub_profile_version'],
      ),
      hubProfileUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hub_profile_updated_at'],
      ),
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
  final String nome;
  final String nomeFantasia;
  final String cnaeCnpjCpf;
  final String telefone;
  final String celular;
  final String email;
  final String endereco;
  final String numeroEndereco;
  final String bairro;
  final String cep;
  final String nomeMunicipio;
  final String ufMunicipio;
  final String observacao;
  final int? hubProfileVersion;
  final String? hubProfileUpdatedAt;
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
    required this.nome,
    required this.nomeFantasia,
    required this.cnaeCnpjCpf,
    required this.telefone,
    required this.celular,
    required this.email,
    required this.endereco,
    required this.numeroEndereco,
    required this.bairro,
    required this.cep,
    required this.nomeMunicipio,
    required this.ufMunicipio,
    required this.observacao,
    this.hubProfileVersion,
    this.hubProfileUpdatedAt,
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
    map['nome'] = Variable<String>(nome);
    map['nome_fantasia'] = Variable<String>(nomeFantasia);
    map['cnae_cnpj_cpf'] = Variable<String>(cnaeCnpjCpf);
    map['telefone'] = Variable<String>(telefone);
    map['celular'] = Variable<String>(celular);
    map['email'] = Variable<String>(email);
    map['endereco'] = Variable<String>(endereco);
    map['numero_endereco'] = Variable<String>(numeroEndereco);
    map['bairro'] = Variable<String>(bairro);
    map['cep'] = Variable<String>(cep);
    map['nome_municipio'] = Variable<String>(nomeMunicipio);
    map['uf_municipio'] = Variable<String>(ufMunicipio);
    map['observacao'] = Variable<String>(observacao);
    if (!nullToAbsent || hubProfileVersion != null) {
      map['hub_profile_version'] = Variable<int>(hubProfileVersion);
    }
    if (!nullToAbsent || hubProfileUpdatedAt != null) {
      map['hub_profile_updated_at'] = Variable<String>(hubProfileUpdatedAt);
    }
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
      nome: Value(nome),
      nomeFantasia: Value(nomeFantasia),
      cnaeCnpjCpf: Value(cnaeCnpjCpf),
      telefone: Value(telefone),
      celular: Value(celular),
      email: Value(email),
      endereco: Value(endereco),
      numeroEndereco: Value(numeroEndereco),
      bairro: Value(bairro),
      cep: Value(cep),
      nomeMunicipio: Value(nomeMunicipio),
      ufMunicipio: Value(ufMunicipio),
      observacao: Value(observacao),
      hubProfileVersion: hubProfileVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(hubProfileVersion),
      hubProfileUpdatedAt: hubProfileUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(hubProfileUpdatedAt),
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
      nome: serializer.fromJson<String>(json['nome']),
      nomeFantasia: serializer.fromJson<String>(json['nomeFantasia']),
      cnaeCnpjCpf: serializer.fromJson<String>(json['cnaeCnpjCpf']),
      telefone: serializer.fromJson<String>(json['telefone']),
      celular: serializer.fromJson<String>(json['celular']),
      email: serializer.fromJson<String>(json['email']),
      endereco: serializer.fromJson<String>(json['endereco']),
      numeroEndereco: serializer.fromJson<String>(json['numeroEndereco']),
      bairro: serializer.fromJson<String>(json['bairro']),
      cep: serializer.fromJson<String>(json['cep']),
      nomeMunicipio: serializer.fromJson<String>(json['nomeMunicipio']),
      ufMunicipio: serializer.fromJson<String>(json['ufMunicipio']),
      observacao: serializer.fromJson<String>(json['observacao']),
      hubProfileVersion: serializer.fromJson<int?>(json['hubProfileVersion']),
      hubProfileUpdatedAt: serializer.fromJson<String?>(
        json['hubProfileUpdatedAt'],
      ),
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
      'nome': serializer.toJson<String>(nome),
      'nomeFantasia': serializer.toJson<String>(nomeFantasia),
      'cnaeCnpjCpf': serializer.toJson<String>(cnaeCnpjCpf),
      'telefone': serializer.toJson<String>(telefone),
      'celular': serializer.toJson<String>(celular),
      'email': serializer.toJson<String>(email),
      'endereco': serializer.toJson<String>(endereco),
      'numeroEndereco': serializer.toJson<String>(numeroEndereco),
      'bairro': serializer.toJson<String>(bairro),
      'cep': serializer.toJson<String>(cep),
      'nomeMunicipio': serializer.toJson<String>(nomeMunicipio),
      'ufMunicipio': serializer.toJson<String>(ufMunicipio),
      'observacao': serializer.toJson<String>(observacao),
      'hubProfileVersion': serializer.toJson<int?>(hubProfileVersion),
      'hubProfileUpdatedAt': serializer.toJson<String?>(hubProfileUpdatedAt),
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
    String? nome,
    String? nomeFantasia,
    String? cnaeCnpjCpf,
    String? telefone,
    String? celular,
    String? email,
    String? endereco,
    String? numeroEndereco,
    String? bairro,
    String? cep,
    String? nomeMunicipio,
    String? ufMunicipio,
    String? observacao,
    Value<int?> hubProfileVersion = const Value.absent(),
    Value<String?> hubProfileUpdatedAt = const Value.absent(),
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
    nome: nome ?? this.nome,
    nomeFantasia: nomeFantasia ?? this.nomeFantasia,
    cnaeCnpjCpf: cnaeCnpjCpf ?? this.cnaeCnpjCpf,
    telefone: telefone ?? this.telefone,
    celular: celular ?? this.celular,
    email: email ?? this.email,
    endereco: endereco ?? this.endereco,
    numeroEndereco: numeroEndereco ?? this.numeroEndereco,
    bairro: bairro ?? this.bairro,
    cep: cep ?? this.cep,
    nomeMunicipio: nomeMunicipio ?? this.nomeMunicipio,
    ufMunicipio: ufMunicipio ?? this.ufMunicipio,
    observacao: observacao ?? this.observacao,
    hubProfileVersion: hubProfileVersion.present
        ? hubProfileVersion.value
        : this.hubProfileVersion,
    hubProfileUpdatedAt: hubProfileUpdatedAt.present
        ? hubProfileUpdatedAt.value
        : this.hubProfileUpdatedAt,
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
      nome: data.nome.present ? data.nome.value : this.nome,
      nomeFantasia: data.nomeFantasia.present
          ? data.nomeFantasia.value
          : this.nomeFantasia,
      cnaeCnpjCpf: data.cnaeCnpjCpf.present
          ? data.cnaeCnpjCpf.value
          : this.cnaeCnpjCpf,
      telefone: data.telefone.present ? data.telefone.value : this.telefone,
      celular: data.celular.present ? data.celular.value : this.celular,
      email: data.email.present ? data.email.value : this.email,
      endereco: data.endereco.present ? data.endereco.value : this.endereco,
      numeroEndereco: data.numeroEndereco.present
          ? data.numeroEndereco.value
          : this.numeroEndereco,
      bairro: data.bairro.present ? data.bairro.value : this.bairro,
      cep: data.cep.present ? data.cep.value : this.cep,
      nomeMunicipio: data.nomeMunicipio.present
          ? data.nomeMunicipio.value
          : this.nomeMunicipio,
      ufMunicipio: data.ufMunicipio.present
          ? data.ufMunicipio.value
          : this.ufMunicipio,
      observacao: data.observacao.present
          ? data.observacao.value
          : this.observacao,
      hubProfileVersion: data.hubProfileVersion.present
          ? data.hubProfileVersion.value
          : this.hubProfileVersion,
      hubProfileUpdatedAt: data.hubProfileUpdatedAt.present
          ? data.hubProfileUpdatedAt.value
          : this.hubProfileUpdatedAt,
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
          ..write('nome: $nome, ')
          ..write('nomeFantasia: $nomeFantasia, ')
          ..write('cnaeCnpjCpf: $cnaeCnpjCpf, ')
          ..write('telefone: $telefone, ')
          ..write('celular: $celular, ')
          ..write('email: $email, ')
          ..write('endereco: $endereco, ')
          ..write('numeroEndereco: $numeroEndereco, ')
          ..write('bairro: $bairro, ')
          ..write('cep: $cep, ')
          ..write('nomeMunicipio: $nomeMunicipio, ')
          ..write('ufMunicipio: $ufMunicipio, ')
          ..write('observacao: $observacao, ')
          ..write('hubProfileVersion: $hubProfileVersion, ')
          ..write('hubProfileUpdatedAt: $hubProfileUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
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
    nome,
    nomeFantasia,
    cnaeCnpjCpf,
    telefone,
    celular,
    email,
    endereco,
    numeroEndereco,
    bairro,
    cep,
    nomeMunicipio,
    ufMunicipio,
    observacao,
    hubProfileVersion,
    hubProfileUpdatedAt,
    createdAt,
    updatedAt,
  ]);
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
          other.nome == this.nome &&
          other.nomeFantasia == this.nomeFantasia &&
          other.cnaeCnpjCpf == this.cnaeCnpjCpf &&
          other.telefone == this.telefone &&
          other.celular == this.celular &&
          other.email == this.email &&
          other.endereco == this.endereco &&
          other.numeroEndereco == this.numeroEndereco &&
          other.bairro == this.bairro &&
          other.cep == this.cep &&
          other.nomeMunicipio == this.nomeMunicipio &&
          other.ufMunicipio == this.ufMunicipio &&
          other.observacao == this.observacao &&
          other.hubProfileVersion == this.hubProfileVersion &&
          other.hubProfileUpdatedAt == this.hubProfileUpdatedAt &&
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
  final Value<String> nome;
  final Value<String> nomeFantasia;
  final Value<String> cnaeCnpjCpf;
  final Value<String> telefone;
  final Value<String> celular;
  final Value<String> email;
  final Value<String> endereco;
  final Value<String> numeroEndereco;
  final Value<String> bairro;
  final Value<String> cep;
  final Value<String> nomeMunicipio;
  final Value<String> ufMunicipio;
  final Value<String> observacao;
  final Value<int?> hubProfileVersion;
  final Value<String?> hubProfileUpdatedAt;
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
    this.nome = const Value.absent(),
    this.nomeFantasia = const Value.absent(),
    this.cnaeCnpjCpf = const Value.absent(),
    this.telefone = const Value.absent(),
    this.celular = const Value.absent(),
    this.email = const Value.absent(),
    this.endereco = const Value.absent(),
    this.numeroEndereco = const Value.absent(),
    this.bairro = const Value.absent(),
    this.cep = const Value.absent(),
    this.nomeMunicipio = const Value.absent(),
    this.ufMunicipio = const Value.absent(),
    this.observacao = const Value.absent(),
    this.hubProfileVersion = const Value.absent(),
    this.hubProfileUpdatedAt = const Value.absent(),
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
    this.nome = const Value.absent(),
    this.nomeFantasia = const Value.absent(),
    this.cnaeCnpjCpf = const Value.absent(),
    this.telefone = const Value.absent(),
    this.celular = const Value.absent(),
    this.email = const Value.absent(),
    this.endereco = const Value.absent(),
    this.numeroEndereco = const Value.absent(),
    this.bairro = const Value.absent(),
    this.cep = const Value.absent(),
    this.nomeMunicipio = const Value.absent(),
    this.ufMunicipio = const Value.absent(),
    this.observacao = const Value.absent(),
    this.hubProfileVersion = const Value.absent(),
    this.hubProfileUpdatedAt = const Value.absent(),
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
    Expression<String>? nome,
    Expression<String>? nomeFantasia,
    Expression<String>? cnaeCnpjCpf,
    Expression<String>? telefone,
    Expression<String>? celular,
    Expression<String>? email,
    Expression<String>? endereco,
    Expression<String>? numeroEndereco,
    Expression<String>? bairro,
    Expression<String>? cep,
    Expression<String>? nomeMunicipio,
    Expression<String>? ufMunicipio,
    Expression<String>? observacao,
    Expression<int>? hubProfileVersion,
    Expression<String>? hubProfileUpdatedAt,
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
      if (nome != null) 'nome': nome,
      if (nomeFantasia != null) 'nome_fantasia': nomeFantasia,
      if (cnaeCnpjCpf != null) 'cnae_cnpj_cpf': cnaeCnpjCpf,
      if (telefone != null) 'telefone': telefone,
      if (celular != null) 'celular': celular,
      if (email != null) 'email': email,
      if (endereco != null) 'endereco': endereco,
      if (numeroEndereco != null) 'numero_endereco': numeroEndereco,
      if (bairro != null) 'bairro': bairro,
      if (cep != null) 'cep': cep,
      if (nomeMunicipio != null) 'nome_municipio': nomeMunicipio,
      if (ufMunicipio != null) 'uf_municipio': ufMunicipio,
      if (observacao != null) 'observacao': observacao,
      if (hubProfileVersion != null) 'hub_profile_version': hubProfileVersion,
      if (hubProfileUpdatedAt != null)
        'hub_profile_updated_at': hubProfileUpdatedAt,
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
    Value<String>? nome,
    Value<String>? nomeFantasia,
    Value<String>? cnaeCnpjCpf,
    Value<String>? telefone,
    Value<String>? celular,
    Value<String>? email,
    Value<String>? endereco,
    Value<String>? numeroEndereco,
    Value<String>? bairro,
    Value<String>? cep,
    Value<String>? nomeMunicipio,
    Value<String>? ufMunicipio,
    Value<String>? observacao,
    Value<int?>? hubProfileVersion,
    Value<String?>? hubProfileUpdatedAt,
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
      nome: nome ?? this.nome,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      cnaeCnpjCpf: cnaeCnpjCpf ?? this.cnaeCnpjCpf,
      telefone: telefone ?? this.telefone,
      celular: celular ?? this.celular,
      email: email ?? this.email,
      endereco: endereco ?? this.endereco,
      numeroEndereco: numeroEndereco ?? this.numeroEndereco,
      bairro: bairro ?? this.bairro,
      cep: cep ?? this.cep,
      nomeMunicipio: nomeMunicipio ?? this.nomeMunicipio,
      ufMunicipio: ufMunicipio ?? this.ufMunicipio,
      observacao: observacao ?? this.observacao,
      hubProfileVersion: hubProfileVersion ?? this.hubProfileVersion,
      hubProfileUpdatedAt: hubProfileUpdatedAt ?? this.hubProfileUpdatedAt,
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
    if (nome.present) {
      map['nome'] = Variable<String>(nome.value);
    }
    if (nomeFantasia.present) {
      map['nome_fantasia'] = Variable<String>(nomeFantasia.value);
    }
    if (cnaeCnpjCpf.present) {
      map['cnae_cnpj_cpf'] = Variable<String>(cnaeCnpjCpf.value);
    }
    if (telefone.present) {
      map['telefone'] = Variable<String>(telefone.value);
    }
    if (celular.present) {
      map['celular'] = Variable<String>(celular.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (endereco.present) {
      map['endereco'] = Variable<String>(endereco.value);
    }
    if (numeroEndereco.present) {
      map['numero_endereco'] = Variable<String>(numeroEndereco.value);
    }
    if (bairro.present) {
      map['bairro'] = Variable<String>(bairro.value);
    }
    if (cep.present) {
      map['cep'] = Variable<String>(cep.value);
    }
    if (nomeMunicipio.present) {
      map['nome_municipio'] = Variable<String>(nomeMunicipio.value);
    }
    if (ufMunicipio.present) {
      map['uf_municipio'] = Variable<String>(ufMunicipio.value);
    }
    if (observacao.present) {
      map['observacao'] = Variable<String>(observacao.value);
    }
    if (hubProfileVersion.present) {
      map['hub_profile_version'] = Variable<int>(hubProfileVersion.value);
    }
    if (hubProfileUpdatedAt.present) {
      map['hub_profile_updated_at'] = Variable<String>(
        hubProfileUpdatedAt.value,
      );
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
          ..write('nome: $nome, ')
          ..write('nomeFantasia: $nomeFantasia, ')
          ..write('cnaeCnpjCpf: $cnaeCnpjCpf, ')
          ..write('telefone: $telefone, ')
          ..write('celular: $celular, ')
          ..write('email: $email, ')
          ..write('endereco: $endereco, ')
          ..write('numeroEndereco: $numeroEndereco, ')
          ..write('bairro: $bairro, ')
          ..write('cep: $cep, ')
          ..write('nomeMunicipio: $nomeMunicipio, ')
          ..write('ufMunicipio: $ufMunicipio, ')
          ..write('observacao: $observacao, ')
          ..write('hubProfileVersion: $hubProfileVersion, ')
          ..write('hubProfileUpdatedAt: $hubProfileUpdatedAt, ')
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _tokenValueMeta = const VerificationMeta(
    'tokenValue',
  );
  @override
  late final GeneratedColumn<String> tokenValue = GeneratedColumn<String>(
    'token_value',
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
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
  static const VerificationMeta _globalPermissionsJsonMeta =
      const VerificationMeta('globalPermissionsJson');
  @override
  late final GeneratedColumn<String> globalPermissionsJson =
      GeneratedColumn<String>(
        'global_permissions_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(
          '{"read":false,"update":false,"delete":false,"ddl":false}',
        ),
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
    name,
    isRevoked,
    version,
    agentId,
    tokenValue,
    createdAt,
    updatedAt,
    payloadJson,
    allTables,
    allViews,
    allPermissions,
    globalPermissionsJson,
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
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('is_revoked')) {
      context.handle(
        _isRevokedMeta,
        isRevoked.isAcceptableOrUnknown(data['is_revoked']!, _isRevokedMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('agent_id')) {
      context.handle(
        _agentIdMeta,
        agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta),
      );
    }
    if (data.containsKey('token_value')) {
      context.handle(
        _tokenValueMeta,
        tokenValue.isAcceptableOrUnknown(data['token_value']!, _tokenValueMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
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
    if (data.containsKey('global_permissions_json')) {
      context.handle(
        _globalPermissionsJsonMeta,
        globalPermissionsJson.isAcceptableOrUnknown(
          data['global_permissions_json']!,
          _globalPermissionsJsonMeta,
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
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isRevoked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_revoked'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      agentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_id'],
      ),
      tokenValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_value'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
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
      globalPermissionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}global_permissions_json'],
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
  final String name;
  final bool isRevoked;
  final int version;
  final String? agentId;
  final String? tokenValue;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String payloadJson;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final String globalPermissionsJson;
  final String rulesJson;
  final DateTime syncedAt;
  final String tokenHash;
  const ClientTokenCacheData({
    required this.id,
    required this.clientId,
    required this.name,
    required this.isRevoked,
    required this.version,
    this.agentId,
    this.tokenValue,
    required this.createdAt,
    this.updatedAt,
    required this.payloadJson,
    required this.allTables,
    required this.allViews,
    required this.allPermissions,
    required this.globalPermissionsJson,
    required this.rulesJson,
    required this.syncedAt,
    required this.tokenHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['name'] = Variable<String>(name);
    map['is_revoked'] = Variable<bool>(isRevoked);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || agentId != null) {
      map['agent_id'] = Variable<String>(agentId);
    }
    if (!nullToAbsent || tokenValue != null) {
      map['token_value'] = Variable<String>(tokenValue);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['all_tables'] = Variable<bool>(allTables);
    map['all_views'] = Variable<bool>(allViews);
    map['all_permissions'] = Variable<bool>(allPermissions);
    map['global_permissions_json'] = Variable<String>(globalPermissionsJson);
    map['rules_json'] = Variable<String>(rulesJson);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    map['token_hash'] = Variable<String>(tokenHash);
    return map;
  }

  ClientTokenCacheTableCompanion toCompanion(bool nullToAbsent) {
    return ClientTokenCacheTableCompanion(
      id: Value(id),
      clientId: Value(clientId),
      name: Value(name),
      isRevoked: Value(isRevoked),
      version: Value(version),
      agentId: agentId == null && nullToAbsent
          ? const Value.absent()
          : Value(agentId),
      tokenValue: tokenValue == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenValue),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      payloadJson: Value(payloadJson),
      allTables: Value(allTables),
      allViews: Value(allViews),
      allPermissions: Value(allPermissions),
      globalPermissionsJson: Value(globalPermissionsJson),
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
      name: serializer.fromJson<String>(json['name']),
      isRevoked: serializer.fromJson<bool>(json['isRevoked']),
      version: serializer.fromJson<int>(json['version']),
      agentId: serializer.fromJson<String?>(json['agentId']),
      tokenValue: serializer.fromJson<String?>(json['tokenValue']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      allTables: serializer.fromJson<bool>(json['allTables']),
      allViews: serializer.fromJson<bool>(json['allViews']),
      allPermissions: serializer.fromJson<bool>(json['allPermissions']),
      globalPermissionsJson: serializer.fromJson<String>(
        json['globalPermissionsJson'],
      ),
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
      'name': serializer.toJson<String>(name),
      'isRevoked': serializer.toJson<bool>(isRevoked),
      'version': serializer.toJson<int>(version),
      'agentId': serializer.toJson<String?>(agentId),
      'tokenValue': serializer.toJson<String?>(tokenValue),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'allTables': serializer.toJson<bool>(allTables),
      'allViews': serializer.toJson<bool>(allViews),
      'allPermissions': serializer.toJson<bool>(allPermissions),
      'globalPermissionsJson': serializer.toJson<String>(globalPermissionsJson),
      'rulesJson': serializer.toJson<String>(rulesJson),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
      'tokenHash': serializer.toJson<String>(tokenHash),
    };
  }

  ClientTokenCacheData copyWith({
    String? id,
    String? clientId,
    String? name,
    bool? isRevoked,
    int? version,
    Value<String?> agentId = const Value.absent(),
    Value<String?> tokenValue = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> updatedAt = const Value.absent(),
    String? payloadJson,
    bool? allTables,
    bool? allViews,
    bool? allPermissions,
    String? globalPermissionsJson,
    String? rulesJson,
    DateTime? syncedAt,
    String? tokenHash,
  }) => ClientTokenCacheData(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    name: name ?? this.name,
    isRevoked: isRevoked ?? this.isRevoked,
    version: version ?? this.version,
    agentId: agentId.present ? agentId.value : this.agentId,
    tokenValue: tokenValue.present ? tokenValue.value : this.tokenValue,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    payloadJson: payloadJson ?? this.payloadJson,
    allTables: allTables ?? this.allTables,
    allViews: allViews ?? this.allViews,
    allPermissions: allPermissions ?? this.allPermissions,
    globalPermissionsJson: globalPermissionsJson ?? this.globalPermissionsJson,
    rulesJson: rulesJson ?? this.rulesJson,
    syncedAt: syncedAt ?? this.syncedAt,
    tokenHash: tokenHash ?? this.tokenHash,
  );
  ClientTokenCacheData copyWithCompanion(ClientTokenCacheTableCompanion data) {
    return ClientTokenCacheData(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      name: data.name.present ? data.name.value : this.name,
      isRevoked: data.isRevoked.present ? data.isRevoked.value : this.isRevoked,
      version: data.version.present ? data.version.value : this.version,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      tokenValue: data.tokenValue.present
          ? data.tokenValue.value
          : this.tokenValue,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      allTables: data.allTables.present ? data.allTables.value : this.allTables,
      allViews: data.allViews.present ? data.allViews.value : this.allViews,
      allPermissions: data.allPermissions.present
          ? data.allPermissions.value
          : this.allPermissions,
      globalPermissionsJson: data.globalPermissionsJson.present
          ? data.globalPermissionsJson.value
          : this.globalPermissionsJson,
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
          ..write('name: $name, ')
          ..write('isRevoked: $isRevoked, ')
          ..write('version: $version, ')
          ..write('agentId: $agentId, ')
          ..write('tokenValue: $tokenValue, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('allTables: $allTables, ')
          ..write('allViews: $allViews, ')
          ..write('allPermissions: $allPermissions, ')
          ..write('globalPermissionsJson: $globalPermissionsJson, ')
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
    name,
    isRevoked,
    version,
    agentId,
    tokenValue,
    createdAt,
    updatedAt,
    payloadJson,
    allTables,
    allViews,
    allPermissions,
    globalPermissionsJson,
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
          other.name == this.name &&
          other.isRevoked == this.isRevoked &&
          other.version == this.version &&
          other.agentId == this.agentId &&
          other.tokenValue == this.tokenValue &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.payloadJson == this.payloadJson &&
          other.allTables == this.allTables &&
          other.allViews == this.allViews &&
          other.allPermissions == this.allPermissions &&
          other.globalPermissionsJson == this.globalPermissionsJson &&
          other.rulesJson == this.rulesJson &&
          other.syncedAt == this.syncedAt &&
          other.tokenHash == this.tokenHash);
}

class ClientTokenCacheTableCompanion
    extends UpdateCompanion<ClientTokenCacheData> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<String> name;
  final Value<bool> isRevoked;
  final Value<int> version;
  final Value<String?> agentId;
  final Value<String?> tokenValue;
  final Value<DateTime> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<String> payloadJson;
  final Value<bool> allTables;
  final Value<bool> allViews;
  final Value<bool> allPermissions;
  final Value<String> globalPermissionsJson;
  final Value<String> rulesJson;
  final Value<DateTime> syncedAt;
  final Value<String> tokenHash;
  final Value<int> rowid;
  const ClientTokenCacheTableCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.name = const Value.absent(),
    this.isRevoked = const Value.absent(),
    this.version = const Value.absent(),
    this.agentId = const Value.absent(),
    this.tokenValue = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.allTables = const Value.absent(),
    this.allViews = const Value.absent(),
    this.allPermissions = const Value.absent(),
    this.globalPermissionsJson = const Value.absent(),
    this.rulesJson = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientTokenCacheTableCompanion.insert({
    required String id,
    required String clientId,
    this.name = const Value.absent(),
    this.isRevoked = const Value.absent(),
    this.version = const Value.absent(),
    this.agentId = const Value.absent(),
    this.tokenValue = const Value.absent(),
    required DateTime createdAt,
    this.updatedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.allTables = const Value.absent(),
    this.allViews = const Value.absent(),
    this.allPermissions = const Value.absent(),
    this.globalPermissionsJson = const Value.absent(),
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
    Expression<String>? name,
    Expression<bool>? isRevoked,
    Expression<int>? version,
    Expression<String>? agentId,
    Expression<String>? tokenValue,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? payloadJson,
    Expression<bool>? allTables,
    Expression<bool>? allViews,
    Expression<bool>? allPermissions,
    Expression<String>? globalPermissionsJson,
    Expression<String>? rulesJson,
    Expression<DateTime>? syncedAt,
    Expression<String>? tokenHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (name != null) 'name': name,
      if (isRevoked != null) 'is_revoked': isRevoked,
      if (version != null) 'version': version,
      if (agentId != null) 'agent_id': agentId,
      if (tokenValue != null) 'token_value': tokenValue,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (allTables != null) 'all_tables': allTables,
      if (allViews != null) 'all_views': allViews,
      if (allPermissions != null) 'all_permissions': allPermissions,
      if (globalPermissionsJson != null)
        'global_permissions_json': globalPermissionsJson,
      if (rulesJson != null) 'rules_json': rulesJson,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (tokenHash != null) 'token_hash': tokenHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientTokenCacheTableCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<String>? name,
    Value<bool>? isRevoked,
    Value<int>? version,
    Value<String?>? agentId,
    Value<String?>? tokenValue,
    Value<DateTime>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<String>? payloadJson,
    Value<bool>? allTables,
    Value<bool>? allViews,
    Value<bool>? allPermissions,
    Value<String>? globalPermissionsJson,
    Value<String>? rulesJson,
    Value<DateTime>? syncedAt,
    Value<String>? tokenHash,
    Value<int>? rowid,
  }) {
    return ClientTokenCacheTableCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      isRevoked: isRevoked ?? this.isRevoked,
      version: version ?? this.version,
      agentId: agentId ?? this.agentId,
      tokenValue: tokenValue ?? this.tokenValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payloadJson: payloadJson ?? this.payloadJson,
      allTables: allTables ?? this.allTables,
      allViews: allViews ?? this.allViews,
      allPermissions: allPermissions ?? this.allPermissions,
      globalPermissionsJson:
          globalPermissionsJson ?? this.globalPermissionsJson,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isRevoked.present) {
      map['is_revoked'] = Variable<bool>(isRevoked.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (tokenValue.present) {
      map['token_value'] = Variable<String>(tokenValue.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
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
    if (globalPermissionsJson.present) {
      map['global_permissions_json'] = Variable<String>(
        globalPermissionsJson.value,
      );
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
          ..write('name: $name, ')
          ..write('isRevoked: $isRevoked, ')
          ..write('version: $version, ')
          ..write('agentId: $agentId, ')
          ..write('tokenValue: $tokenValue, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('allTables: $allTables, ')
          ..write('allViews: $allViews, ')
          ..write('allPermissions: $allPermissions, ')
          ..write('globalPermissionsJson: $globalPermissionsJson, ')
          ..write('rulesJson: $rulesJson, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentActionDefinitionTableTable extends AgentActionDefinitionTable
    with
        TableInfo<$AgentActionDefinitionTableTable, AgentActionDefinitionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentActionDefinitionTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
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
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _policiesJsonMeta = const VerificationMeta(
    'policiesJson',
  );
  @override
  late final GeneratedColumn<String> policiesJson = GeneratedColumn<String>(
    'policies_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _definitionVersionMeta = const VerificationMeta(
    'definitionVersion',
  );
  @override
  late final GeneratedColumn<int> definitionVersion = GeneratedColumn<int>(
    'definition_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _definitionSnapshotHashMeta =
      const VerificationMeta('definitionSnapshotHash');
  @override
  late final GeneratedColumn<String> definitionSnapshotHash =
      GeneratedColumn<String>(
        'definition_snapshot_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastPreflightSnapshotHashMeta =
      const VerificationMeta('lastPreflightSnapshotHash');
  @override
  late final GeneratedColumn<String> lastPreflightSnapshotHash =
      GeneratedColumn<String>(
        'last_preflight_snapshot_hash',
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
    name,
    description,
    type,
    state,
    configJson,
    policiesJson,
    definitionVersion,
    definitionSnapshotHash,
    lastPreflightSnapshotHash,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_action_definition_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentActionDefinitionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_configJsonMeta);
    }
    if (data.containsKey('policies_json')) {
      context.handle(
        _policiesJsonMeta,
        policiesJson.isAcceptableOrUnknown(
          data['policies_json']!,
          _policiesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_policiesJsonMeta);
    }
    if (data.containsKey('definition_version')) {
      context.handle(
        _definitionVersionMeta,
        definitionVersion.isAcceptableOrUnknown(
          data['definition_version']!,
          _definitionVersionMeta,
        ),
      );
    }
    if (data.containsKey('definition_snapshot_hash')) {
      context.handle(
        _definitionSnapshotHashMeta,
        definitionSnapshotHash.isAcceptableOrUnknown(
          data['definition_snapshot_hash']!,
          _definitionSnapshotHashMeta,
        ),
      );
    }
    if (data.containsKey('last_preflight_snapshot_hash')) {
      context.handle(
        _lastPreflightSnapshotHashMeta,
        lastPreflightSnapshotHash.isAcceptableOrUnknown(
          data['last_preflight_snapshot_hash']!,
          _lastPreflightSnapshotHashMeta,
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
  AgentActionDefinitionData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentActionDefinitionData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      policiesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}policies_json'],
      )!,
      definitionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}definition_version'],
      )!,
      definitionSnapshotHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}definition_snapshot_hash'],
      ),
      lastPreflightSnapshotHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_preflight_snapshot_hash'],
      ),
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
  $AgentActionDefinitionTableTable createAlias(String alias) {
    return $AgentActionDefinitionTableTable(attachedDatabase, alias);
  }
}

class AgentActionDefinitionData extends DataClass
    implements Insertable<AgentActionDefinitionData> {
  final String id;
  final String name;
  final String? description;
  final String type;
  final String state;
  final String configJson;
  final String policiesJson;
  final int definitionVersion;
  final String? definitionSnapshotHash;
  final String? lastPreflightSnapshotHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AgentActionDefinitionData({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.state,
    required this.configJson,
    required this.policiesJson,
    required this.definitionVersion,
    this.definitionSnapshotHash,
    this.lastPreflightSnapshotHash,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['type'] = Variable<String>(type);
    map['state'] = Variable<String>(state);
    map['config_json'] = Variable<String>(configJson);
    map['policies_json'] = Variable<String>(policiesJson);
    map['definition_version'] = Variable<int>(definitionVersion);
    if (!nullToAbsent || definitionSnapshotHash != null) {
      map['definition_snapshot_hash'] = Variable<String>(
        definitionSnapshotHash,
      );
    }
    if (!nullToAbsent || lastPreflightSnapshotHash != null) {
      map['last_preflight_snapshot_hash'] = Variable<String>(
        lastPreflightSnapshotHash,
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AgentActionDefinitionTableCompanion toCompanion(bool nullToAbsent) {
    return AgentActionDefinitionTableCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      type: Value(type),
      state: Value(state),
      configJson: Value(configJson),
      policiesJson: Value(policiesJson),
      definitionVersion: Value(definitionVersion),
      definitionSnapshotHash: definitionSnapshotHash == null && nullToAbsent
          ? const Value.absent()
          : Value(definitionSnapshotHash),
      lastPreflightSnapshotHash:
          lastPreflightSnapshotHash == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPreflightSnapshotHash),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AgentActionDefinitionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentActionDefinitionData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      type: serializer.fromJson<String>(json['type']),
      state: serializer.fromJson<String>(json['state']),
      configJson: serializer.fromJson<String>(json['configJson']),
      policiesJson: serializer.fromJson<String>(json['policiesJson']),
      definitionVersion: serializer.fromJson<int>(json['definitionVersion']),
      definitionSnapshotHash: serializer.fromJson<String?>(
        json['definitionSnapshotHash'],
      ),
      lastPreflightSnapshotHash: serializer.fromJson<String?>(
        json['lastPreflightSnapshotHash'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'type': serializer.toJson<String>(type),
      'state': serializer.toJson<String>(state),
      'configJson': serializer.toJson<String>(configJson),
      'policiesJson': serializer.toJson<String>(policiesJson),
      'definitionVersion': serializer.toJson<int>(definitionVersion),
      'definitionSnapshotHash': serializer.toJson<String?>(
        definitionSnapshotHash,
      ),
      'lastPreflightSnapshotHash': serializer.toJson<String?>(
        lastPreflightSnapshotHash,
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AgentActionDefinitionData copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    String? type,
    String? state,
    String? configJson,
    String? policiesJson,
    int? definitionVersion,
    Value<String?> definitionSnapshotHash = const Value.absent(),
    Value<String?> lastPreflightSnapshotHash = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AgentActionDefinitionData(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    type: type ?? this.type,
    state: state ?? this.state,
    configJson: configJson ?? this.configJson,
    policiesJson: policiesJson ?? this.policiesJson,
    definitionVersion: definitionVersion ?? this.definitionVersion,
    definitionSnapshotHash: definitionSnapshotHash.present
        ? definitionSnapshotHash.value
        : this.definitionSnapshotHash,
    lastPreflightSnapshotHash: lastPreflightSnapshotHash.present
        ? lastPreflightSnapshotHash.value
        : this.lastPreflightSnapshotHash,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AgentActionDefinitionData copyWithCompanion(
    AgentActionDefinitionTableCompanion data,
  ) {
    return AgentActionDefinitionData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      type: data.type.present ? data.type.value : this.type,
      state: data.state.present ? data.state.value : this.state,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      policiesJson: data.policiesJson.present
          ? data.policiesJson.value
          : this.policiesJson,
      definitionVersion: data.definitionVersion.present
          ? data.definitionVersion.value
          : this.definitionVersion,
      definitionSnapshotHash: data.definitionSnapshotHash.present
          ? data.definitionSnapshotHash.value
          : this.definitionSnapshotHash,
      lastPreflightSnapshotHash: data.lastPreflightSnapshotHash.present
          ? data.lastPreflightSnapshotHash.value
          : this.lastPreflightSnapshotHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionDefinitionData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('type: $type, ')
          ..write('state: $state, ')
          ..write('configJson: $configJson, ')
          ..write('policiesJson: $policiesJson, ')
          ..write('definitionVersion: $definitionVersion, ')
          ..write('definitionSnapshotHash: $definitionSnapshotHash, ')
          ..write('lastPreflightSnapshotHash: $lastPreflightSnapshotHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    type,
    state,
    configJson,
    policiesJson,
    definitionVersion,
    definitionSnapshotHash,
    lastPreflightSnapshotHash,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentActionDefinitionData &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.type == this.type &&
          other.state == this.state &&
          other.configJson == this.configJson &&
          other.policiesJson == this.policiesJson &&
          other.definitionVersion == this.definitionVersion &&
          other.definitionSnapshotHash == this.definitionSnapshotHash &&
          other.lastPreflightSnapshotHash == this.lastPreflightSnapshotHash &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AgentActionDefinitionTableCompanion
    extends UpdateCompanion<AgentActionDefinitionData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> type;
  final Value<String> state;
  final Value<String> configJson;
  final Value<String> policiesJson;
  final Value<int> definitionVersion;
  final Value<String?> definitionSnapshotHash;
  final Value<String?> lastPreflightSnapshotHash;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AgentActionDefinitionTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.type = const Value.absent(),
    this.state = const Value.absent(),
    this.configJson = const Value.absent(),
    this.policiesJson = const Value.absent(),
    this.definitionVersion = const Value.absent(),
    this.definitionSnapshotHash = const Value.absent(),
    this.lastPreflightSnapshotHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentActionDefinitionTableCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    required String type,
    required String state,
    required String configJson,
    required String policiesJson,
    this.definitionVersion = const Value.absent(),
    this.definitionSnapshotHash = const Value.absent(),
    this.lastPreflightSnapshotHash = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       type = Value(type),
       state = Value(state),
       configJson = Value(configJson),
       policiesJson = Value(policiesJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AgentActionDefinitionData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? type,
    Expression<String>? state,
    Expression<String>? configJson,
    Expression<String>? policiesJson,
    Expression<int>? definitionVersion,
    Expression<String>? definitionSnapshotHash,
    Expression<String>? lastPreflightSnapshotHash,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (type != null) 'type': type,
      if (state != null) 'state': state,
      if (configJson != null) 'config_json': configJson,
      if (policiesJson != null) 'policies_json': policiesJson,
      if (definitionVersion != null) 'definition_version': definitionVersion,
      if (definitionSnapshotHash != null)
        'definition_snapshot_hash': definitionSnapshotHash,
      if (lastPreflightSnapshotHash != null)
        'last_preflight_snapshot_hash': lastPreflightSnapshotHash,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentActionDefinitionTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? type,
    Value<String>? state,
    Value<String>? configJson,
    Value<String>? policiesJson,
    Value<int>? definitionVersion,
    Value<String?>? definitionSnapshotHash,
    Value<String?>? lastPreflightSnapshotHash,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AgentActionDefinitionTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      state: state ?? this.state,
      configJson: configJson ?? this.configJson,
      policiesJson: policiesJson ?? this.policiesJson,
      definitionVersion: definitionVersion ?? this.definitionVersion,
      definitionSnapshotHash:
          definitionSnapshotHash ?? this.definitionSnapshotHash,
      lastPreflightSnapshotHash:
          lastPreflightSnapshotHash ?? this.lastPreflightSnapshotHash,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (policiesJson.present) {
      map['policies_json'] = Variable<String>(policiesJson.value);
    }
    if (definitionVersion.present) {
      map['definition_version'] = Variable<int>(definitionVersion.value);
    }
    if (definitionSnapshotHash.present) {
      map['definition_snapshot_hash'] = Variable<String>(
        definitionSnapshotHash.value,
      );
    }
    if (lastPreflightSnapshotHash.present) {
      map['last_preflight_snapshot_hash'] = Variable<String>(
        lastPreflightSnapshotHash.value,
      );
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
    return (StringBuffer('AgentActionDefinitionTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('type: $type, ')
          ..write('state: $state, ')
          ..write('configJson: $configJson, ')
          ..write('policiesJson: $policiesJson, ')
          ..write('definitionVersion: $definitionVersion, ')
          ..write('definitionSnapshotHash: $definitionSnapshotHash, ')
          ..write('lastPreflightSnapshotHash: $lastPreflightSnapshotHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentActionTriggerTableTable extends AgentActionTriggerTable
    with TableInfo<$AgentActionTriggerTableTable, AgentActionTriggerData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentActionTriggerTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'is_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _scheduleJsonMeta = const VerificationMeta(
    'scheduleJson',
  );
  @override
  late final GeneratedColumn<String> scheduleJson = GeneratedColumn<String>(
    'schedule_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastScheduledAtMeta = const VerificationMeta(
    'lastScheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastScheduledAt =
      GeneratedColumn<DateTime>(
        'last_scheduled_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastRunAtMeta = const VerificationMeta(
    'lastRunAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastRunAt = GeneratedColumn<DateTime>(
    'last_run_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextRunAtMeta = const VerificationMeta(
    'nextRunAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRunAt = GeneratedColumn<DateTime>(
    'next_run_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
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
    actionId,
    type,
    name,
    isEnabled,
    scheduleJson,
    lastScheduledAt,
    lastRunAt,
    nextRunAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_action_trigger_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentActionTriggerData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('is_enabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta),
      );
    }
    if (data.containsKey('schedule_json')) {
      context.handle(
        _scheduleJsonMeta,
        scheduleJson.isAcceptableOrUnknown(
          data['schedule_json']!,
          _scheduleJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduleJsonMeta);
    }
    if (data.containsKey('last_scheduled_at')) {
      context.handle(
        _lastScheduledAtMeta,
        lastScheduledAt.isAcceptableOrUnknown(
          data['last_scheduled_at']!,
          _lastScheduledAtMeta,
        ),
      );
    }
    if (data.containsKey('last_run_at')) {
      context.handle(
        _lastRunAtMeta,
        lastRunAt.isAcceptableOrUnknown(data['last_run_at']!, _lastRunAtMeta),
      );
    }
    if (data.containsKey('next_run_at')) {
      context.handle(
        _nextRunAtMeta,
        nextRunAt.isAcceptableOrUnknown(data['next_run_at']!, _nextRunAtMeta),
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
  AgentActionTriggerData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentActionTriggerData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      isEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_enabled'],
      )!,
      scheduleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_json'],
      )!,
      lastScheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_scheduled_at'],
      ),
      lastRunAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_run_at'],
      ),
      nextRunAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_run_at'],
      ),
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
  $AgentActionTriggerTableTable createAlias(String alias) {
    return $AgentActionTriggerTableTable(attachedDatabase, alias);
  }
}

class AgentActionTriggerData extends DataClass
    implements Insertable<AgentActionTriggerData> {
  final String id;
  final String actionId;
  final String type;
  final String? name;
  final bool isEnabled;
  final String scheduleJson;
  final DateTime? lastScheduledAt;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AgentActionTriggerData({
    required this.id,
    required this.actionId,
    required this.type,
    this.name,
    required this.isEnabled,
    required this.scheduleJson,
    this.lastScheduledAt,
    this.lastRunAt,
    this.nextRunAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['action_id'] = Variable<String>(actionId);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['schedule_json'] = Variable<String>(scheduleJson);
    if (!nullToAbsent || lastScheduledAt != null) {
      map['last_scheduled_at'] = Variable<DateTime>(lastScheduledAt);
    }
    if (!nullToAbsent || lastRunAt != null) {
      map['last_run_at'] = Variable<DateTime>(lastRunAt);
    }
    if (!nullToAbsent || nextRunAt != null) {
      map['next_run_at'] = Variable<DateTime>(nextRunAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AgentActionTriggerTableCompanion toCompanion(bool nullToAbsent) {
    return AgentActionTriggerTableCompanion(
      id: Value(id),
      actionId: Value(actionId),
      type: Value(type),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      isEnabled: Value(isEnabled),
      scheduleJson: Value(scheduleJson),
      lastScheduledAt: lastScheduledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastScheduledAt),
      lastRunAt: lastRunAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRunAt),
      nextRunAt: nextRunAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRunAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AgentActionTriggerData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentActionTriggerData(
      id: serializer.fromJson<String>(json['id']),
      actionId: serializer.fromJson<String>(json['actionId']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String?>(json['name']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      scheduleJson: serializer.fromJson<String>(json['scheduleJson']),
      lastScheduledAt: serializer.fromJson<DateTime?>(json['lastScheduledAt']),
      lastRunAt: serializer.fromJson<DateTime?>(json['lastRunAt']),
      nextRunAt: serializer.fromJson<DateTime?>(json['nextRunAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actionId': serializer.toJson<String>(actionId),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String?>(name),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'scheduleJson': serializer.toJson<String>(scheduleJson),
      'lastScheduledAt': serializer.toJson<DateTime?>(lastScheduledAt),
      'lastRunAt': serializer.toJson<DateTime?>(lastRunAt),
      'nextRunAt': serializer.toJson<DateTime?>(nextRunAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AgentActionTriggerData copyWith({
    String? id,
    String? actionId,
    String? type,
    Value<String?> name = const Value.absent(),
    bool? isEnabled,
    String? scheduleJson,
    Value<DateTime?> lastScheduledAt = const Value.absent(),
    Value<DateTime?> lastRunAt = const Value.absent(),
    Value<DateTime?> nextRunAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AgentActionTriggerData(
    id: id ?? this.id,
    actionId: actionId ?? this.actionId,
    type: type ?? this.type,
    name: name.present ? name.value : this.name,
    isEnabled: isEnabled ?? this.isEnabled,
    scheduleJson: scheduleJson ?? this.scheduleJson,
    lastScheduledAt: lastScheduledAt.present
        ? lastScheduledAt.value
        : this.lastScheduledAt,
    lastRunAt: lastRunAt.present ? lastRunAt.value : this.lastRunAt,
    nextRunAt: nextRunAt.present ? nextRunAt.value : this.nextRunAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AgentActionTriggerData copyWithCompanion(
    AgentActionTriggerTableCompanion data,
  ) {
    return AgentActionTriggerData(
      id: data.id.present ? data.id.value : this.id,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      scheduleJson: data.scheduleJson.present
          ? data.scheduleJson.value
          : this.scheduleJson,
      lastScheduledAt: data.lastScheduledAt.present
          ? data.lastScheduledAt.value
          : this.lastScheduledAt,
      lastRunAt: data.lastRunAt.present ? data.lastRunAt.value : this.lastRunAt,
      nextRunAt: data.nextRunAt.present ? data.nextRunAt.value : this.nextRunAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionTriggerData(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('scheduleJson: $scheduleJson, ')
          ..write('lastScheduledAt: $lastScheduledAt, ')
          ..write('lastRunAt: $lastRunAt, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    actionId,
    type,
    name,
    isEnabled,
    scheduleJson,
    lastScheduledAt,
    lastRunAt,
    nextRunAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentActionTriggerData &&
          other.id == this.id &&
          other.actionId == this.actionId &&
          other.type == this.type &&
          other.name == this.name &&
          other.isEnabled == this.isEnabled &&
          other.scheduleJson == this.scheduleJson &&
          other.lastScheduledAt == this.lastScheduledAt &&
          other.lastRunAt == this.lastRunAt &&
          other.nextRunAt == this.nextRunAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AgentActionTriggerTableCompanion
    extends UpdateCompanion<AgentActionTriggerData> {
  final Value<String> id;
  final Value<String> actionId;
  final Value<String> type;
  final Value<String?> name;
  final Value<bool> isEnabled;
  final Value<String> scheduleJson;
  final Value<DateTime?> lastScheduledAt;
  final Value<DateTime?> lastRunAt;
  final Value<DateTime?> nextRunAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AgentActionTriggerTableCompanion({
    this.id = const Value.absent(),
    this.actionId = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.scheduleJson = const Value.absent(),
    this.lastScheduledAt = const Value.absent(),
    this.lastRunAt = const Value.absent(),
    this.nextRunAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentActionTriggerTableCompanion.insert({
    required String id,
    required String actionId,
    required String type,
    this.name = const Value.absent(),
    this.isEnabled = const Value.absent(),
    required String scheduleJson,
    this.lastScheduledAt = const Value.absent(),
    this.lastRunAt = const Value.absent(),
    this.nextRunAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       actionId = Value(actionId),
       type = Value(type),
       scheduleJson = Value(scheduleJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AgentActionTriggerData> custom({
    Expression<String>? id,
    Expression<String>? actionId,
    Expression<String>? type,
    Expression<String>? name,
    Expression<bool>? isEnabled,
    Expression<String>? scheduleJson,
    Expression<DateTime>? lastScheduledAt,
    Expression<DateTime>? lastRunAt,
    Expression<DateTime>? nextRunAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actionId != null) 'action_id': actionId,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (scheduleJson != null) 'schedule_json': scheduleJson,
      if (lastScheduledAt != null) 'last_scheduled_at': lastScheduledAt,
      if (lastRunAt != null) 'last_run_at': lastRunAt,
      if (nextRunAt != null) 'next_run_at': nextRunAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentActionTriggerTableCompanion copyWith({
    Value<String>? id,
    Value<String>? actionId,
    Value<String>? type,
    Value<String?>? name,
    Value<bool>? isEnabled,
    Value<String>? scheduleJson,
    Value<DateTime?>? lastScheduledAt,
    Value<DateTime?>? lastRunAt,
    Value<DateTime?>? nextRunAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AgentActionTriggerTableCompanion(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      type: type ?? this.type,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      scheduleJson: scheduleJson ?? this.scheduleJson,
      lastScheduledAt: lastScheduledAt ?? this.lastScheduledAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
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
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (scheduleJson.present) {
      map['schedule_json'] = Variable<String>(scheduleJson.value);
    }
    if (lastScheduledAt.present) {
      map['last_scheduled_at'] = Variable<DateTime>(lastScheduledAt.value);
    }
    if (lastRunAt.present) {
      map['last_run_at'] = Variable<DateTime>(lastRunAt.value);
    }
    if (nextRunAt.present) {
      map['next_run_at'] = Variable<DateTime>(nextRunAt.value);
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
    return (StringBuffer('AgentActionTriggerTableCompanion(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('scheduleJson: $scheduleJson, ')
          ..write('lastScheduledAt: $lastScheduledAt, ')
          ..write('lastRunAt: $lastRunAt, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentActionExecutionTableTable extends AgentActionExecutionTable
    with TableInfo<$AgentActionExecutionTableTable, AgentActionExecutionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentActionExecutionTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _actionTypeMeta = const VerificationMeta(
    'actionType',
  );
  @override
  late final GeneratedColumn<String> actionType = GeneratedColumn<String>(
    'action_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestedAtMeta = const VerificationMeta(
    'requestedAt',
  );
  @override
  late final GeneratedColumn<DateTime> requestedAt = GeneratedColumn<DateTime>(
    'requested_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestedByMeta = const VerificationMeta(
    'requestedBy',
  );
  @override
  late final GeneratedColumn<String> requestedBy = GeneratedColumn<String>(
    'requested_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _traceIdMeta = const VerificationMeta(
    'traceId',
  );
  @override
  late final GeneratedColumn<String> traceId = GeneratedColumn<String>(
    'trace_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _runtimeInstanceIdMeta = const VerificationMeta(
    'runtimeInstanceId',
  );
  @override
  late final GeneratedColumn<String> runtimeInstanceId =
      GeneratedColumn<String>(
        'runtime_instance_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _runtimeSessionIdMeta = const VerificationMeta(
    'runtimeSessionId',
  );
  @override
  late final GeneratedColumn<String> runtimeSessionId = GeneratedColumn<String>(
    'runtime_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _triggerIdMeta = const VerificationMeta(
    'triggerId',
  );
  @override
  late final GeneratedColumn<String> triggerId = GeneratedColumn<String>(
    'trigger_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _triggerTypeMeta = const VerificationMeta(
    'triggerType',
  );
  @override
  late final GeneratedColumn<String> triggerType = GeneratedColumn<String>(
    'trigger_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _triggeredAtMeta = const VerificationMeta(
    'triggeredAt',
  );
  @override
  late final GeneratedColumn<DateTime> triggeredAt = GeneratedColumn<DateTime>(
    'triggered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _queueStartedAtMeta = const VerificationMeta(
    'queueStartedAt',
  );
  @override
  late final GeneratedColumn<DateTime> queueStartedAt =
      GeneratedColumn<DateTime>(
        'queue_started_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _processStartedAtMeta = const VerificationMeta(
    'processStartedAt',
  );
  @override
  late final GeneratedColumn<DateTime> processStartedAt =
      GeneratedColumn<DateTime>(
        'process_started_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeoutAtMeta = const VerificationMeta(
    'timeoutAt',
  );
  @override
  late final GeneratedColumn<DateTime> timeoutAt = GeneratedColumn<DateTime>(
    'timeout_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<int> pid = GeneratedColumn<int>(
    'pid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
  static const VerificationMeta _processExecutableMeta = const VerificationMeta(
    'processExecutable',
  );
  @override
  late final GeneratedColumn<String> processExecutable =
      GeneratedColumn<String>(
        'process_executable',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _processArgumentCountMeta =
      const VerificationMeta('processArgumentCount');
  @override
  late final GeneratedColumn<int> processArgumentCount = GeneratedColumn<int>(
    'process_argument_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processCommandPreviewMeta =
      const VerificationMeta('processCommandPreview');
  @override
  late final GeneratedColumn<String> processCommandPreview =
      GeneratedColumn<String>(
        'process_command_preview',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _stdoutTextMeta = const VerificationMeta(
    'stdoutText',
  );
  @override
  late final GeneratedColumn<String> stdoutText = GeneratedColumn<String>(
    'stdout_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stderrTextMeta = const VerificationMeta(
    'stderrText',
  );
  @override
  late final GeneratedColumn<String> stderrText = GeneratedColumn<String>(
    'stderr_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stdoutTruncatedMeta = const VerificationMeta(
    'stdoutTruncated',
  );
  @override
  late final GeneratedColumn<bool> stdoutTruncated = GeneratedColumn<bool>(
    'stdout_truncated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stdout_truncated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _stderrTruncatedMeta = const VerificationMeta(
    'stderrTruncated',
  );
  @override
  late final GeneratedColumn<bool> stderrTruncated = GeneratedColumn<bool>(
    'stderr_truncated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stderr_truncated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _stdoutStoredInChunksMeta =
      const VerificationMeta('stdoutStoredInChunks');
  @override
  late final GeneratedColumn<bool> stdoutStoredInChunks = GeneratedColumn<bool>(
    'stdout_stored_in_chunks',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stdout_stored_in_chunks" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _stderrStoredInChunksMeta =
      const VerificationMeta('stderrStoredInChunks');
  @override
  late final GeneratedColumn<bool> stderrStoredInChunks = GeneratedColumn<bool>(
    'stderr_stored_in_chunks',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stderr_stored_in_chunks" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _definitionSnapshotHashMeta =
      const VerificationMeta('definitionSnapshotHash');
  @override
  late final GeneratedColumn<String> definitionSnapshotHash =
      GeneratedColumn<String>(
        'definition_snapshot_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _contextHashMeta = const VerificationMeta(
    'contextHash',
  );
  @override
  late final GeneratedColumn<String> contextHash = GeneratedColumn<String>(
    'context_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _redactionAppliedMeta = const VerificationMeta(
    'redactionApplied',
  );
  @override
  late final GeneratedColumn<bool> redactionApplied = GeneratedColumn<bool>(
    'redaction_applied',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("redaction_applied" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  static const VerificationMeta _failurePhaseMeta = const VerificationMeta(
    'failurePhase',
  );
  @override
  late final GeneratedColumn<String> failurePhase = GeneratedColumn<String>(
    'failure_phase',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureMessageMeta = const VerificationMeta(
    'failureMessage',
  );
  @override
  late final GeneratedColumn<String> failureMessage = GeneratedColumn<String>(
    'failure_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    actionId,
    actionType,
    status,
    requestedAt,
    source,
    idempotencyKey,
    requestedBy,
    traceId,
    runtimeInstanceId,
    runtimeSessionId,
    triggerId,
    triggerType,
    scheduledAt,
    triggeredAt,
    queueStartedAt,
    processStartedAt,
    finishedAt,
    timeoutAt,
    pid,
    exitCode,
    processExecutable,
    processArgumentCount,
    processCommandPreview,
    stdoutText,
    stderrText,
    stdoutTruncated,
    stderrTruncated,
    stdoutStoredInChunks,
    stderrStoredInChunks,
    definitionSnapshotHash,
    contextHash,
    redactionApplied,
    failureCode,
    failurePhase,
    failureMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_action_execution_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentActionExecutionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('action_type')) {
      context.handle(
        _actionTypeMeta,
        actionType.isAcceptableOrUnknown(data['action_type']!, _actionTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_actionTypeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('requested_at')) {
      context.handle(
        _requestedAtMeta,
        requestedAt.isAcceptableOrUnknown(
          data['requested_at']!,
          _requestedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestedAtMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    }
    if (data.containsKey('requested_by')) {
      context.handle(
        _requestedByMeta,
        requestedBy.isAcceptableOrUnknown(
          data['requested_by']!,
          _requestedByMeta,
        ),
      );
    }
    if (data.containsKey('trace_id')) {
      context.handle(
        _traceIdMeta,
        traceId.isAcceptableOrUnknown(data['trace_id']!, _traceIdMeta),
      );
    }
    if (data.containsKey('runtime_instance_id')) {
      context.handle(
        _runtimeInstanceIdMeta,
        runtimeInstanceId.isAcceptableOrUnknown(
          data['runtime_instance_id']!,
          _runtimeInstanceIdMeta,
        ),
      );
    }
    if (data.containsKey('runtime_session_id')) {
      context.handle(
        _runtimeSessionIdMeta,
        runtimeSessionId.isAcceptableOrUnknown(
          data['runtime_session_id']!,
          _runtimeSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('trigger_id')) {
      context.handle(
        _triggerIdMeta,
        triggerId.isAcceptableOrUnknown(data['trigger_id']!, _triggerIdMeta),
      );
    }
    if (data.containsKey('trigger_type')) {
      context.handle(
        _triggerTypeMeta,
        triggerType.isAcceptableOrUnknown(
          data['trigger_type']!,
          _triggerTypeMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    }
    if (data.containsKey('triggered_at')) {
      context.handle(
        _triggeredAtMeta,
        triggeredAt.isAcceptableOrUnknown(
          data['triggered_at']!,
          _triggeredAtMeta,
        ),
      );
    }
    if (data.containsKey('queue_started_at')) {
      context.handle(
        _queueStartedAtMeta,
        queueStartedAt.isAcceptableOrUnknown(
          data['queue_started_at']!,
          _queueStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('process_started_at')) {
      context.handle(
        _processStartedAtMeta,
        processStartedAt.isAcceptableOrUnknown(
          data['process_started_at']!,
          _processStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('timeout_at')) {
      context.handle(
        _timeoutAtMeta,
        timeoutAt.isAcceptableOrUnknown(data['timeout_at']!, _timeoutAtMeta),
      );
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    }
    if (data.containsKey('exit_code')) {
      context.handle(
        _exitCodeMeta,
        exitCode.isAcceptableOrUnknown(data['exit_code']!, _exitCodeMeta),
      );
    }
    if (data.containsKey('process_executable')) {
      context.handle(
        _processExecutableMeta,
        processExecutable.isAcceptableOrUnknown(
          data['process_executable']!,
          _processExecutableMeta,
        ),
      );
    }
    if (data.containsKey('process_argument_count')) {
      context.handle(
        _processArgumentCountMeta,
        processArgumentCount.isAcceptableOrUnknown(
          data['process_argument_count']!,
          _processArgumentCountMeta,
        ),
      );
    }
    if (data.containsKey('process_command_preview')) {
      context.handle(
        _processCommandPreviewMeta,
        processCommandPreview.isAcceptableOrUnknown(
          data['process_command_preview']!,
          _processCommandPreviewMeta,
        ),
      );
    }
    if (data.containsKey('stdout_text')) {
      context.handle(
        _stdoutTextMeta,
        stdoutText.isAcceptableOrUnknown(data['stdout_text']!, _stdoutTextMeta),
      );
    }
    if (data.containsKey('stderr_text')) {
      context.handle(
        _stderrTextMeta,
        stderrText.isAcceptableOrUnknown(data['stderr_text']!, _stderrTextMeta),
      );
    }
    if (data.containsKey('stdout_truncated')) {
      context.handle(
        _stdoutTruncatedMeta,
        stdoutTruncated.isAcceptableOrUnknown(
          data['stdout_truncated']!,
          _stdoutTruncatedMeta,
        ),
      );
    }
    if (data.containsKey('stderr_truncated')) {
      context.handle(
        _stderrTruncatedMeta,
        stderrTruncated.isAcceptableOrUnknown(
          data['stderr_truncated']!,
          _stderrTruncatedMeta,
        ),
      );
    }
    if (data.containsKey('stdout_stored_in_chunks')) {
      context.handle(
        _stdoutStoredInChunksMeta,
        stdoutStoredInChunks.isAcceptableOrUnknown(
          data['stdout_stored_in_chunks']!,
          _stdoutStoredInChunksMeta,
        ),
      );
    }
    if (data.containsKey('stderr_stored_in_chunks')) {
      context.handle(
        _stderrStoredInChunksMeta,
        stderrStoredInChunks.isAcceptableOrUnknown(
          data['stderr_stored_in_chunks']!,
          _stderrStoredInChunksMeta,
        ),
      );
    }
    if (data.containsKey('definition_snapshot_hash')) {
      context.handle(
        _definitionSnapshotHashMeta,
        definitionSnapshotHash.isAcceptableOrUnknown(
          data['definition_snapshot_hash']!,
          _definitionSnapshotHashMeta,
        ),
      );
    }
    if (data.containsKey('context_hash')) {
      context.handle(
        _contextHashMeta,
        contextHash.isAcceptableOrUnknown(
          data['context_hash']!,
          _contextHashMeta,
        ),
      );
    }
    if (data.containsKey('redaction_applied')) {
      context.handle(
        _redactionAppliedMeta,
        redactionApplied.isAcceptableOrUnknown(
          data['redaction_applied']!,
          _redactionAppliedMeta,
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
    if (data.containsKey('failure_phase')) {
      context.handle(
        _failurePhaseMeta,
        failurePhase.isAcceptableOrUnknown(
          data['failure_phase']!,
          _failurePhaseMeta,
        ),
      );
    }
    if (data.containsKey('failure_message')) {
      context.handle(
        _failureMessageMeta,
        failureMessage.isAcceptableOrUnknown(
          data['failure_message']!,
          _failureMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AgentActionExecutionData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentActionExecutionData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      actionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      requestedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}requested_at'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      ),
      requestedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requested_by'],
      ),
      traceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trace_id'],
      ),
      runtimeInstanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runtime_instance_id'],
      ),
      runtimeSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runtime_session_id'],
      ),
      triggerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_id'],
      ),
      triggerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_type'],
      ),
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      ),
      triggeredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}triggered_at'],
      ),
      queueStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}queue_started_at'],
      ),
      processStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}process_started_at'],
      ),
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
      timeoutAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timeout_at'],
      ),
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pid'],
      ),
      exitCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exit_code'],
      ),
      processExecutable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}process_executable'],
      ),
      processArgumentCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}process_argument_count'],
      ),
      processCommandPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}process_command_preview'],
      ),
      stdoutText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stdout_text'],
      ),
      stderrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stderr_text'],
      ),
      stdoutTruncated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stdout_truncated'],
      )!,
      stderrTruncated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stderr_truncated'],
      )!,
      stdoutStoredInChunks: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stdout_stored_in_chunks'],
      )!,
      stderrStoredInChunks: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stderr_stored_in_chunks'],
      )!,
      definitionSnapshotHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}definition_snapshot_hash'],
      ),
      contextHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_hash'],
      ),
      redactionApplied: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}redaction_applied'],
      )!,
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      failurePhase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_phase'],
      ),
      failureMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_message'],
      ),
    );
  }

  @override
  $AgentActionExecutionTableTable createAlias(String alias) {
    return $AgentActionExecutionTableTable(attachedDatabase, alias);
  }
}

class AgentActionExecutionData extends DataClass
    implements Insertable<AgentActionExecutionData> {
  final String id;
  final String actionId;
  final String actionType;
  final String status;
  final DateTime requestedAt;
  final String source;
  final String? idempotencyKey;
  final String? requestedBy;
  final String? traceId;
  final String? runtimeInstanceId;
  final String? runtimeSessionId;
  final String? triggerId;
  final String? triggerType;
  final DateTime? scheduledAt;
  final DateTime? triggeredAt;
  final DateTime? queueStartedAt;
  final DateTime? processStartedAt;
  final DateTime? finishedAt;
  final DateTime? timeoutAt;
  final int? pid;
  final int? exitCode;
  final String? processExecutable;
  final int? processArgumentCount;
  final String? processCommandPreview;
  final String? stdoutText;
  final String? stderrText;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final bool stdoutStoredInChunks;
  final bool stderrStoredInChunks;
  final String? definitionSnapshotHash;
  final String? contextHash;
  final bool redactionApplied;
  final String? failureCode;
  final String? failurePhase;
  final String? failureMessage;
  const AgentActionExecutionData({
    required this.id,
    required this.actionId,
    required this.actionType,
    required this.status,
    required this.requestedAt,
    required this.source,
    this.idempotencyKey,
    this.requestedBy,
    this.traceId,
    this.runtimeInstanceId,
    this.runtimeSessionId,
    this.triggerId,
    this.triggerType,
    this.scheduledAt,
    this.triggeredAt,
    this.queueStartedAt,
    this.processStartedAt,
    this.finishedAt,
    this.timeoutAt,
    this.pid,
    this.exitCode,
    this.processExecutable,
    this.processArgumentCount,
    this.processCommandPreview,
    this.stdoutText,
    this.stderrText,
    required this.stdoutTruncated,
    required this.stderrTruncated,
    required this.stdoutStoredInChunks,
    required this.stderrStoredInChunks,
    this.definitionSnapshotHash,
    this.contextHash,
    required this.redactionApplied,
    this.failureCode,
    this.failurePhase,
    this.failureMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['action_id'] = Variable<String>(actionId);
    map['action_type'] = Variable<String>(actionType);
    map['status'] = Variable<String>(status);
    map['requested_at'] = Variable<DateTime>(requestedAt);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || idempotencyKey != null) {
      map['idempotency_key'] = Variable<String>(idempotencyKey);
    }
    if (!nullToAbsent || requestedBy != null) {
      map['requested_by'] = Variable<String>(requestedBy);
    }
    if (!nullToAbsent || traceId != null) {
      map['trace_id'] = Variable<String>(traceId);
    }
    if (!nullToAbsent || runtimeInstanceId != null) {
      map['runtime_instance_id'] = Variable<String>(runtimeInstanceId);
    }
    if (!nullToAbsent || runtimeSessionId != null) {
      map['runtime_session_id'] = Variable<String>(runtimeSessionId);
    }
    if (!nullToAbsent || triggerId != null) {
      map['trigger_id'] = Variable<String>(triggerId);
    }
    if (!nullToAbsent || triggerType != null) {
      map['trigger_type'] = Variable<String>(triggerType);
    }
    if (!nullToAbsent || scheduledAt != null) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    }
    if (!nullToAbsent || triggeredAt != null) {
      map['triggered_at'] = Variable<DateTime>(triggeredAt);
    }
    if (!nullToAbsent || queueStartedAt != null) {
      map['queue_started_at'] = Variable<DateTime>(queueStartedAt);
    }
    if (!nullToAbsent || processStartedAt != null) {
      map['process_started_at'] = Variable<DateTime>(processStartedAt);
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    if (!nullToAbsent || timeoutAt != null) {
      map['timeout_at'] = Variable<DateTime>(timeoutAt);
    }
    if (!nullToAbsent || pid != null) {
      map['pid'] = Variable<int>(pid);
    }
    if (!nullToAbsent || exitCode != null) {
      map['exit_code'] = Variable<int>(exitCode);
    }
    if (!nullToAbsent || processExecutable != null) {
      map['process_executable'] = Variable<String>(processExecutable);
    }
    if (!nullToAbsent || processArgumentCount != null) {
      map['process_argument_count'] = Variable<int>(processArgumentCount);
    }
    if (!nullToAbsent || processCommandPreview != null) {
      map['process_command_preview'] = Variable<String>(processCommandPreview);
    }
    if (!nullToAbsent || stdoutText != null) {
      map['stdout_text'] = Variable<String>(stdoutText);
    }
    if (!nullToAbsent || stderrText != null) {
      map['stderr_text'] = Variable<String>(stderrText);
    }
    map['stdout_truncated'] = Variable<bool>(stdoutTruncated);
    map['stderr_truncated'] = Variable<bool>(stderrTruncated);
    map['stdout_stored_in_chunks'] = Variable<bool>(stdoutStoredInChunks);
    map['stderr_stored_in_chunks'] = Variable<bool>(stderrStoredInChunks);
    if (!nullToAbsent || definitionSnapshotHash != null) {
      map['definition_snapshot_hash'] = Variable<String>(
        definitionSnapshotHash,
      );
    }
    if (!nullToAbsent || contextHash != null) {
      map['context_hash'] = Variable<String>(contextHash);
    }
    map['redaction_applied'] = Variable<bool>(redactionApplied);
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    if (!nullToAbsent || failurePhase != null) {
      map['failure_phase'] = Variable<String>(failurePhase);
    }
    if (!nullToAbsent || failureMessage != null) {
      map['failure_message'] = Variable<String>(failureMessage);
    }
    return map;
  }

  AgentActionExecutionTableCompanion toCompanion(bool nullToAbsent) {
    return AgentActionExecutionTableCompanion(
      id: Value(id),
      actionId: Value(actionId),
      actionType: Value(actionType),
      status: Value(status),
      requestedAt: Value(requestedAt),
      source: Value(source),
      idempotencyKey: idempotencyKey == null && nullToAbsent
          ? const Value.absent()
          : Value(idempotencyKey),
      requestedBy: requestedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(requestedBy),
      traceId: traceId == null && nullToAbsent
          ? const Value.absent()
          : Value(traceId),
      runtimeInstanceId: runtimeInstanceId == null && nullToAbsent
          ? const Value.absent()
          : Value(runtimeInstanceId),
      runtimeSessionId: runtimeSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(runtimeSessionId),
      triggerId: triggerId == null && nullToAbsent
          ? const Value.absent()
          : Value(triggerId),
      triggerType: triggerType == null && nullToAbsent
          ? const Value.absent()
          : Value(triggerType),
      scheduledAt: scheduledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledAt),
      triggeredAt: triggeredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(triggeredAt),
      queueStartedAt: queueStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(queueStartedAt),
      processStartedAt: processStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(processStartedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      timeoutAt: timeoutAt == null && nullToAbsent
          ? const Value.absent()
          : Value(timeoutAt),
      pid: pid == null && nullToAbsent ? const Value.absent() : Value(pid),
      exitCode: exitCode == null && nullToAbsent
          ? const Value.absent()
          : Value(exitCode),
      processExecutable: processExecutable == null && nullToAbsent
          ? const Value.absent()
          : Value(processExecutable),
      processArgumentCount: processArgumentCount == null && nullToAbsent
          ? const Value.absent()
          : Value(processArgumentCount),
      processCommandPreview: processCommandPreview == null && nullToAbsent
          ? const Value.absent()
          : Value(processCommandPreview),
      stdoutText: stdoutText == null && nullToAbsent
          ? const Value.absent()
          : Value(stdoutText),
      stderrText: stderrText == null && nullToAbsent
          ? const Value.absent()
          : Value(stderrText),
      stdoutTruncated: Value(stdoutTruncated),
      stderrTruncated: Value(stderrTruncated),
      stdoutStoredInChunks: Value(stdoutStoredInChunks),
      stderrStoredInChunks: Value(stderrStoredInChunks),
      definitionSnapshotHash: definitionSnapshotHash == null && nullToAbsent
          ? const Value.absent()
          : Value(definitionSnapshotHash),
      contextHash: contextHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contextHash),
      redactionApplied: Value(redactionApplied),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      failurePhase: failurePhase == null && nullToAbsent
          ? const Value.absent()
          : Value(failurePhase),
      failureMessage: failureMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(failureMessage),
    );
  }

  factory AgentActionExecutionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentActionExecutionData(
      id: serializer.fromJson<String>(json['id']),
      actionId: serializer.fromJson<String>(json['actionId']),
      actionType: serializer.fromJson<String>(json['actionType']),
      status: serializer.fromJson<String>(json['status']),
      requestedAt: serializer.fromJson<DateTime>(json['requestedAt']),
      source: serializer.fromJson<String>(json['source']),
      idempotencyKey: serializer.fromJson<String?>(json['idempotencyKey']),
      requestedBy: serializer.fromJson<String?>(json['requestedBy']),
      traceId: serializer.fromJson<String?>(json['traceId']),
      runtimeInstanceId: serializer.fromJson<String?>(
        json['runtimeInstanceId'],
      ),
      runtimeSessionId: serializer.fromJson<String?>(json['runtimeSessionId']),
      triggerId: serializer.fromJson<String?>(json['triggerId']),
      triggerType: serializer.fromJson<String?>(json['triggerType']),
      scheduledAt: serializer.fromJson<DateTime?>(json['scheduledAt']),
      triggeredAt: serializer.fromJson<DateTime?>(json['triggeredAt']),
      queueStartedAt: serializer.fromJson<DateTime?>(json['queueStartedAt']),
      processStartedAt: serializer.fromJson<DateTime?>(
        json['processStartedAt'],
      ),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      timeoutAt: serializer.fromJson<DateTime?>(json['timeoutAt']),
      pid: serializer.fromJson<int?>(json['pid']),
      exitCode: serializer.fromJson<int?>(json['exitCode']),
      processExecutable: serializer.fromJson<String?>(
        json['processExecutable'],
      ),
      processArgumentCount: serializer.fromJson<int?>(
        json['processArgumentCount'],
      ),
      processCommandPreview: serializer.fromJson<String?>(
        json['processCommandPreview'],
      ),
      stdoutText: serializer.fromJson<String?>(json['stdoutText']),
      stderrText: serializer.fromJson<String?>(json['stderrText']),
      stdoutTruncated: serializer.fromJson<bool>(json['stdoutTruncated']),
      stderrTruncated: serializer.fromJson<bool>(json['stderrTruncated']),
      stdoutStoredInChunks: serializer.fromJson<bool>(
        json['stdoutStoredInChunks'],
      ),
      stderrStoredInChunks: serializer.fromJson<bool>(
        json['stderrStoredInChunks'],
      ),
      definitionSnapshotHash: serializer.fromJson<String?>(
        json['definitionSnapshotHash'],
      ),
      contextHash: serializer.fromJson<String?>(json['contextHash']),
      redactionApplied: serializer.fromJson<bool>(json['redactionApplied']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      failurePhase: serializer.fromJson<String?>(json['failurePhase']),
      failureMessage: serializer.fromJson<String?>(json['failureMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actionId': serializer.toJson<String>(actionId),
      'actionType': serializer.toJson<String>(actionType),
      'status': serializer.toJson<String>(status),
      'requestedAt': serializer.toJson<DateTime>(requestedAt),
      'source': serializer.toJson<String>(source),
      'idempotencyKey': serializer.toJson<String?>(idempotencyKey),
      'requestedBy': serializer.toJson<String?>(requestedBy),
      'traceId': serializer.toJson<String?>(traceId),
      'runtimeInstanceId': serializer.toJson<String?>(runtimeInstanceId),
      'runtimeSessionId': serializer.toJson<String?>(runtimeSessionId),
      'triggerId': serializer.toJson<String?>(triggerId),
      'triggerType': serializer.toJson<String?>(triggerType),
      'scheduledAt': serializer.toJson<DateTime?>(scheduledAt),
      'triggeredAt': serializer.toJson<DateTime?>(triggeredAt),
      'queueStartedAt': serializer.toJson<DateTime?>(queueStartedAt),
      'processStartedAt': serializer.toJson<DateTime?>(processStartedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'timeoutAt': serializer.toJson<DateTime?>(timeoutAt),
      'pid': serializer.toJson<int?>(pid),
      'exitCode': serializer.toJson<int?>(exitCode),
      'processExecutable': serializer.toJson<String?>(processExecutable),
      'processArgumentCount': serializer.toJson<int?>(processArgumentCount),
      'processCommandPreview': serializer.toJson<String?>(
        processCommandPreview,
      ),
      'stdoutText': serializer.toJson<String?>(stdoutText),
      'stderrText': serializer.toJson<String?>(stderrText),
      'stdoutTruncated': serializer.toJson<bool>(stdoutTruncated),
      'stderrTruncated': serializer.toJson<bool>(stderrTruncated),
      'stdoutStoredInChunks': serializer.toJson<bool>(stdoutStoredInChunks),
      'stderrStoredInChunks': serializer.toJson<bool>(stderrStoredInChunks),
      'definitionSnapshotHash': serializer.toJson<String?>(
        definitionSnapshotHash,
      ),
      'contextHash': serializer.toJson<String?>(contextHash),
      'redactionApplied': serializer.toJson<bool>(redactionApplied),
      'failureCode': serializer.toJson<String?>(failureCode),
      'failurePhase': serializer.toJson<String?>(failurePhase),
      'failureMessage': serializer.toJson<String?>(failureMessage),
    };
  }

  AgentActionExecutionData copyWith({
    String? id,
    String? actionId,
    String? actionType,
    String? status,
    DateTime? requestedAt,
    String? source,
    Value<String?> idempotencyKey = const Value.absent(),
    Value<String?> requestedBy = const Value.absent(),
    Value<String?> traceId = const Value.absent(),
    Value<String?> runtimeInstanceId = const Value.absent(),
    Value<String?> runtimeSessionId = const Value.absent(),
    Value<String?> triggerId = const Value.absent(),
    Value<String?> triggerType = const Value.absent(),
    Value<DateTime?> scheduledAt = const Value.absent(),
    Value<DateTime?> triggeredAt = const Value.absent(),
    Value<DateTime?> queueStartedAt = const Value.absent(),
    Value<DateTime?> processStartedAt = const Value.absent(),
    Value<DateTime?> finishedAt = const Value.absent(),
    Value<DateTime?> timeoutAt = const Value.absent(),
    Value<int?> pid = const Value.absent(),
    Value<int?> exitCode = const Value.absent(),
    Value<String?> processExecutable = const Value.absent(),
    Value<int?> processArgumentCount = const Value.absent(),
    Value<String?> processCommandPreview = const Value.absent(),
    Value<String?> stdoutText = const Value.absent(),
    Value<String?> stderrText = const Value.absent(),
    bool? stdoutTruncated,
    bool? stderrTruncated,
    bool? stdoutStoredInChunks,
    bool? stderrStoredInChunks,
    Value<String?> definitionSnapshotHash = const Value.absent(),
    Value<String?> contextHash = const Value.absent(),
    bool? redactionApplied,
    Value<String?> failureCode = const Value.absent(),
    Value<String?> failurePhase = const Value.absent(),
    Value<String?> failureMessage = const Value.absent(),
  }) => AgentActionExecutionData(
    id: id ?? this.id,
    actionId: actionId ?? this.actionId,
    actionType: actionType ?? this.actionType,
    status: status ?? this.status,
    requestedAt: requestedAt ?? this.requestedAt,
    source: source ?? this.source,
    idempotencyKey: idempotencyKey.present
        ? idempotencyKey.value
        : this.idempotencyKey,
    requestedBy: requestedBy.present ? requestedBy.value : this.requestedBy,
    traceId: traceId.present ? traceId.value : this.traceId,
    runtimeInstanceId: runtimeInstanceId.present
        ? runtimeInstanceId.value
        : this.runtimeInstanceId,
    runtimeSessionId: runtimeSessionId.present
        ? runtimeSessionId.value
        : this.runtimeSessionId,
    triggerId: triggerId.present ? triggerId.value : this.triggerId,
    triggerType: triggerType.present ? triggerType.value : this.triggerType,
    scheduledAt: scheduledAt.present ? scheduledAt.value : this.scheduledAt,
    triggeredAt: triggeredAt.present ? triggeredAt.value : this.triggeredAt,
    queueStartedAt: queueStartedAt.present
        ? queueStartedAt.value
        : this.queueStartedAt,
    processStartedAt: processStartedAt.present
        ? processStartedAt.value
        : this.processStartedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    timeoutAt: timeoutAt.present ? timeoutAt.value : this.timeoutAt,
    pid: pid.present ? pid.value : this.pid,
    exitCode: exitCode.present ? exitCode.value : this.exitCode,
    processExecutable: processExecutable.present
        ? processExecutable.value
        : this.processExecutable,
    processArgumentCount: processArgumentCount.present
        ? processArgumentCount.value
        : this.processArgumentCount,
    processCommandPreview: processCommandPreview.present
        ? processCommandPreview.value
        : this.processCommandPreview,
    stdoutText: stdoutText.present ? stdoutText.value : this.stdoutText,
    stderrText: stderrText.present ? stderrText.value : this.stderrText,
    stdoutTruncated: stdoutTruncated ?? this.stdoutTruncated,
    stderrTruncated: stderrTruncated ?? this.stderrTruncated,
    stdoutStoredInChunks: stdoutStoredInChunks ?? this.stdoutStoredInChunks,
    stderrStoredInChunks: stderrStoredInChunks ?? this.stderrStoredInChunks,
    definitionSnapshotHash: definitionSnapshotHash.present
        ? definitionSnapshotHash.value
        : this.definitionSnapshotHash,
    contextHash: contextHash.present ? contextHash.value : this.contextHash,
    redactionApplied: redactionApplied ?? this.redactionApplied,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    failurePhase: failurePhase.present ? failurePhase.value : this.failurePhase,
    failureMessage: failureMessage.present
        ? failureMessage.value
        : this.failureMessage,
  );
  AgentActionExecutionData copyWithCompanion(
    AgentActionExecutionTableCompanion data,
  ) {
    return AgentActionExecutionData(
      id: data.id.present ? data.id.value : this.id,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      actionType: data.actionType.present
          ? data.actionType.value
          : this.actionType,
      status: data.status.present ? data.status.value : this.status,
      requestedAt: data.requestedAt.present
          ? data.requestedAt.value
          : this.requestedAt,
      source: data.source.present ? data.source.value : this.source,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      requestedBy: data.requestedBy.present
          ? data.requestedBy.value
          : this.requestedBy,
      traceId: data.traceId.present ? data.traceId.value : this.traceId,
      runtimeInstanceId: data.runtimeInstanceId.present
          ? data.runtimeInstanceId.value
          : this.runtimeInstanceId,
      runtimeSessionId: data.runtimeSessionId.present
          ? data.runtimeSessionId.value
          : this.runtimeSessionId,
      triggerId: data.triggerId.present ? data.triggerId.value : this.triggerId,
      triggerType: data.triggerType.present
          ? data.triggerType.value
          : this.triggerType,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      triggeredAt: data.triggeredAt.present
          ? data.triggeredAt.value
          : this.triggeredAt,
      queueStartedAt: data.queueStartedAt.present
          ? data.queueStartedAt.value
          : this.queueStartedAt,
      processStartedAt: data.processStartedAt.present
          ? data.processStartedAt.value
          : this.processStartedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      timeoutAt: data.timeoutAt.present ? data.timeoutAt.value : this.timeoutAt,
      pid: data.pid.present ? data.pid.value : this.pid,
      exitCode: data.exitCode.present ? data.exitCode.value : this.exitCode,
      processExecutable: data.processExecutable.present
          ? data.processExecutable.value
          : this.processExecutable,
      processArgumentCount: data.processArgumentCount.present
          ? data.processArgumentCount.value
          : this.processArgumentCount,
      processCommandPreview: data.processCommandPreview.present
          ? data.processCommandPreview.value
          : this.processCommandPreview,
      stdoutText: data.stdoutText.present
          ? data.stdoutText.value
          : this.stdoutText,
      stderrText: data.stderrText.present
          ? data.stderrText.value
          : this.stderrText,
      stdoutTruncated: data.stdoutTruncated.present
          ? data.stdoutTruncated.value
          : this.stdoutTruncated,
      stderrTruncated: data.stderrTruncated.present
          ? data.stderrTruncated.value
          : this.stderrTruncated,
      stdoutStoredInChunks: data.stdoutStoredInChunks.present
          ? data.stdoutStoredInChunks.value
          : this.stdoutStoredInChunks,
      stderrStoredInChunks: data.stderrStoredInChunks.present
          ? data.stderrStoredInChunks.value
          : this.stderrStoredInChunks,
      definitionSnapshotHash: data.definitionSnapshotHash.present
          ? data.definitionSnapshotHash.value
          : this.definitionSnapshotHash,
      contextHash: data.contextHash.present
          ? data.contextHash.value
          : this.contextHash,
      redactionApplied: data.redactionApplied.present
          ? data.redactionApplied.value
          : this.redactionApplied,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      failurePhase: data.failurePhase.present
          ? data.failurePhase.value
          : this.failurePhase,
      failureMessage: data.failureMessage.present
          ? data.failureMessage.value
          : this.failureMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionExecutionData(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('actionType: $actionType, ')
          ..write('status: $status, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('source: $source, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('requestedBy: $requestedBy, ')
          ..write('traceId: $traceId, ')
          ..write('runtimeInstanceId: $runtimeInstanceId, ')
          ..write('runtimeSessionId: $runtimeSessionId, ')
          ..write('triggerId: $triggerId, ')
          ..write('triggerType: $triggerType, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('triggeredAt: $triggeredAt, ')
          ..write('queueStartedAt: $queueStartedAt, ')
          ..write('processStartedAt: $processStartedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('timeoutAt: $timeoutAt, ')
          ..write('pid: $pid, ')
          ..write('exitCode: $exitCode, ')
          ..write('processExecutable: $processExecutable, ')
          ..write('processArgumentCount: $processArgumentCount, ')
          ..write('processCommandPreview: $processCommandPreview, ')
          ..write('stdoutText: $stdoutText, ')
          ..write('stderrText: $stderrText, ')
          ..write('stdoutTruncated: $stdoutTruncated, ')
          ..write('stderrTruncated: $stderrTruncated, ')
          ..write('stdoutStoredInChunks: $stdoutStoredInChunks, ')
          ..write('stderrStoredInChunks: $stderrStoredInChunks, ')
          ..write('definitionSnapshotHash: $definitionSnapshotHash, ')
          ..write('contextHash: $contextHash, ')
          ..write('redactionApplied: $redactionApplied, ')
          ..write('failureCode: $failureCode, ')
          ..write('failurePhase: $failurePhase, ')
          ..write('failureMessage: $failureMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    actionId,
    actionType,
    status,
    requestedAt,
    source,
    idempotencyKey,
    requestedBy,
    traceId,
    runtimeInstanceId,
    runtimeSessionId,
    triggerId,
    triggerType,
    scheduledAt,
    triggeredAt,
    queueStartedAt,
    processStartedAt,
    finishedAt,
    timeoutAt,
    pid,
    exitCode,
    processExecutable,
    processArgumentCount,
    processCommandPreview,
    stdoutText,
    stderrText,
    stdoutTruncated,
    stderrTruncated,
    stdoutStoredInChunks,
    stderrStoredInChunks,
    definitionSnapshotHash,
    contextHash,
    redactionApplied,
    failureCode,
    failurePhase,
    failureMessage,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentActionExecutionData &&
          other.id == this.id &&
          other.actionId == this.actionId &&
          other.actionType == this.actionType &&
          other.status == this.status &&
          other.requestedAt == this.requestedAt &&
          other.source == this.source &&
          other.idempotencyKey == this.idempotencyKey &&
          other.requestedBy == this.requestedBy &&
          other.traceId == this.traceId &&
          other.runtimeInstanceId == this.runtimeInstanceId &&
          other.runtimeSessionId == this.runtimeSessionId &&
          other.triggerId == this.triggerId &&
          other.triggerType == this.triggerType &&
          other.scheduledAt == this.scheduledAt &&
          other.triggeredAt == this.triggeredAt &&
          other.queueStartedAt == this.queueStartedAt &&
          other.processStartedAt == this.processStartedAt &&
          other.finishedAt == this.finishedAt &&
          other.timeoutAt == this.timeoutAt &&
          other.pid == this.pid &&
          other.exitCode == this.exitCode &&
          other.processExecutable == this.processExecutable &&
          other.processArgumentCount == this.processArgumentCount &&
          other.processCommandPreview == this.processCommandPreview &&
          other.stdoutText == this.stdoutText &&
          other.stderrText == this.stderrText &&
          other.stdoutTruncated == this.stdoutTruncated &&
          other.stderrTruncated == this.stderrTruncated &&
          other.stdoutStoredInChunks == this.stdoutStoredInChunks &&
          other.stderrStoredInChunks == this.stderrStoredInChunks &&
          other.definitionSnapshotHash == this.definitionSnapshotHash &&
          other.contextHash == this.contextHash &&
          other.redactionApplied == this.redactionApplied &&
          other.failureCode == this.failureCode &&
          other.failurePhase == this.failurePhase &&
          other.failureMessage == this.failureMessage);
}

class AgentActionExecutionTableCompanion
    extends UpdateCompanion<AgentActionExecutionData> {
  final Value<String> id;
  final Value<String> actionId;
  final Value<String> actionType;
  final Value<String> status;
  final Value<DateTime> requestedAt;
  final Value<String> source;
  final Value<String?> idempotencyKey;
  final Value<String?> requestedBy;
  final Value<String?> traceId;
  final Value<String?> runtimeInstanceId;
  final Value<String?> runtimeSessionId;
  final Value<String?> triggerId;
  final Value<String?> triggerType;
  final Value<DateTime?> scheduledAt;
  final Value<DateTime?> triggeredAt;
  final Value<DateTime?> queueStartedAt;
  final Value<DateTime?> processStartedAt;
  final Value<DateTime?> finishedAt;
  final Value<DateTime?> timeoutAt;
  final Value<int?> pid;
  final Value<int?> exitCode;
  final Value<String?> processExecutable;
  final Value<int?> processArgumentCount;
  final Value<String?> processCommandPreview;
  final Value<String?> stdoutText;
  final Value<String?> stderrText;
  final Value<bool> stdoutTruncated;
  final Value<bool> stderrTruncated;
  final Value<bool> stdoutStoredInChunks;
  final Value<bool> stderrStoredInChunks;
  final Value<String?> definitionSnapshotHash;
  final Value<String?> contextHash;
  final Value<bool> redactionApplied;
  final Value<String?> failureCode;
  final Value<String?> failurePhase;
  final Value<String?> failureMessage;
  final Value<int> rowid;
  const AgentActionExecutionTableCompanion({
    this.id = const Value.absent(),
    this.actionId = const Value.absent(),
    this.actionType = const Value.absent(),
    this.status = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.requestedBy = const Value.absent(),
    this.traceId = const Value.absent(),
    this.runtimeInstanceId = const Value.absent(),
    this.runtimeSessionId = const Value.absent(),
    this.triggerId = const Value.absent(),
    this.triggerType = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.triggeredAt = const Value.absent(),
    this.queueStartedAt = const Value.absent(),
    this.processStartedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.timeoutAt = const Value.absent(),
    this.pid = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.processExecutable = const Value.absent(),
    this.processArgumentCount = const Value.absent(),
    this.processCommandPreview = const Value.absent(),
    this.stdoutText = const Value.absent(),
    this.stderrText = const Value.absent(),
    this.stdoutTruncated = const Value.absent(),
    this.stderrTruncated = const Value.absent(),
    this.stdoutStoredInChunks = const Value.absent(),
    this.stderrStoredInChunks = const Value.absent(),
    this.definitionSnapshotHash = const Value.absent(),
    this.contextHash = const Value.absent(),
    this.redactionApplied = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.failurePhase = const Value.absent(),
    this.failureMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentActionExecutionTableCompanion.insert({
    required String id,
    required String actionId,
    required String actionType,
    required String status,
    required DateTime requestedAt,
    required String source,
    this.idempotencyKey = const Value.absent(),
    this.requestedBy = const Value.absent(),
    this.traceId = const Value.absent(),
    this.runtimeInstanceId = const Value.absent(),
    this.runtimeSessionId = const Value.absent(),
    this.triggerId = const Value.absent(),
    this.triggerType = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.triggeredAt = const Value.absent(),
    this.queueStartedAt = const Value.absent(),
    this.processStartedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.timeoutAt = const Value.absent(),
    this.pid = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.processExecutable = const Value.absent(),
    this.processArgumentCount = const Value.absent(),
    this.processCommandPreview = const Value.absent(),
    this.stdoutText = const Value.absent(),
    this.stderrText = const Value.absent(),
    this.stdoutTruncated = const Value.absent(),
    this.stderrTruncated = const Value.absent(),
    this.stdoutStoredInChunks = const Value.absent(),
    this.stderrStoredInChunks = const Value.absent(),
    this.definitionSnapshotHash = const Value.absent(),
    this.contextHash = const Value.absent(),
    this.redactionApplied = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.failurePhase = const Value.absent(),
    this.failureMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       actionId = Value(actionId),
       actionType = Value(actionType),
       status = Value(status),
       requestedAt = Value(requestedAt),
       source = Value(source);
  static Insertable<AgentActionExecutionData> custom({
    Expression<String>? id,
    Expression<String>? actionId,
    Expression<String>? actionType,
    Expression<String>? status,
    Expression<DateTime>? requestedAt,
    Expression<String>? source,
    Expression<String>? idempotencyKey,
    Expression<String>? requestedBy,
    Expression<String>? traceId,
    Expression<String>? runtimeInstanceId,
    Expression<String>? runtimeSessionId,
    Expression<String>? triggerId,
    Expression<String>? triggerType,
    Expression<DateTime>? scheduledAt,
    Expression<DateTime>? triggeredAt,
    Expression<DateTime>? queueStartedAt,
    Expression<DateTime>? processStartedAt,
    Expression<DateTime>? finishedAt,
    Expression<DateTime>? timeoutAt,
    Expression<int>? pid,
    Expression<int>? exitCode,
    Expression<String>? processExecutable,
    Expression<int>? processArgumentCount,
    Expression<String>? processCommandPreview,
    Expression<String>? stdoutText,
    Expression<String>? stderrText,
    Expression<bool>? stdoutTruncated,
    Expression<bool>? stderrTruncated,
    Expression<bool>? stdoutStoredInChunks,
    Expression<bool>? stderrStoredInChunks,
    Expression<String>? definitionSnapshotHash,
    Expression<String>? contextHash,
    Expression<bool>? redactionApplied,
    Expression<String>? failureCode,
    Expression<String>? failurePhase,
    Expression<String>? failureMessage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actionId != null) 'action_id': actionId,
      if (actionType != null) 'action_type': actionType,
      if (status != null) 'status': status,
      if (requestedAt != null) 'requested_at': requestedAt,
      if (source != null) 'source': source,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (traceId != null) 'trace_id': traceId,
      if (runtimeInstanceId != null) 'runtime_instance_id': runtimeInstanceId,
      if (runtimeSessionId != null) 'runtime_session_id': runtimeSessionId,
      if (triggerId != null) 'trigger_id': triggerId,
      if (triggerType != null) 'trigger_type': triggerType,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (triggeredAt != null) 'triggered_at': triggeredAt,
      if (queueStartedAt != null) 'queue_started_at': queueStartedAt,
      if (processStartedAt != null) 'process_started_at': processStartedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (timeoutAt != null) 'timeout_at': timeoutAt,
      if (pid != null) 'pid': pid,
      if (exitCode != null) 'exit_code': exitCode,
      if (processExecutable != null) 'process_executable': processExecutable,
      if (processArgumentCount != null)
        'process_argument_count': processArgumentCount,
      if (processCommandPreview != null)
        'process_command_preview': processCommandPreview,
      if (stdoutText != null) 'stdout_text': stdoutText,
      if (stderrText != null) 'stderr_text': stderrText,
      if (stdoutTruncated != null) 'stdout_truncated': stdoutTruncated,
      if (stderrTruncated != null) 'stderr_truncated': stderrTruncated,
      if (stdoutStoredInChunks != null)
        'stdout_stored_in_chunks': stdoutStoredInChunks,
      if (stderrStoredInChunks != null)
        'stderr_stored_in_chunks': stderrStoredInChunks,
      if (definitionSnapshotHash != null)
        'definition_snapshot_hash': definitionSnapshotHash,
      if (contextHash != null) 'context_hash': contextHash,
      if (redactionApplied != null) 'redaction_applied': redactionApplied,
      if (failureCode != null) 'failure_code': failureCode,
      if (failurePhase != null) 'failure_phase': failurePhase,
      if (failureMessage != null) 'failure_message': failureMessage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentActionExecutionTableCompanion copyWith({
    Value<String>? id,
    Value<String>? actionId,
    Value<String>? actionType,
    Value<String>? status,
    Value<DateTime>? requestedAt,
    Value<String>? source,
    Value<String?>? idempotencyKey,
    Value<String?>? requestedBy,
    Value<String?>? traceId,
    Value<String?>? runtimeInstanceId,
    Value<String?>? runtimeSessionId,
    Value<String?>? triggerId,
    Value<String?>? triggerType,
    Value<DateTime?>? scheduledAt,
    Value<DateTime?>? triggeredAt,
    Value<DateTime?>? queueStartedAt,
    Value<DateTime?>? processStartedAt,
    Value<DateTime?>? finishedAt,
    Value<DateTime?>? timeoutAt,
    Value<int?>? pid,
    Value<int?>? exitCode,
    Value<String?>? processExecutable,
    Value<int?>? processArgumentCount,
    Value<String?>? processCommandPreview,
    Value<String?>? stdoutText,
    Value<String?>? stderrText,
    Value<bool>? stdoutTruncated,
    Value<bool>? stderrTruncated,
    Value<bool>? stdoutStoredInChunks,
    Value<bool>? stderrStoredInChunks,
    Value<String?>? definitionSnapshotHash,
    Value<String?>? contextHash,
    Value<bool>? redactionApplied,
    Value<String?>? failureCode,
    Value<String?>? failurePhase,
    Value<String?>? failureMessage,
    Value<int>? rowid,
  }) {
    return AgentActionExecutionTableCompanion(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      actionType: actionType ?? this.actionType,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      source: source ?? this.source,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      requestedBy: requestedBy ?? this.requestedBy,
      traceId: traceId ?? this.traceId,
      runtimeInstanceId: runtimeInstanceId ?? this.runtimeInstanceId,
      runtimeSessionId: runtimeSessionId ?? this.runtimeSessionId,
      triggerId: triggerId ?? this.triggerId,
      triggerType: triggerType ?? this.triggerType,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      queueStartedAt: queueStartedAt ?? this.queueStartedAt,
      processStartedAt: processStartedAt ?? this.processStartedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      timeoutAt: timeoutAt ?? this.timeoutAt,
      pid: pid ?? this.pid,
      exitCode: exitCode ?? this.exitCode,
      processExecutable: processExecutable ?? this.processExecutable,
      processArgumentCount: processArgumentCount ?? this.processArgumentCount,
      processCommandPreview:
          processCommandPreview ?? this.processCommandPreview,
      stdoutText: stdoutText ?? this.stdoutText,
      stderrText: stderrText ?? this.stderrText,
      stdoutTruncated: stdoutTruncated ?? this.stdoutTruncated,
      stderrTruncated: stderrTruncated ?? this.stderrTruncated,
      stdoutStoredInChunks: stdoutStoredInChunks ?? this.stdoutStoredInChunks,
      stderrStoredInChunks: stderrStoredInChunks ?? this.stderrStoredInChunks,
      definitionSnapshotHash:
          definitionSnapshotHash ?? this.definitionSnapshotHash,
      contextHash: contextHash ?? this.contextHash,
      redactionApplied: redactionApplied ?? this.redactionApplied,
      failureCode: failureCode ?? this.failureCode,
      failurePhase: failurePhase ?? this.failurePhase,
      failureMessage: failureMessage ?? this.failureMessage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (actionType.present) {
      map['action_type'] = Variable<String>(actionType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (requestedAt.present) {
      map['requested_at'] = Variable<DateTime>(requestedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (requestedBy.present) {
      map['requested_by'] = Variable<String>(requestedBy.value);
    }
    if (traceId.present) {
      map['trace_id'] = Variable<String>(traceId.value);
    }
    if (runtimeInstanceId.present) {
      map['runtime_instance_id'] = Variable<String>(runtimeInstanceId.value);
    }
    if (runtimeSessionId.present) {
      map['runtime_session_id'] = Variable<String>(runtimeSessionId.value);
    }
    if (triggerId.present) {
      map['trigger_id'] = Variable<String>(triggerId.value);
    }
    if (triggerType.present) {
      map['trigger_type'] = Variable<String>(triggerType.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (triggeredAt.present) {
      map['triggered_at'] = Variable<DateTime>(triggeredAt.value);
    }
    if (queueStartedAt.present) {
      map['queue_started_at'] = Variable<DateTime>(queueStartedAt.value);
    }
    if (processStartedAt.present) {
      map['process_started_at'] = Variable<DateTime>(processStartedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (timeoutAt.present) {
      map['timeout_at'] = Variable<DateTime>(timeoutAt.value);
    }
    if (pid.present) {
      map['pid'] = Variable<int>(pid.value);
    }
    if (exitCode.present) {
      map['exit_code'] = Variable<int>(exitCode.value);
    }
    if (processExecutable.present) {
      map['process_executable'] = Variable<String>(processExecutable.value);
    }
    if (processArgumentCount.present) {
      map['process_argument_count'] = Variable<int>(processArgumentCount.value);
    }
    if (processCommandPreview.present) {
      map['process_command_preview'] = Variable<String>(
        processCommandPreview.value,
      );
    }
    if (stdoutText.present) {
      map['stdout_text'] = Variable<String>(stdoutText.value);
    }
    if (stderrText.present) {
      map['stderr_text'] = Variable<String>(stderrText.value);
    }
    if (stdoutTruncated.present) {
      map['stdout_truncated'] = Variable<bool>(stdoutTruncated.value);
    }
    if (stderrTruncated.present) {
      map['stderr_truncated'] = Variable<bool>(stderrTruncated.value);
    }
    if (stdoutStoredInChunks.present) {
      map['stdout_stored_in_chunks'] = Variable<bool>(
        stdoutStoredInChunks.value,
      );
    }
    if (stderrStoredInChunks.present) {
      map['stderr_stored_in_chunks'] = Variable<bool>(
        stderrStoredInChunks.value,
      );
    }
    if (definitionSnapshotHash.present) {
      map['definition_snapshot_hash'] = Variable<String>(
        definitionSnapshotHash.value,
      );
    }
    if (contextHash.present) {
      map['context_hash'] = Variable<String>(contextHash.value);
    }
    if (redactionApplied.present) {
      map['redaction_applied'] = Variable<bool>(redactionApplied.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (failurePhase.present) {
      map['failure_phase'] = Variable<String>(failurePhase.value);
    }
    if (failureMessage.present) {
      map['failure_message'] = Variable<String>(failureMessage.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionExecutionTableCompanion(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('actionType: $actionType, ')
          ..write('status: $status, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('source: $source, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('requestedBy: $requestedBy, ')
          ..write('traceId: $traceId, ')
          ..write('runtimeInstanceId: $runtimeInstanceId, ')
          ..write('runtimeSessionId: $runtimeSessionId, ')
          ..write('triggerId: $triggerId, ')
          ..write('triggerType: $triggerType, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('triggeredAt: $triggeredAt, ')
          ..write('queueStartedAt: $queueStartedAt, ')
          ..write('processStartedAt: $processStartedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('timeoutAt: $timeoutAt, ')
          ..write('pid: $pid, ')
          ..write('exitCode: $exitCode, ')
          ..write('processExecutable: $processExecutable, ')
          ..write('processArgumentCount: $processArgumentCount, ')
          ..write('processCommandPreview: $processCommandPreview, ')
          ..write('stdoutText: $stdoutText, ')
          ..write('stderrText: $stderrText, ')
          ..write('stdoutTruncated: $stdoutTruncated, ')
          ..write('stderrTruncated: $stderrTruncated, ')
          ..write('stdoutStoredInChunks: $stdoutStoredInChunks, ')
          ..write('stderrStoredInChunks: $stderrStoredInChunks, ')
          ..write('definitionSnapshotHash: $definitionSnapshotHash, ')
          ..write('contextHash: $contextHash, ')
          ..write('redactionApplied: $redactionApplied, ')
          ..write('failureCode: $failureCode, ')
          ..write('failurePhase: $failurePhase, ')
          ..write('failureMessage: $failureMessage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RpcIdempotencyCacheTableTable extends RpcIdempotencyCacheTable
    with TableInfo<$RpcIdempotencyCacheTableTable, RpcIdempotencyCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RpcIdempotencyCacheTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _responseJsonMeta = const VerificationMeta(
    'responseJson',
  );
  @override
  late final GeneratedColumn<String> responseJson = GeneratedColumn<String>(
    'response_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestFingerprintMeta =
      const VerificationMeta('requestFingerprint');
  @override
  late final GeneratedColumn<String> requestFingerprint =
      GeneratedColumn<String>(
        'request_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
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
    cacheKey,
    responseJson,
    requestFingerprint,
    expiresAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rpc_idempotency_cache_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<RpcIdempotencyCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('response_json')) {
      context.handle(
        _responseJsonMeta,
        responseJson.isAcceptableOrUnknown(
          data['response_json']!,
          _responseJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_responseJsonMeta);
    }
    if (data.containsKey('request_fingerprint')) {
      context.handle(
        _requestFingerprintMeta,
        requestFingerprint.isAcceptableOrUnknown(
          data['request_fingerprint']!,
          _requestFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  RpcIdempotencyCacheData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RpcIdempotencyCacheData(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      responseJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}response_json'],
      )!,
      requestFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_fingerprint'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RpcIdempotencyCacheTableTable createAlias(String alias) {
    return $RpcIdempotencyCacheTableTable(attachedDatabase, alias);
  }
}

class RpcIdempotencyCacheData extends DataClass
    implements Insertable<RpcIdempotencyCacheData> {
  final String cacheKey;
  final String responseJson;
  final String? requestFingerprint;
  final DateTime expiresAt;
  final DateTime updatedAt;
  const RpcIdempotencyCacheData({
    required this.cacheKey,
    required this.responseJson,
    this.requestFingerprint,
    required this.expiresAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['response_json'] = Variable<String>(responseJson);
    if (!nullToAbsent || requestFingerprint != null) {
      map['request_fingerprint'] = Variable<String>(requestFingerprint);
    }
    map['expires_at'] = Variable<DateTime>(expiresAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RpcIdempotencyCacheTableCompanion toCompanion(bool nullToAbsent) {
    return RpcIdempotencyCacheTableCompanion(
      cacheKey: Value(cacheKey),
      responseJson: Value(responseJson),
      requestFingerprint: requestFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(requestFingerprint),
      expiresAt: Value(expiresAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory RpcIdempotencyCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RpcIdempotencyCacheData(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      responseJson: serializer.fromJson<String>(json['responseJson']),
      requestFingerprint: serializer.fromJson<String?>(
        json['requestFingerprint'],
      ),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'responseJson': serializer.toJson<String>(responseJson),
      'requestFingerprint': serializer.toJson<String?>(requestFingerprint),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RpcIdempotencyCacheData copyWith({
    String? cacheKey,
    String? responseJson,
    Value<String?> requestFingerprint = const Value.absent(),
    DateTime? expiresAt,
    DateTime? updatedAt,
  }) => RpcIdempotencyCacheData(
    cacheKey: cacheKey ?? this.cacheKey,
    responseJson: responseJson ?? this.responseJson,
    requestFingerprint: requestFingerprint.present
        ? requestFingerprint.value
        : this.requestFingerprint,
    expiresAt: expiresAt ?? this.expiresAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RpcIdempotencyCacheData copyWithCompanion(
    RpcIdempotencyCacheTableCompanion data,
  ) {
    return RpcIdempotencyCacheData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      responseJson: data.responseJson.present
          ? data.responseJson.value
          : this.responseJson,
      requestFingerprint: data.requestFingerprint.present
          ? data.requestFingerprint.value
          : this.requestFingerprint,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RpcIdempotencyCacheData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('responseJson: $responseJson, ')
          ..write('requestFingerprint: $requestFingerprint, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    cacheKey,
    responseJson,
    requestFingerprint,
    expiresAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RpcIdempotencyCacheData &&
          other.cacheKey == this.cacheKey &&
          other.responseJson == this.responseJson &&
          other.requestFingerprint == this.requestFingerprint &&
          other.expiresAt == this.expiresAt &&
          other.updatedAt == this.updatedAt);
}

class RpcIdempotencyCacheTableCompanion
    extends UpdateCompanion<RpcIdempotencyCacheData> {
  final Value<String> cacheKey;
  final Value<String> responseJson;
  final Value<String?> requestFingerprint;
  final Value<DateTime> expiresAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RpcIdempotencyCacheTableCompanion({
    this.cacheKey = const Value.absent(),
    this.responseJson = const Value.absent(),
    this.requestFingerprint = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RpcIdempotencyCacheTableCompanion.insert({
    required String cacheKey,
    required String responseJson,
    this.requestFingerprint = const Value.absent(),
    required DateTime expiresAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       responseJson = Value(responseJson),
       expiresAt = Value(expiresAt),
       updatedAt = Value(updatedAt);
  static Insertable<RpcIdempotencyCacheData> custom({
    Expression<String>? cacheKey,
    Expression<String>? responseJson,
    Expression<String>? requestFingerprint,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (responseJson != null) 'response_json': responseJson,
      if (requestFingerprint != null) 'request_fingerprint': requestFingerprint,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RpcIdempotencyCacheTableCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? responseJson,
    Value<String?>? requestFingerprint,
    Value<DateTime>? expiresAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RpcIdempotencyCacheTableCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      responseJson: responseJson ?? this.responseJson,
      requestFingerprint: requestFingerprint ?? this.requestFingerprint,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (responseJson.present) {
      map['response_json'] = Variable<String>(responseJson.value);
    }
    if (requestFingerprint.present) {
      map['request_fingerprint'] = Variable<String>(requestFingerprint.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
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
    return (StringBuffer('RpcIdempotencyCacheTableCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('responseJson: $responseJson, ')
          ..write('requestFingerprint: $requestFingerprint, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentActionRemoteAuditTableTable extends AgentActionRemoteAuditTable
    with
        TableInfo<
          $AgentActionRemoteAuditTableTable,
          AgentActionRemoteAuditData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentActionRemoteAuditTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rpcMethodMeta = const VerificationMeta(
    'rpcMethod',
  );
  @override
  late final GeneratedColumn<String> rpcMethod = GeneratedColumn<String>(
    'rpc_method',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _traceIdMeta = const VerificationMeta(
    'traceId',
  );
  @override
  late final GeneratedColumn<String> traceId = GeneratedColumn<String>(
    'trace_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestedByMeta = const VerificationMeta(
    'requestedBy',
  );
  @override
  late final GeneratedColumn<String> requestedBy = GeneratedColumn<String>(
    'requested_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonCodeMeta = const VerificationMeta(
    'reasonCode',
  );
  @override
  late final GeneratedColumn<String> reasonCode = GeneratedColumn<String>(
    'reason_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rpcErrorCodeMeta = const VerificationMeta(
    'rpcErrorCode',
  );
  @override
  late final GeneratedColumn<int> rpcErrorCode = GeneratedColumn<int>(
    'rpc_error_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _credentialPresentMeta = const VerificationMeta(
    'credentialPresent',
  );
  @override
  late final GeneratedColumn<bool> credentialPresent = GeneratedColumn<bool>(
    'credential_present',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("credential_present" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tokenJtiMeta = const VerificationMeta(
    'tokenJti',
  );
  @override
  late final GeneratedColumn<String> tokenJti = GeneratedColumn<String>(
    'token_jti',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _runtimeInstanceIdMeta = const VerificationMeta(
    'runtimeInstanceId',
  );
  @override
  late final GeneratedColumn<String> runtimeInstanceId =
      GeneratedColumn<String>(
        'runtime_instance_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _runtimeSessionIdMeta = const VerificationMeta(
    'runtimeSessionId',
  );
  @override
  late final GeneratedColumn<String> runtimeSessionId = GeneratedColumn<String>(
    'runtime_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    occurredAt,
    rpcMethod,
    actionId,
    executionId,
    traceId,
    requestedBy,
    outcome,
    reasonCode,
    rpcErrorCode,
    credentialPresent,
    clientId,
    tokenJti,
    runtimeInstanceId,
    runtimeSessionId,
    idempotencyKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_action_remote_audit_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentActionRemoteAuditData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('rpc_method')) {
      context.handle(
        _rpcMethodMeta,
        rpcMethod.isAcceptableOrUnknown(data['rpc_method']!, _rpcMethodMeta),
      );
    } else if (isInserting) {
      context.missing(_rpcMethodMeta);
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
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
    }
    if (data.containsKey('trace_id')) {
      context.handle(
        _traceIdMeta,
        traceId.isAcceptableOrUnknown(data['trace_id']!, _traceIdMeta),
      );
    }
    if (data.containsKey('requested_by')) {
      context.handle(
        _requestedByMeta,
        requestedBy.isAcceptableOrUnknown(
          data['requested_by']!,
          _requestedByMeta,
        ),
      );
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('reason_code')) {
      context.handle(
        _reasonCodeMeta,
        reasonCode.isAcceptableOrUnknown(data['reason_code']!, _reasonCodeMeta),
      );
    }
    if (data.containsKey('rpc_error_code')) {
      context.handle(
        _rpcErrorCodeMeta,
        rpcErrorCode.isAcceptableOrUnknown(
          data['rpc_error_code']!,
          _rpcErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('credential_present')) {
      context.handle(
        _credentialPresentMeta,
        credentialPresent.isAcceptableOrUnknown(
          data['credential_present']!,
          _credentialPresentMeta,
        ),
      );
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    }
    if (data.containsKey('token_jti')) {
      context.handle(
        _tokenJtiMeta,
        tokenJti.isAcceptableOrUnknown(data['token_jti']!, _tokenJtiMeta),
      );
    }
    if (data.containsKey('runtime_instance_id')) {
      context.handle(
        _runtimeInstanceIdMeta,
        runtimeInstanceId.isAcceptableOrUnknown(
          data['runtime_instance_id']!,
          _runtimeInstanceIdMeta,
        ),
      );
    }
    if (data.containsKey('runtime_session_id')) {
      context.handle(
        _runtimeSessionIdMeta,
        runtimeSessionId.isAcceptableOrUnknown(
          data['runtime_session_id']!,
          _runtimeSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AgentActionRemoteAuditData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentActionRemoteAuditData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      rpcMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rpc_method'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      ),
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      ),
      traceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trace_id'],
      ),
      requestedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requested_by'],
      ),
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      reasonCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason_code'],
      ),
      rpcErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rpc_error_code'],
      ),
      credentialPresent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}credential_present'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      ),
      tokenJti: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_jti'],
      ),
      runtimeInstanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runtime_instance_id'],
      ),
      runtimeSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runtime_session_id'],
      ),
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      ),
    );
  }

  @override
  $AgentActionRemoteAuditTableTable createAlias(String alias) {
    return $AgentActionRemoteAuditTableTable(attachedDatabase, alias);
  }
}

class AgentActionRemoteAuditData extends DataClass
    implements Insertable<AgentActionRemoteAuditData> {
  final String id;
  final DateTime occurredAt;
  final String rpcMethod;
  final String? actionId;
  final String? executionId;
  final String? traceId;
  final String? requestedBy;
  final String outcome;
  final String? reasonCode;
  final int? rpcErrorCode;
  final bool credentialPresent;
  final String? clientId;
  final String? tokenJti;
  final String? runtimeInstanceId;
  final String? runtimeSessionId;
  final String? idempotencyKey;
  const AgentActionRemoteAuditData({
    required this.id,
    required this.occurredAt,
    required this.rpcMethod,
    this.actionId,
    this.executionId,
    this.traceId,
    this.requestedBy,
    required this.outcome,
    this.reasonCode,
    this.rpcErrorCode,
    required this.credentialPresent,
    this.clientId,
    this.tokenJti,
    this.runtimeInstanceId,
    this.runtimeSessionId,
    this.idempotencyKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['rpc_method'] = Variable<String>(rpcMethod);
    if (!nullToAbsent || actionId != null) {
      map['action_id'] = Variable<String>(actionId);
    }
    if (!nullToAbsent || executionId != null) {
      map['execution_id'] = Variable<String>(executionId);
    }
    if (!nullToAbsent || traceId != null) {
      map['trace_id'] = Variable<String>(traceId);
    }
    if (!nullToAbsent || requestedBy != null) {
      map['requested_by'] = Variable<String>(requestedBy);
    }
    map['outcome'] = Variable<String>(outcome);
    if (!nullToAbsent || reasonCode != null) {
      map['reason_code'] = Variable<String>(reasonCode);
    }
    if (!nullToAbsent || rpcErrorCode != null) {
      map['rpc_error_code'] = Variable<int>(rpcErrorCode);
    }
    map['credential_present'] = Variable<bool>(credentialPresent);
    if (!nullToAbsent || clientId != null) {
      map['client_id'] = Variable<String>(clientId);
    }
    if (!nullToAbsent || tokenJti != null) {
      map['token_jti'] = Variable<String>(tokenJti);
    }
    if (!nullToAbsent || runtimeInstanceId != null) {
      map['runtime_instance_id'] = Variable<String>(runtimeInstanceId);
    }
    if (!nullToAbsent || runtimeSessionId != null) {
      map['runtime_session_id'] = Variable<String>(runtimeSessionId);
    }
    if (!nullToAbsent || idempotencyKey != null) {
      map['idempotency_key'] = Variable<String>(idempotencyKey);
    }
    return map;
  }

  AgentActionRemoteAuditTableCompanion toCompanion(bool nullToAbsent) {
    return AgentActionRemoteAuditTableCompanion(
      id: Value(id),
      occurredAt: Value(occurredAt),
      rpcMethod: Value(rpcMethod),
      actionId: actionId == null && nullToAbsent
          ? const Value.absent()
          : Value(actionId),
      executionId: executionId == null && nullToAbsent
          ? const Value.absent()
          : Value(executionId),
      traceId: traceId == null && nullToAbsent
          ? const Value.absent()
          : Value(traceId),
      requestedBy: requestedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(requestedBy),
      outcome: Value(outcome),
      reasonCode: reasonCode == null && nullToAbsent
          ? const Value.absent()
          : Value(reasonCode),
      rpcErrorCode: rpcErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(rpcErrorCode),
      credentialPresent: Value(credentialPresent),
      clientId: clientId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientId),
      tokenJti: tokenJti == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenJti),
      runtimeInstanceId: runtimeInstanceId == null && nullToAbsent
          ? const Value.absent()
          : Value(runtimeInstanceId),
      runtimeSessionId: runtimeSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(runtimeSessionId),
      idempotencyKey: idempotencyKey == null && nullToAbsent
          ? const Value.absent()
          : Value(idempotencyKey),
    );
  }

  factory AgentActionRemoteAuditData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentActionRemoteAuditData(
      id: serializer.fromJson<String>(json['id']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      rpcMethod: serializer.fromJson<String>(json['rpcMethod']),
      actionId: serializer.fromJson<String?>(json['actionId']),
      executionId: serializer.fromJson<String?>(json['executionId']),
      traceId: serializer.fromJson<String?>(json['traceId']),
      requestedBy: serializer.fromJson<String?>(json['requestedBy']),
      outcome: serializer.fromJson<String>(json['outcome']),
      reasonCode: serializer.fromJson<String?>(json['reasonCode']),
      rpcErrorCode: serializer.fromJson<int?>(json['rpcErrorCode']),
      credentialPresent: serializer.fromJson<bool>(json['credentialPresent']),
      clientId: serializer.fromJson<String?>(json['clientId']),
      tokenJti: serializer.fromJson<String?>(json['tokenJti']),
      runtimeInstanceId: serializer.fromJson<String?>(
        json['runtimeInstanceId'],
      ),
      runtimeSessionId: serializer.fromJson<String?>(json['runtimeSessionId']),
      idempotencyKey: serializer.fromJson<String?>(json['idempotencyKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'rpcMethod': serializer.toJson<String>(rpcMethod),
      'actionId': serializer.toJson<String?>(actionId),
      'executionId': serializer.toJson<String?>(executionId),
      'traceId': serializer.toJson<String?>(traceId),
      'requestedBy': serializer.toJson<String?>(requestedBy),
      'outcome': serializer.toJson<String>(outcome),
      'reasonCode': serializer.toJson<String?>(reasonCode),
      'rpcErrorCode': serializer.toJson<int?>(rpcErrorCode),
      'credentialPresent': serializer.toJson<bool>(credentialPresent),
      'clientId': serializer.toJson<String?>(clientId),
      'tokenJti': serializer.toJson<String?>(tokenJti),
      'runtimeInstanceId': serializer.toJson<String?>(runtimeInstanceId),
      'runtimeSessionId': serializer.toJson<String?>(runtimeSessionId),
      'idempotencyKey': serializer.toJson<String?>(idempotencyKey),
    };
  }

  AgentActionRemoteAuditData copyWith({
    String? id,
    DateTime? occurredAt,
    String? rpcMethod,
    Value<String?> actionId = const Value.absent(),
    Value<String?> executionId = const Value.absent(),
    Value<String?> traceId = const Value.absent(),
    Value<String?> requestedBy = const Value.absent(),
    String? outcome,
    Value<String?> reasonCode = const Value.absent(),
    Value<int?> rpcErrorCode = const Value.absent(),
    bool? credentialPresent,
    Value<String?> clientId = const Value.absent(),
    Value<String?> tokenJti = const Value.absent(),
    Value<String?> runtimeInstanceId = const Value.absent(),
    Value<String?> runtimeSessionId = const Value.absent(),
    Value<String?> idempotencyKey = const Value.absent(),
  }) => AgentActionRemoteAuditData(
    id: id ?? this.id,
    occurredAt: occurredAt ?? this.occurredAt,
    rpcMethod: rpcMethod ?? this.rpcMethod,
    actionId: actionId.present ? actionId.value : this.actionId,
    executionId: executionId.present ? executionId.value : this.executionId,
    traceId: traceId.present ? traceId.value : this.traceId,
    requestedBy: requestedBy.present ? requestedBy.value : this.requestedBy,
    outcome: outcome ?? this.outcome,
    reasonCode: reasonCode.present ? reasonCode.value : this.reasonCode,
    rpcErrorCode: rpcErrorCode.present ? rpcErrorCode.value : this.rpcErrorCode,
    credentialPresent: credentialPresent ?? this.credentialPresent,
    clientId: clientId.present ? clientId.value : this.clientId,
    tokenJti: tokenJti.present ? tokenJti.value : this.tokenJti,
    runtimeInstanceId: runtimeInstanceId.present
        ? runtimeInstanceId.value
        : this.runtimeInstanceId,
    runtimeSessionId: runtimeSessionId.present
        ? runtimeSessionId.value
        : this.runtimeSessionId,
    idempotencyKey: idempotencyKey.present
        ? idempotencyKey.value
        : this.idempotencyKey,
  );
  AgentActionRemoteAuditData copyWithCompanion(
    AgentActionRemoteAuditTableCompanion data,
  ) {
    return AgentActionRemoteAuditData(
      id: data.id.present ? data.id.value : this.id,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      rpcMethod: data.rpcMethod.present ? data.rpcMethod.value : this.rpcMethod,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      traceId: data.traceId.present ? data.traceId.value : this.traceId,
      requestedBy: data.requestedBy.present
          ? data.requestedBy.value
          : this.requestedBy,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      reasonCode: data.reasonCode.present
          ? data.reasonCode.value
          : this.reasonCode,
      rpcErrorCode: data.rpcErrorCode.present
          ? data.rpcErrorCode.value
          : this.rpcErrorCode,
      credentialPresent: data.credentialPresent.present
          ? data.credentialPresent.value
          : this.credentialPresent,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      tokenJti: data.tokenJti.present ? data.tokenJti.value : this.tokenJti,
      runtimeInstanceId: data.runtimeInstanceId.present
          ? data.runtimeInstanceId.value
          : this.runtimeInstanceId,
      runtimeSessionId: data.runtimeSessionId.present
          ? data.runtimeSessionId.value
          : this.runtimeSessionId,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionRemoteAuditData(')
          ..write('id: $id, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('rpcMethod: $rpcMethod, ')
          ..write('actionId: $actionId, ')
          ..write('executionId: $executionId, ')
          ..write('traceId: $traceId, ')
          ..write('requestedBy: $requestedBy, ')
          ..write('outcome: $outcome, ')
          ..write('reasonCode: $reasonCode, ')
          ..write('rpcErrorCode: $rpcErrorCode, ')
          ..write('credentialPresent: $credentialPresent, ')
          ..write('clientId: $clientId, ')
          ..write('tokenJti: $tokenJti, ')
          ..write('runtimeInstanceId: $runtimeInstanceId, ')
          ..write('runtimeSessionId: $runtimeSessionId, ')
          ..write('idempotencyKey: $idempotencyKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    occurredAt,
    rpcMethod,
    actionId,
    executionId,
    traceId,
    requestedBy,
    outcome,
    reasonCode,
    rpcErrorCode,
    credentialPresent,
    clientId,
    tokenJti,
    runtimeInstanceId,
    runtimeSessionId,
    idempotencyKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentActionRemoteAuditData &&
          other.id == this.id &&
          other.occurredAt == this.occurredAt &&
          other.rpcMethod == this.rpcMethod &&
          other.actionId == this.actionId &&
          other.executionId == this.executionId &&
          other.traceId == this.traceId &&
          other.requestedBy == this.requestedBy &&
          other.outcome == this.outcome &&
          other.reasonCode == this.reasonCode &&
          other.rpcErrorCode == this.rpcErrorCode &&
          other.credentialPresent == this.credentialPresent &&
          other.clientId == this.clientId &&
          other.tokenJti == this.tokenJti &&
          other.runtimeInstanceId == this.runtimeInstanceId &&
          other.runtimeSessionId == this.runtimeSessionId &&
          other.idempotencyKey == this.idempotencyKey);
}

class AgentActionRemoteAuditTableCompanion
    extends UpdateCompanion<AgentActionRemoteAuditData> {
  final Value<String> id;
  final Value<DateTime> occurredAt;
  final Value<String> rpcMethod;
  final Value<String?> actionId;
  final Value<String?> executionId;
  final Value<String?> traceId;
  final Value<String?> requestedBy;
  final Value<String> outcome;
  final Value<String?> reasonCode;
  final Value<int?> rpcErrorCode;
  final Value<bool> credentialPresent;
  final Value<String?> clientId;
  final Value<String?> tokenJti;
  final Value<String?> runtimeInstanceId;
  final Value<String?> runtimeSessionId;
  final Value<String?> idempotencyKey;
  final Value<int> rowid;
  const AgentActionRemoteAuditTableCompanion({
    this.id = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.rpcMethod = const Value.absent(),
    this.actionId = const Value.absent(),
    this.executionId = const Value.absent(),
    this.traceId = const Value.absent(),
    this.requestedBy = const Value.absent(),
    this.outcome = const Value.absent(),
    this.reasonCode = const Value.absent(),
    this.rpcErrorCode = const Value.absent(),
    this.credentialPresent = const Value.absent(),
    this.clientId = const Value.absent(),
    this.tokenJti = const Value.absent(),
    this.runtimeInstanceId = const Value.absent(),
    this.runtimeSessionId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentActionRemoteAuditTableCompanion.insert({
    required String id,
    required DateTime occurredAt,
    required String rpcMethod,
    this.actionId = const Value.absent(),
    this.executionId = const Value.absent(),
    this.traceId = const Value.absent(),
    this.requestedBy = const Value.absent(),
    required String outcome,
    this.reasonCode = const Value.absent(),
    this.rpcErrorCode = const Value.absent(),
    this.credentialPresent = const Value.absent(),
    this.clientId = const Value.absent(),
    this.tokenJti = const Value.absent(),
    this.runtimeInstanceId = const Value.absent(),
    this.runtimeSessionId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       occurredAt = Value(occurredAt),
       rpcMethod = Value(rpcMethod),
       outcome = Value(outcome);
  static Insertable<AgentActionRemoteAuditData> custom({
    Expression<String>? id,
    Expression<DateTime>? occurredAt,
    Expression<String>? rpcMethod,
    Expression<String>? actionId,
    Expression<String>? executionId,
    Expression<String>? traceId,
    Expression<String>? requestedBy,
    Expression<String>? outcome,
    Expression<String>? reasonCode,
    Expression<int>? rpcErrorCode,
    Expression<bool>? credentialPresent,
    Expression<String>? clientId,
    Expression<String>? tokenJti,
    Expression<String>? runtimeInstanceId,
    Expression<String>? runtimeSessionId,
    Expression<String>? idempotencyKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (rpcMethod != null) 'rpc_method': rpcMethod,
      if (actionId != null) 'action_id': actionId,
      if (executionId != null) 'execution_id': executionId,
      if (traceId != null) 'trace_id': traceId,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (outcome != null) 'outcome': outcome,
      if (reasonCode != null) 'reason_code': reasonCode,
      if (rpcErrorCode != null) 'rpc_error_code': rpcErrorCode,
      if (credentialPresent != null) 'credential_present': credentialPresent,
      if (clientId != null) 'client_id': clientId,
      if (tokenJti != null) 'token_jti': tokenJti,
      if (runtimeInstanceId != null) 'runtime_instance_id': runtimeInstanceId,
      if (runtimeSessionId != null) 'runtime_session_id': runtimeSessionId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentActionRemoteAuditTableCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? occurredAt,
    Value<String>? rpcMethod,
    Value<String?>? actionId,
    Value<String?>? executionId,
    Value<String?>? traceId,
    Value<String?>? requestedBy,
    Value<String>? outcome,
    Value<String?>? reasonCode,
    Value<int?>? rpcErrorCode,
    Value<bool>? credentialPresent,
    Value<String?>? clientId,
    Value<String?>? tokenJti,
    Value<String?>? runtimeInstanceId,
    Value<String?>? runtimeSessionId,
    Value<String?>? idempotencyKey,
    Value<int>? rowid,
  }) {
    return AgentActionRemoteAuditTableCompanion(
      id: id ?? this.id,
      occurredAt: occurredAt ?? this.occurredAt,
      rpcMethod: rpcMethod ?? this.rpcMethod,
      actionId: actionId ?? this.actionId,
      executionId: executionId ?? this.executionId,
      traceId: traceId ?? this.traceId,
      requestedBy: requestedBy ?? this.requestedBy,
      outcome: outcome ?? this.outcome,
      reasonCode: reasonCode ?? this.reasonCode,
      rpcErrorCode: rpcErrorCode ?? this.rpcErrorCode,
      credentialPresent: credentialPresent ?? this.credentialPresent,
      clientId: clientId ?? this.clientId,
      tokenJti: tokenJti ?? this.tokenJti,
      runtimeInstanceId: runtimeInstanceId ?? this.runtimeInstanceId,
      runtimeSessionId: runtimeSessionId ?? this.runtimeSessionId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (rpcMethod.present) {
      map['rpc_method'] = Variable<String>(rpcMethod.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (traceId.present) {
      map['trace_id'] = Variable<String>(traceId.value);
    }
    if (requestedBy.present) {
      map['requested_by'] = Variable<String>(requestedBy.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (reasonCode.present) {
      map['reason_code'] = Variable<String>(reasonCode.value);
    }
    if (rpcErrorCode.present) {
      map['rpc_error_code'] = Variable<int>(rpcErrorCode.value);
    }
    if (credentialPresent.present) {
      map['credential_present'] = Variable<bool>(credentialPresent.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (tokenJti.present) {
      map['token_jti'] = Variable<String>(tokenJti.value);
    }
    if (runtimeInstanceId.present) {
      map['runtime_instance_id'] = Variable<String>(runtimeInstanceId.value);
    }
    if (runtimeSessionId.present) {
      map['runtime_session_id'] = Variable<String>(runtimeSessionId.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionRemoteAuditTableCompanion(')
          ..write('id: $id, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('rpcMethod: $rpcMethod, ')
          ..write('actionId: $actionId, ')
          ..write('executionId: $executionId, ')
          ..write('traceId: $traceId, ')
          ..write('requestedBy: $requestedBy, ')
          ..write('outcome: $outcome, ')
          ..write('reasonCode: $reasonCode, ')
          ..write('rpcErrorCode: $rpcErrorCode, ')
          ..write('credentialPresent: $credentialPresent, ')
          ..write('clientId: $clientId, ')
          ..write('tokenJti: $tokenJti, ')
          ..write('runtimeInstanceId: $runtimeInstanceId, ')
          ..write('runtimeSessionId: $runtimeSessionId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentActionCapturedOutputChunkTableTable
    extends AgentActionCapturedOutputChunkTable
    with
        TableInfo<
          $AgentActionCapturedOutputChunkTableTable,
          AgentActionCapturedOutputChunkData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentActionCapturedOutputChunkTableTable(
    this.attachedDatabase, [
    this._alias,
  ]);
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
  static const VerificationMeta _streamMeta = const VerificationMeta('stream');
  @override
  late final GeneratedColumn<String> stream = GeneratedColumn<String>(
    'stream',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chunkIndexMeta = const VerificationMeta(
    'chunkIndex',
  );
  @override
  late final GeneratedColumn<int> chunkIndex = GeneratedColumn<int>(
    'chunk_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _utf8OffsetMeta = const VerificationMeta(
    'utf8Offset',
  );
  @override
  late final GeneratedColumn<int> utf8Offset = GeneratedColumn<int>(
    'utf8_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    executionId,
    stream,
    chunkIndex,
    utf8Offset,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_action_captured_output_chunk_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentActionCapturedOutputChunkData> instance, {
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
    if (data.containsKey('stream')) {
      context.handle(
        _streamMeta,
        stream.isAcceptableOrUnknown(data['stream']!, _streamMeta),
      );
    } else if (isInserting) {
      context.missing(_streamMeta);
    }
    if (data.containsKey('chunk_index')) {
      context.handle(
        _chunkIndexMeta,
        chunkIndex.isAcceptableOrUnknown(data['chunk_index']!, _chunkIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_chunkIndexMeta);
    }
    if (data.containsKey('utf8_offset')) {
      context.handle(
        _utf8OffsetMeta,
        utf8Offset.isAcceptableOrUnknown(data['utf8_offset']!, _utf8OffsetMeta),
      );
    } else if (isInserting) {
      context.missing(_utf8OffsetMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {executionId, stream, chunkIndex};
  @override
  AgentActionCapturedOutputChunkData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentActionCapturedOutputChunkData(
      executionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_id'],
      )!,
      stream: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream'],
      )!,
      chunkIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_index'],
      )!,
      utf8Offset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}utf8_offset'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $AgentActionCapturedOutputChunkTableTable createAlias(String alias) {
    return $AgentActionCapturedOutputChunkTableTable(attachedDatabase, alias);
  }
}

class AgentActionCapturedOutputChunkData extends DataClass
    implements Insertable<AgentActionCapturedOutputChunkData> {
  final String executionId;
  final String stream;
  final int chunkIndex;
  final int utf8Offset;
  final String payload;
  const AgentActionCapturedOutputChunkData({
    required this.executionId,
    required this.stream,
    required this.chunkIndex,
    required this.utf8Offset,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['execution_id'] = Variable<String>(executionId);
    map['stream'] = Variable<String>(stream);
    map['chunk_index'] = Variable<int>(chunkIndex);
    map['utf8_offset'] = Variable<int>(utf8Offset);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  AgentActionCapturedOutputChunkTableCompanion toCompanion(bool nullToAbsent) {
    return AgentActionCapturedOutputChunkTableCompanion(
      executionId: Value(executionId),
      stream: Value(stream),
      chunkIndex: Value(chunkIndex),
      utf8Offset: Value(utf8Offset),
      payload: Value(payload),
    );
  }

  factory AgentActionCapturedOutputChunkData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentActionCapturedOutputChunkData(
      executionId: serializer.fromJson<String>(json['executionId']),
      stream: serializer.fromJson<String>(json['stream']),
      chunkIndex: serializer.fromJson<int>(json['chunkIndex']),
      utf8Offset: serializer.fromJson<int>(json['utf8Offset']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'executionId': serializer.toJson<String>(executionId),
      'stream': serializer.toJson<String>(stream),
      'chunkIndex': serializer.toJson<int>(chunkIndex),
      'utf8Offset': serializer.toJson<int>(utf8Offset),
      'payload': serializer.toJson<String>(payload),
    };
  }

  AgentActionCapturedOutputChunkData copyWith({
    String? executionId,
    String? stream,
    int? chunkIndex,
    int? utf8Offset,
    String? payload,
  }) => AgentActionCapturedOutputChunkData(
    executionId: executionId ?? this.executionId,
    stream: stream ?? this.stream,
    chunkIndex: chunkIndex ?? this.chunkIndex,
    utf8Offset: utf8Offset ?? this.utf8Offset,
    payload: payload ?? this.payload,
  );
  AgentActionCapturedOutputChunkData copyWithCompanion(
    AgentActionCapturedOutputChunkTableCompanion data,
  ) {
    return AgentActionCapturedOutputChunkData(
      executionId: data.executionId.present
          ? data.executionId.value
          : this.executionId,
      stream: data.stream.present ? data.stream.value : this.stream,
      chunkIndex: data.chunkIndex.present
          ? data.chunkIndex.value
          : this.chunkIndex,
      utf8Offset: data.utf8Offset.present
          ? data.utf8Offset.value
          : this.utf8Offset,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionCapturedOutputChunkData(')
          ..write('executionId: $executionId, ')
          ..write('stream: $stream, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('utf8Offset: $utf8Offset, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(executionId, stream, chunkIndex, utf8Offset, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentActionCapturedOutputChunkData &&
          other.executionId == this.executionId &&
          other.stream == this.stream &&
          other.chunkIndex == this.chunkIndex &&
          other.utf8Offset == this.utf8Offset &&
          other.payload == this.payload);
}

class AgentActionCapturedOutputChunkTableCompanion
    extends UpdateCompanion<AgentActionCapturedOutputChunkData> {
  final Value<String> executionId;
  final Value<String> stream;
  final Value<int> chunkIndex;
  final Value<int> utf8Offset;
  final Value<String> payload;
  final Value<int> rowid;
  const AgentActionCapturedOutputChunkTableCompanion({
    this.executionId = const Value.absent(),
    this.stream = const Value.absent(),
    this.chunkIndex = const Value.absent(),
    this.utf8Offset = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentActionCapturedOutputChunkTableCompanion.insert({
    required String executionId,
    required String stream,
    required int chunkIndex,
    required int utf8Offset,
    required String payload,
    this.rowid = const Value.absent(),
  }) : executionId = Value(executionId),
       stream = Value(stream),
       chunkIndex = Value(chunkIndex),
       utf8Offset = Value(utf8Offset),
       payload = Value(payload);
  static Insertable<AgentActionCapturedOutputChunkData> custom({
    Expression<String>? executionId,
    Expression<String>? stream,
    Expression<int>? chunkIndex,
    Expression<int>? utf8Offset,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (executionId != null) 'execution_id': executionId,
      if (stream != null) 'stream': stream,
      if (chunkIndex != null) 'chunk_index': chunkIndex,
      if (utf8Offset != null) 'utf8_offset': utf8Offset,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentActionCapturedOutputChunkTableCompanion copyWith({
    Value<String>? executionId,
    Value<String>? stream,
    Value<int>? chunkIndex,
    Value<int>? utf8Offset,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return AgentActionCapturedOutputChunkTableCompanion(
      executionId: executionId ?? this.executionId,
      stream: stream ?? this.stream,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      utf8Offset: utf8Offset ?? this.utf8Offset,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (executionId.present) {
      map['execution_id'] = Variable<String>(executionId.value);
    }
    if (stream.present) {
      map['stream'] = Variable<String>(stream.value);
    }
    if (chunkIndex.present) {
      map['chunk_index'] = Variable<int>(chunkIndex.value);
    }
    if (utf8Offset.present) {
      map['utf8_offset'] = Variable<int>(utf8Offset.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentActionCapturedOutputChunkTableCompanion(')
          ..write('executionId: $executionId, ')
          ..write('stream: $stream, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('utf8Offset: $utf8Offset, ')
          ..write('payload: $payload, ')
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
  late final $AgentActionDefinitionTableTable agentActionDefinitionTable =
      $AgentActionDefinitionTableTable(this);
  late final $AgentActionTriggerTableTable agentActionTriggerTable =
      $AgentActionTriggerTableTable(this);
  late final $AgentActionExecutionTableTable agentActionExecutionTable =
      $AgentActionExecutionTableTable(this);
  late final $RpcIdempotencyCacheTableTable rpcIdempotencyCacheTable =
      $RpcIdempotencyCacheTableTable(this);
  late final $AgentActionRemoteAuditTableTable agentActionRemoteAuditTable =
      $AgentActionRemoteAuditTableTable(this);
  late final $AgentActionCapturedOutputChunkTableTable
  agentActionCapturedOutputChunkTable =
      $AgentActionCapturedOutputChunkTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    configTable,
    clientTokenCacheTable,
    agentActionDefinitionTable,
    agentActionTriggerTable,
    agentActionExecutionTable,
    rpcIdempotencyCacheTable,
    agentActionRemoteAuditTable,
    agentActionCapturedOutputChunkTable,
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
      Value<String> nome,
      Value<String> nomeFantasia,
      Value<String> cnaeCnpjCpf,
      Value<String> telefone,
      Value<String> celular,
      Value<String> email,
      Value<String> endereco,
      Value<String> numeroEndereco,
      Value<String> bairro,
      Value<String> cep,
      Value<String> nomeMunicipio,
      Value<String> ufMunicipio,
      Value<String> observacao,
      Value<int?> hubProfileVersion,
      Value<String?> hubProfileUpdatedAt,
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
      Value<String> nome,
      Value<String> nomeFantasia,
      Value<String> cnaeCnpjCpf,
      Value<String> telefone,
      Value<String> celular,
      Value<String> email,
      Value<String> endereco,
      Value<String> numeroEndereco,
      Value<String> bairro,
      Value<String> cep,
      Value<String> nomeMunicipio,
      Value<String> ufMunicipio,
      Value<String> observacao,
      Value<int?> hubProfileVersion,
      Value<String?> hubProfileUpdatedAt,
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

  ColumnFilters<String> get nome => $composableBuilder(
    column: $table.nome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nomeFantasia => $composableBuilder(
    column: $table.nomeFantasia,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cnaeCnpjCpf => $composableBuilder(
    column: $table.cnaeCnpjCpf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get telefone => $composableBuilder(
    column: $table.telefone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get celular => $composableBuilder(
    column: $table.celular,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endereco => $composableBuilder(
    column: $table.endereco,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get numeroEndereco => $composableBuilder(
    column: $table.numeroEndereco,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bairro => $composableBuilder(
    column: $table.bairro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cep => $composableBuilder(
    column: $table.cep,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nomeMunicipio => $composableBuilder(
    column: $table.nomeMunicipio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ufMunicipio => $composableBuilder(
    column: $table.ufMunicipio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observacao => $composableBuilder(
    column: $table.observacao,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hubProfileVersion => $composableBuilder(
    column: $table.hubProfileVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hubProfileUpdatedAt => $composableBuilder(
    column: $table.hubProfileUpdatedAt,
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

  ColumnOrderings<String> get nome => $composableBuilder(
    column: $table.nome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nomeFantasia => $composableBuilder(
    column: $table.nomeFantasia,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cnaeCnpjCpf => $composableBuilder(
    column: $table.cnaeCnpjCpf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get telefone => $composableBuilder(
    column: $table.telefone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get celular => $composableBuilder(
    column: $table.celular,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endereco => $composableBuilder(
    column: $table.endereco,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get numeroEndereco => $composableBuilder(
    column: $table.numeroEndereco,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bairro => $composableBuilder(
    column: $table.bairro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cep => $composableBuilder(
    column: $table.cep,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nomeMunicipio => $composableBuilder(
    column: $table.nomeMunicipio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ufMunicipio => $composableBuilder(
    column: $table.ufMunicipio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observacao => $composableBuilder(
    column: $table.observacao,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hubProfileVersion => $composableBuilder(
    column: $table.hubProfileVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hubProfileUpdatedAt => $composableBuilder(
    column: $table.hubProfileUpdatedAt,
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

  GeneratedColumn<String> get nome =>
      $composableBuilder(column: $table.nome, builder: (column) => column);

  GeneratedColumn<String> get nomeFantasia => $composableBuilder(
    column: $table.nomeFantasia,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cnaeCnpjCpf => $composableBuilder(
    column: $table.cnaeCnpjCpf,
    builder: (column) => column,
  );

  GeneratedColumn<String> get telefone =>
      $composableBuilder(column: $table.telefone, builder: (column) => column);

  GeneratedColumn<String> get celular =>
      $composableBuilder(column: $table.celular, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get endereco =>
      $composableBuilder(column: $table.endereco, builder: (column) => column);

  GeneratedColumn<String> get numeroEndereco => $composableBuilder(
    column: $table.numeroEndereco,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bairro =>
      $composableBuilder(column: $table.bairro, builder: (column) => column);

  GeneratedColumn<String> get cep =>
      $composableBuilder(column: $table.cep, builder: (column) => column);

  GeneratedColumn<String> get nomeMunicipio => $composableBuilder(
    column: $table.nomeMunicipio,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ufMunicipio => $composableBuilder(
    column: $table.ufMunicipio,
    builder: (column) => column,
  );

  GeneratedColumn<String> get observacao => $composableBuilder(
    column: $table.observacao,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hubProfileVersion => $composableBuilder(
    column: $table.hubProfileVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hubProfileUpdatedAt => $composableBuilder(
    column: $table.hubProfileUpdatedAt,
    builder: (column) => column,
  );

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
                Value<String> nome = const Value.absent(),
                Value<String> nomeFantasia = const Value.absent(),
                Value<String> cnaeCnpjCpf = const Value.absent(),
                Value<String> telefone = const Value.absent(),
                Value<String> celular = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String> endereco = const Value.absent(),
                Value<String> numeroEndereco = const Value.absent(),
                Value<String> bairro = const Value.absent(),
                Value<String> cep = const Value.absent(),
                Value<String> nomeMunicipio = const Value.absent(),
                Value<String> ufMunicipio = const Value.absent(),
                Value<String> observacao = const Value.absent(),
                Value<int?> hubProfileVersion = const Value.absent(),
                Value<String?> hubProfileUpdatedAt = const Value.absent(),
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
                nome: nome,
                nomeFantasia: nomeFantasia,
                cnaeCnpjCpf: cnaeCnpjCpf,
                telefone: telefone,
                celular: celular,
                email: email,
                endereco: endereco,
                numeroEndereco: numeroEndereco,
                bairro: bairro,
                cep: cep,
                nomeMunicipio: nomeMunicipio,
                ufMunicipio: ufMunicipio,
                observacao: observacao,
                hubProfileVersion: hubProfileVersion,
                hubProfileUpdatedAt: hubProfileUpdatedAt,
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
                Value<String> nome = const Value.absent(),
                Value<String> nomeFantasia = const Value.absent(),
                Value<String> cnaeCnpjCpf = const Value.absent(),
                Value<String> telefone = const Value.absent(),
                Value<String> celular = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String> endereco = const Value.absent(),
                Value<String> numeroEndereco = const Value.absent(),
                Value<String> bairro = const Value.absent(),
                Value<String> cep = const Value.absent(),
                Value<String> nomeMunicipio = const Value.absent(),
                Value<String> ufMunicipio = const Value.absent(),
                Value<String> observacao = const Value.absent(),
                Value<int?> hubProfileVersion = const Value.absent(),
                Value<String?> hubProfileUpdatedAt = const Value.absent(),
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
                nome: nome,
                nomeFantasia: nomeFantasia,
                cnaeCnpjCpf: cnaeCnpjCpf,
                telefone: telefone,
                celular: celular,
                email: email,
                endereco: endereco,
                numeroEndereco: numeroEndereco,
                bairro: bairro,
                cep: cep,
                nomeMunicipio: nomeMunicipio,
                ufMunicipio: ufMunicipio,
                observacao: observacao,
                hubProfileVersion: hubProfileVersion,
                hubProfileUpdatedAt: hubProfileUpdatedAt,
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
      Value<String> name,
      Value<bool> isRevoked,
      Value<int> version,
      Value<String?> agentId,
      Value<String?> tokenValue,
      required DateTime createdAt,
      Value<DateTime?> updatedAt,
      Value<String> payloadJson,
      Value<bool> allTables,
      Value<bool> allViews,
      Value<bool> allPermissions,
      Value<String> globalPermissionsJson,
      Value<String> rulesJson,
      required DateTime syncedAt,
      Value<String> tokenHash,
      Value<int> rowid,
    });
typedef $$ClientTokenCacheTableTableUpdateCompanionBuilder =
    ClientTokenCacheTableCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<String> name,
      Value<bool> isRevoked,
      Value<int> version,
      Value<String?> agentId,
      Value<String?> tokenValue,
      Value<DateTime> createdAt,
      Value<DateTime?> updatedAt,
      Value<String> payloadJson,
      Value<bool> allTables,
      Value<bool> allViews,
      Value<bool> allPermissions,
      Value<String> globalPermissionsJson,
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRevoked => $composableBuilder(
    column: $table.isRevoked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenValue => $composableBuilder(
    column: $table.tokenValue,
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

  ColumnFilters<String> get globalPermissionsJson => $composableBuilder(
    column: $table.globalPermissionsJson,
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRevoked => $composableBuilder(
    column: $table.isRevoked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenValue => $composableBuilder(
    column: $table.tokenValue,
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

  ColumnOrderings<String> get globalPermissionsJson => $composableBuilder(
    column: $table.globalPermissionsJson,
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

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isRevoked =>
      $composableBuilder(column: $table.isRevoked, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<String> get tokenValue => $composableBuilder(
    column: $table.tokenValue,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

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

  GeneratedColumn<String> get globalPermissionsJson => $composableBuilder(
    column: $table.globalPermissionsJson,
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
                Value<String> name = const Value.absent(),
                Value<bool> isRevoked = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> agentId = const Value.absent(),
                Value<String?> tokenValue = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<bool> allTables = const Value.absent(),
                Value<bool> allViews = const Value.absent(),
                Value<bool> allPermissions = const Value.absent(),
                Value<String> globalPermissionsJson = const Value.absent(),
                Value<String> rulesJson = const Value.absent(),
                Value<DateTime> syncedAt = const Value.absent(),
                Value<String> tokenHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientTokenCacheTableCompanion(
                id: id,
                clientId: clientId,
                name: name,
                isRevoked: isRevoked,
                version: version,
                agentId: agentId,
                tokenValue: tokenValue,
                createdAt: createdAt,
                updatedAt: updatedAt,
                payloadJson: payloadJson,
                allTables: allTables,
                allViews: allViews,
                allPermissions: allPermissions,
                globalPermissionsJson: globalPermissionsJson,
                rulesJson: rulesJson,
                syncedAt: syncedAt,
                tokenHash: tokenHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                Value<String> name = const Value.absent(),
                Value<bool> isRevoked = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> agentId = const Value.absent(),
                Value<String?> tokenValue = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<bool> allTables = const Value.absent(),
                Value<bool> allViews = const Value.absent(),
                Value<bool> allPermissions = const Value.absent(),
                Value<String> globalPermissionsJson = const Value.absent(),
                Value<String> rulesJson = const Value.absent(),
                required DateTime syncedAt,
                Value<String> tokenHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientTokenCacheTableCompanion.insert(
                id: id,
                clientId: clientId,
                name: name,
                isRevoked: isRevoked,
                version: version,
                agentId: agentId,
                tokenValue: tokenValue,
                createdAt: createdAt,
                updatedAt: updatedAt,
                payloadJson: payloadJson,
                allTables: allTables,
                allViews: allViews,
                allPermissions: allPermissions,
                globalPermissionsJson: globalPermissionsJson,
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
typedef $$AgentActionDefinitionTableTableCreateCompanionBuilder =
    AgentActionDefinitionTableCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      required String type,
      required String state,
      required String configJson,
      required String policiesJson,
      Value<int> definitionVersion,
      Value<String?> definitionSnapshotHash,
      Value<String?> lastPreflightSnapshotHash,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AgentActionDefinitionTableTableUpdateCompanionBuilder =
    AgentActionDefinitionTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<String> type,
      Value<String> state,
      Value<String> configJson,
      Value<String> policiesJson,
      Value<int> definitionVersion,
      Value<String?> definitionSnapshotHash,
      Value<String?> lastPreflightSnapshotHash,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AgentActionDefinitionTableTableFilterComposer
    extends Composer<_$AppDatabase, $AgentActionDefinitionTableTable> {
  $$AgentActionDefinitionTableTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get policiesJson => $composableBuilder(
    column: $table.policiesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get definitionSnapshotHash => $composableBuilder(
    column: $table.definitionSnapshotHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPreflightSnapshotHash => $composableBuilder(
    column: $table.lastPreflightSnapshotHash,
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

class $$AgentActionDefinitionTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentActionDefinitionTableTable> {
  $$AgentActionDefinitionTableTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get policiesJson => $composableBuilder(
    column: $table.policiesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get definitionSnapshotHash => $composableBuilder(
    column: $table.definitionSnapshotHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPreflightSnapshotHash => $composableBuilder(
    column: $table.lastPreflightSnapshotHash,
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

class $$AgentActionDefinitionTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentActionDefinitionTableTable> {
  $$AgentActionDefinitionTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get policiesJson => $composableBuilder(
    column: $table.policiesJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get definitionSnapshotHash => $composableBuilder(
    column: $table.definitionSnapshotHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastPreflightSnapshotHash => $composableBuilder(
    column: $table.lastPreflightSnapshotHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AgentActionDefinitionTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentActionDefinitionTableTable,
          AgentActionDefinitionData,
          $$AgentActionDefinitionTableTableFilterComposer,
          $$AgentActionDefinitionTableTableOrderingComposer,
          $$AgentActionDefinitionTableTableAnnotationComposer,
          $$AgentActionDefinitionTableTableCreateCompanionBuilder,
          $$AgentActionDefinitionTableTableUpdateCompanionBuilder,
          (
            AgentActionDefinitionData,
            BaseReferences<
              _$AppDatabase,
              $AgentActionDefinitionTableTable,
              AgentActionDefinitionData
            >,
          ),
          AgentActionDefinitionData,
          PrefetchHooks Function()
        > {
  $$AgentActionDefinitionTableTableTableManager(
    _$AppDatabase db,
    $AgentActionDefinitionTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentActionDefinitionTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AgentActionDefinitionTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AgentActionDefinitionTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<String> policiesJson = const Value.absent(),
                Value<int> definitionVersion = const Value.absent(),
                Value<String?> definitionSnapshotHash = const Value.absent(),
                Value<String?> lastPreflightSnapshotHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentActionDefinitionTableCompanion(
                id: id,
                name: name,
                description: description,
                type: type,
                state: state,
                configJson: configJson,
                policiesJson: policiesJson,
                definitionVersion: definitionVersion,
                definitionSnapshotHash: definitionSnapshotHash,
                lastPreflightSnapshotHash: lastPreflightSnapshotHash,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                required String type,
                required String state,
                required String configJson,
                required String policiesJson,
                Value<int> definitionVersion = const Value.absent(),
                Value<String?> definitionSnapshotHash = const Value.absent(),
                Value<String?> lastPreflightSnapshotHash = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AgentActionDefinitionTableCompanion.insert(
                id: id,
                name: name,
                description: description,
                type: type,
                state: state,
                configJson: configJson,
                policiesJson: policiesJson,
                definitionVersion: definitionVersion,
                definitionSnapshotHash: definitionSnapshotHash,
                lastPreflightSnapshotHash: lastPreflightSnapshotHash,
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

typedef $$AgentActionDefinitionTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentActionDefinitionTableTable,
      AgentActionDefinitionData,
      $$AgentActionDefinitionTableTableFilterComposer,
      $$AgentActionDefinitionTableTableOrderingComposer,
      $$AgentActionDefinitionTableTableAnnotationComposer,
      $$AgentActionDefinitionTableTableCreateCompanionBuilder,
      $$AgentActionDefinitionTableTableUpdateCompanionBuilder,
      (
        AgentActionDefinitionData,
        BaseReferences<
          _$AppDatabase,
          $AgentActionDefinitionTableTable,
          AgentActionDefinitionData
        >,
      ),
      AgentActionDefinitionData,
      PrefetchHooks Function()
    >;
typedef $$AgentActionTriggerTableTableCreateCompanionBuilder =
    AgentActionTriggerTableCompanion Function({
      required String id,
      required String actionId,
      required String type,
      Value<String?> name,
      Value<bool> isEnabled,
      required String scheduleJson,
      Value<DateTime?> lastScheduledAt,
      Value<DateTime?> lastRunAt,
      Value<DateTime?> nextRunAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AgentActionTriggerTableTableUpdateCompanionBuilder =
    AgentActionTriggerTableCompanion Function({
      Value<String> id,
      Value<String> actionId,
      Value<String> type,
      Value<String?> name,
      Value<bool> isEnabled,
      Value<String> scheduleJson,
      Value<DateTime?> lastScheduledAt,
      Value<DateTime?> lastRunAt,
      Value<DateTime?> nextRunAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AgentActionTriggerTableTableFilterComposer
    extends Composer<_$AppDatabase, $AgentActionTriggerTableTable> {
  $$AgentActionTriggerTableTableFilterComposer({
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

  ColumnFilters<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastScheduledAt => $composableBuilder(
    column: $table.lastScheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastRunAt => $composableBuilder(
    column: $table.lastRunAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRunAt => $composableBuilder(
    column: $table.nextRunAt,
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

class $$AgentActionTriggerTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentActionTriggerTableTable> {
  $$AgentActionTriggerTableTableOrderingComposer({
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

  ColumnOrderings<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastScheduledAt => $composableBuilder(
    column: $table.lastScheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastRunAt => $composableBuilder(
    column: $table.lastRunAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRunAt => $composableBuilder(
    column: $table.nextRunAt,
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

class $$AgentActionTriggerTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentActionTriggerTableTable> {
  $$AgentActionTriggerTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actionId =>
      $composableBuilder(column: $table.actionId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastScheduledAt => $composableBuilder(
    column: $table.lastScheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastRunAt =>
      $composableBuilder(column: $table.lastRunAt, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRunAt =>
      $composableBuilder(column: $table.nextRunAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AgentActionTriggerTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentActionTriggerTableTable,
          AgentActionTriggerData,
          $$AgentActionTriggerTableTableFilterComposer,
          $$AgentActionTriggerTableTableOrderingComposer,
          $$AgentActionTriggerTableTableAnnotationComposer,
          $$AgentActionTriggerTableTableCreateCompanionBuilder,
          $$AgentActionTriggerTableTableUpdateCompanionBuilder,
          (
            AgentActionTriggerData,
            BaseReferences<
              _$AppDatabase,
              $AgentActionTriggerTableTable,
              AgentActionTriggerData
            >,
          ),
          AgentActionTriggerData,
          PrefetchHooks Function()
        > {
  $$AgentActionTriggerTableTableTableManager(
    _$AppDatabase db,
    $AgentActionTriggerTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentActionTriggerTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AgentActionTriggerTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AgentActionTriggerTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> actionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<String> scheduleJson = const Value.absent(),
                Value<DateTime?> lastScheduledAt = const Value.absent(),
                Value<DateTime?> lastRunAt = const Value.absent(),
                Value<DateTime?> nextRunAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentActionTriggerTableCompanion(
                id: id,
                actionId: actionId,
                type: type,
                name: name,
                isEnabled: isEnabled,
                scheduleJson: scheduleJson,
                lastScheduledAt: lastScheduledAt,
                lastRunAt: lastRunAt,
                nextRunAt: nextRunAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String actionId,
                required String type,
                Value<String?> name = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                required String scheduleJson,
                Value<DateTime?> lastScheduledAt = const Value.absent(),
                Value<DateTime?> lastRunAt = const Value.absent(),
                Value<DateTime?> nextRunAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AgentActionTriggerTableCompanion.insert(
                id: id,
                actionId: actionId,
                type: type,
                name: name,
                isEnabled: isEnabled,
                scheduleJson: scheduleJson,
                lastScheduledAt: lastScheduledAt,
                lastRunAt: lastRunAt,
                nextRunAt: nextRunAt,
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

typedef $$AgentActionTriggerTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentActionTriggerTableTable,
      AgentActionTriggerData,
      $$AgentActionTriggerTableTableFilterComposer,
      $$AgentActionTriggerTableTableOrderingComposer,
      $$AgentActionTriggerTableTableAnnotationComposer,
      $$AgentActionTriggerTableTableCreateCompanionBuilder,
      $$AgentActionTriggerTableTableUpdateCompanionBuilder,
      (
        AgentActionTriggerData,
        BaseReferences<
          _$AppDatabase,
          $AgentActionTriggerTableTable,
          AgentActionTriggerData
        >,
      ),
      AgentActionTriggerData,
      PrefetchHooks Function()
    >;
typedef $$AgentActionExecutionTableTableCreateCompanionBuilder =
    AgentActionExecutionTableCompanion Function({
      required String id,
      required String actionId,
      required String actionType,
      required String status,
      required DateTime requestedAt,
      required String source,
      Value<String?> idempotencyKey,
      Value<String?> requestedBy,
      Value<String?> traceId,
      Value<String?> runtimeInstanceId,
      Value<String?> runtimeSessionId,
      Value<String?> triggerId,
      Value<String?> triggerType,
      Value<DateTime?> scheduledAt,
      Value<DateTime?> triggeredAt,
      Value<DateTime?> queueStartedAt,
      Value<DateTime?> processStartedAt,
      Value<DateTime?> finishedAt,
      Value<DateTime?> timeoutAt,
      Value<int?> pid,
      Value<int?> exitCode,
      Value<String?> processExecutable,
      Value<int?> processArgumentCount,
      Value<String?> processCommandPreview,
      Value<String?> stdoutText,
      Value<String?> stderrText,
      Value<bool> stdoutTruncated,
      Value<bool> stderrTruncated,
      Value<bool> stdoutStoredInChunks,
      Value<bool> stderrStoredInChunks,
      Value<String?> definitionSnapshotHash,
      Value<String?> contextHash,
      Value<bool> redactionApplied,
      Value<String?> failureCode,
      Value<String?> failurePhase,
      Value<String?> failureMessage,
      Value<int> rowid,
    });
typedef $$AgentActionExecutionTableTableUpdateCompanionBuilder =
    AgentActionExecutionTableCompanion Function({
      Value<String> id,
      Value<String> actionId,
      Value<String> actionType,
      Value<String> status,
      Value<DateTime> requestedAt,
      Value<String> source,
      Value<String?> idempotencyKey,
      Value<String?> requestedBy,
      Value<String?> traceId,
      Value<String?> runtimeInstanceId,
      Value<String?> runtimeSessionId,
      Value<String?> triggerId,
      Value<String?> triggerType,
      Value<DateTime?> scheduledAt,
      Value<DateTime?> triggeredAt,
      Value<DateTime?> queueStartedAt,
      Value<DateTime?> processStartedAt,
      Value<DateTime?> finishedAt,
      Value<DateTime?> timeoutAt,
      Value<int?> pid,
      Value<int?> exitCode,
      Value<String?> processExecutable,
      Value<int?> processArgumentCount,
      Value<String?> processCommandPreview,
      Value<String?> stdoutText,
      Value<String?> stderrText,
      Value<bool> stdoutTruncated,
      Value<bool> stderrTruncated,
      Value<bool> stdoutStoredInChunks,
      Value<bool> stderrStoredInChunks,
      Value<String?> definitionSnapshotHash,
      Value<String?> contextHash,
      Value<bool> redactionApplied,
      Value<String?> failureCode,
      Value<String?> failurePhase,
      Value<String?> failureMessage,
      Value<int> rowid,
    });

class $$AgentActionExecutionTableTableFilterComposer
    extends Composer<_$AppDatabase, $AgentActionExecutionTableTable> {
  $$AgentActionExecutionTableTableFilterComposer({
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

  ColumnFilters<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestedBy => $composableBuilder(
    column: $table.requestedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get traceId => $composableBuilder(
    column: $table.traceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runtimeInstanceId => $composableBuilder(
    column: $table.runtimeInstanceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runtimeSessionId => $composableBuilder(
    column: $table.runtimeSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerId => $composableBuilder(
    column: $table.triggerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerType => $composableBuilder(
    column: $table.triggerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get queueStartedAt => $composableBuilder(
    column: $table.queueStartedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get processStartedAt => $composableBuilder(
    column: $table.processStartedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timeoutAt => $composableBuilder(
    column: $table.timeoutAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processExecutable => $composableBuilder(
    column: $table.processExecutable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get processArgumentCount => $composableBuilder(
    column: $table.processArgumentCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processCommandPreview => $composableBuilder(
    column: $table.processCommandPreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stdoutText => $composableBuilder(
    column: $table.stdoutText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stderrText => $composableBuilder(
    column: $table.stderrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stdoutTruncated => $composableBuilder(
    column: $table.stdoutTruncated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stderrTruncated => $composableBuilder(
    column: $table.stderrTruncated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stdoutStoredInChunks => $composableBuilder(
    column: $table.stdoutStoredInChunks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stderrStoredInChunks => $composableBuilder(
    column: $table.stderrStoredInChunks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get definitionSnapshotHash => $composableBuilder(
    column: $table.definitionSnapshotHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextHash => $composableBuilder(
    column: $table.contextHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get redactionApplied => $composableBuilder(
    column: $table.redactionApplied,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failurePhase => $composableBuilder(
    column: $table.failurePhase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentActionExecutionTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentActionExecutionTableTable> {
  $$AgentActionExecutionTableTableOrderingComposer({
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

  ColumnOrderings<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestedBy => $composableBuilder(
    column: $table.requestedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get traceId => $composableBuilder(
    column: $table.traceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runtimeInstanceId => $composableBuilder(
    column: $table.runtimeInstanceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runtimeSessionId => $composableBuilder(
    column: $table.runtimeSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerId => $composableBuilder(
    column: $table.triggerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerType => $composableBuilder(
    column: $table.triggerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get queueStartedAt => $composableBuilder(
    column: $table.queueStartedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get processStartedAt => $composableBuilder(
    column: $table.processStartedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timeoutAt => $composableBuilder(
    column: $table.timeoutAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processExecutable => $composableBuilder(
    column: $table.processExecutable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get processArgumentCount => $composableBuilder(
    column: $table.processArgumentCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processCommandPreview => $composableBuilder(
    column: $table.processCommandPreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stdoutText => $composableBuilder(
    column: $table.stdoutText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stderrText => $composableBuilder(
    column: $table.stderrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stdoutTruncated => $composableBuilder(
    column: $table.stdoutTruncated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stderrTruncated => $composableBuilder(
    column: $table.stderrTruncated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stdoutStoredInChunks => $composableBuilder(
    column: $table.stdoutStoredInChunks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stderrStoredInChunks => $composableBuilder(
    column: $table.stderrStoredInChunks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get definitionSnapshotHash => $composableBuilder(
    column: $table.definitionSnapshotHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextHash => $composableBuilder(
    column: $table.contextHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get redactionApplied => $composableBuilder(
    column: $table.redactionApplied,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failurePhase => $composableBuilder(
    column: $table.failurePhase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentActionExecutionTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentActionExecutionTableTable> {
  $$AgentActionExecutionTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actionId =>
      $composableBuilder(column: $table.actionId, builder: (column) => column);

  GeneratedColumn<String> get actionType => $composableBuilder(
    column: $table.actionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestedBy => $composableBuilder(
    column: $table.requestedBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get traceId =>
      $composableBuilder(column: $table.traceId, builder: (column) => column);

  GeneratedColumn<String> get runtimeInstanceId => $composableBuilder(
    column: $table.runtimeInstanceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get runtimeSessionId => $composableBuilder(
    column: $table.runtimeSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get triggerId =>
      $composableBuilder(column: $table.triggerId, builder: (column) => column);

  GeneratedColumn<String> get triggerType => $composableBuilder(
    column: $table.triggerType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get queueStartedAt => $composableBuilder(
    column: $table.queueStartedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get processStartedAt => $composableBuilder(
    column: $table.processStartedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timeoutAt =>
      $composableBuilder(column: $table.timeoutAt, builder: (column) => column);

  GeneratedColumn<int> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get exitCode =>
      $composableBuilder(column: $table.exitCode, builder: (column) => column);

  GeneratedColumn<String> get processExecutable => $composableBuilder(
    column: $table.processExecutable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get processArgumentCount => $composableBuilder(
    column: $table.processArgumentCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processCommandPreview => $composableBuilder(
    column: $table.processCommandPreview,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stdoutText => $composableBuilder(
    column: $table.stdoutText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stderrText => $composableBuilder(
    column: $table.stderrText,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stdoutTruncated => $composableBuilder(
    column: $table.stdoutTruncated,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stderrTruncated => $composableBuilder(
    column: $table.stderrTruncated,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stdoutStoredInChunks => $composableBuilder(
    column: $table.stdoutStoredInChunks,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stderrStoredInChunks => $composableBuilder(
    column: $table.stderrStoredInChunks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get definitionSnapshotHash => $composableBuilder(
    column: $table.definitionSnapshotHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contextHash => $composableBuilder(
    column: $table.contextHash,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get redactionApplied => $composableBuilder(
    column: $table.redactionApplied,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failurePhase => $composableBuilder(
    column: $table.failurePhase,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => column,
  );
}

class $$AgentActionExecutionTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentActionExecutionTableTable,
          AgentActionExecutionData,
          $$AgentActionExecutionTableTableFilterComposer,
          $$AgentActionExecutionTableTableOrderingComposer,
          $$AgentActionExecutionTableTableAnnotationComposer,
          $$AgentActionExecutionTableTableCreateCompanionBuilder,
          $$AgentActionExecutionTableTableUpdateCompanionBuilder,
          (
            AgentActionExecutionData,
            BaseReferences<
              _$AppDatabase,
              $AgentActionExecutionTableTable,
              AgentActionExecutionData
            >,
          ),
          AgentActionExecutionData,
          PrefetchHooks Function()
        > {
  $$AgentActionExecutionTableTableTableManager(
    _$AppDatabase db,
    $AgentActionExecutionTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentActionExecutionTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AgentActionExecutionTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AgentActionExecutionTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> actionId = const Value.absent(),
                Value<String> actionType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> requestedAt = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> idempotencyKey = const Value.absent(),
                Value<String?> requestedBy = const Value.absent(),
                Value<String?> traceId = const Value.absent(),
                Value<String?> runtimeInstanceId = const Value.absent(),
                Value<String?> runtimeSessionId = const Value.absent(),
                Value<String?> triggerId = const Value.absent(),
                Value<String?> triggerType = const Value.absent(),
                Value<DateTime?> scheduledAt = const Value.absent(),
                Value<DateTime?> triggeredAt = const Value.absent(),
                Value<DateTime?> queueStartedAt = const Value.absent(),
                Value<DateTime?> processStartedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<DateTime?> timeoutAt = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<String?> processExecutable = const Value.absent(),
                Value<int?> processArgumentCount = const Value.absent(),
                Value<String?> processCommandPreview = const Value.absent(),
                Value<String?> stdoutText = const Value.absent(),
                Value<String?> stderrText = const Value.absent(),
                Value<bool> stdoutTruncated = const Value.absent(),
                Value<bool> stderrTruncated = const Value.absent(),
                Value<bool> stdoutStoredInChunks = const Value.absent(),
                Value<bool> stderrStoredInChunks = const Value.absent(),
                Value<String?> definitionSnapshotHash = const Value.absent(),
                Value<String?> contextHash = const Value.absent(),
                Value<bool> redactionApplied = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> failurePhase = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentActionExecutionTableCompanion(
                id: id,
                actionId: actionId,
                actionType: actionType,
                status: status,
                requestedAt: requestedAt,
                source: source,
                idempotencyKey: idempotencyKey,
                requestedBy: requestedBy,
                traceId: traceId,
                runtimeInstanceId: runtimeInstanceId,
                runtimeSessionId: runtimeSessionId,
                triggerId: triggerId,
                triggerType: triggerType,
                scheduledAt: scheduledAt,
                triggeredAt: triggeredAt,
                queueStartedAt: queueStartedAt,
                processStartedAt: processStartedAt,
                finishedAt: finishedAt,
                timeoutAt: timeoutAt,
                pid: pid,
                exitCode: exitCode,
                processExecutable: processExecutable,
                processArgumentCount: processArgumentCount,
                processCommandPreview: processCommandPreview,
                stdoutText: stdoutText,
                stderrText: stderrText,
                stdoutTruncated: stdoutTruncated,
                stderrTruncated: stderrTruncated,
                stdoutStoredInChunks: stdoutStoredInChunks,
                stderrStoredInChunks: stderrStoredInChunks,
                definitionSnapshotHash: definitionSnapshotHash,
                contextHash: contextHash,
                redactionApplied: redactionApplied,
                failureCode: failureCode,
                failurePhase: failurePhase,
                failureMessage: failureMessage,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String actionId,
                required String actionType,
                required String status,
                required DateTime requestedAt,
                required String source,
                Value<String?> idempotencyKey = const Value.absent(),
                Value<String?> requestedBy = const Value.absent(),
                Value<String?> traceId = const Value.absent(),
                Value<String?> runtimeInstanceId = const Value.absent(),
                Value<String?> runtimeSessionId = const Value.absent(),
                Value<String?> triggerId = const Value.absent(),
                Value<String?> triggerType = const Value.absent(),
                Value<DateTime?> scheduledAt = const Value.absent(),
                Value<DateTime?> triggeredAt = const Value.absent(),
                Value<DateTime?> queueStartedAt = const Value.absent(),
                Value<DateTime?> processStartedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<DateTime?> timeoutAt = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<String?> processExecutable = const Value.absent(),
                Value<int?> processArgumentCount = const Value.absent(),
                Value<String?> processCommandPreview = const Value.absent(),
                Value<String?> stdoutText = const Value.absent(),
                Value<String?> stderrText = const Value.absent(),
                Value<bool> stdoutTruncated = const Value.absent(),
                Value<bool> stderrTruncated = const Value.absent(),
                Value<bool> stdoutStoredInChunks = const Value.absent(),
                Value<bool> stderrStoredInChunks = const Value.absent(),
                Value<String?> definitionSnapshotHash = const Value.absent(),
                Value<String?> contextHash = const Value.absent(),
                Value<bool> redactionApplied = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> failurePhase = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentActionExecutionTableCompanion.insert(
                id: id,
                actionId: actionId,
                actionType: actionType,
                status: status,
                requestedAt: requestedAt,
                source: source,
                idempotencyKey: idempotencyKey,
                requestedBy: requestedBy,
                traceId: traceId,
                runtimeInstanceId: runtimeInstanceId,
                runtimeSessionId: runtimeSessionId,
                triggerId: triggerId,
                triggerType: triggerType,
                scheduledAt: scheduledAt,
                triggeredAt: triggeredAt,
                queueStartedAt: queueStartedAt,
                processStartedAt: processStartedAt,
                finishedAt: finishedAt,
                timeoutAt: timeoutAt,
                pid: pid,
                exitCode: exitCode,
                processExecutable: processExecutable,
                processArgumentCount: processArgumentCount,
                processCommandPreview: processCommandPreview,
                stdoutText: stdoutText,
                stderrText: stderrText,
                stdoutTruncated: stdoutTruncated,
                stderrTruncated: stderrTruncated,
                stdoutStoredInChunks: stdoutStoredInChunks,
                stderrStoredInChunks: stderrStoredInChunks,
                definitionSnapshotHash: definitionSnapshotHash,
                contextHash: contextHash,
                redactionApplied: redactionApplied,
                failureCode: failureCode,
                failurePhase: failurePhase,
                failureMessage: failureMessage,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentActionExecutionTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentActionExecutionTableTable,
      AgentActionExecutionData,
      $$AgentActionExecutionTableTableFilterComposer,
      $$AgentActionExecutionTableTableOrderingComposer,
      $$AgentActionExecutionTableTableAnnotationComposer,
      $$AgentActionExecutionTableTableCreateCompanionBuilder,
      $$AgentActionExecutionTableTableUpdateCompanionBuilder,
      (
        AgentActionExecutionData,
        BaseReferences<
          _$AppDatabase,
          $AgentActionExecutionTableTable,
          AgentActionExecutionData
        >,
      ),
      AgentActionExecutionData,
      PrefetchHooks Function()
    >;
typedef $$RpcIdempotencyCacheTableTableCreateCompanionBuilder =
    RpcIdempotencyCacheTableCompanion Function({
      required String cacheKey,
      required String responseJson,
      Value<String?> requestFingerprint,
      required DateTime expiresAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RpcIdempotencyCacheTableTableUpdateCompanionBuilder =
    RpcIdempotencyCacheTableCompanion Function({
      Value<String> cacheKey,
      Value<String> responseJson,
      Value<String?> requestFingerprint,
      Value<DateTime> expiresAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$RpcIdempotencyCacheTableTableFilterComposer
    extends Composer<_$AppDatabase, $RpcIdempotencyCacheTableTable> {
  $$RpcIdempotencyCacheTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get responseJson => $composableBuilder(
    column: $table.responseJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestFingerprint => $composableBuilder(
    column: $table.requestFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RpcIdempotencyCacheTableTableOrderingComposer
    extends Composer<_$AppDatabase, $RpcIdempotencyCacheTableTable> {
  $$RpcIdempotencyCacheTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get responseJson => $composableBuilder(
    column: $table.responseJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestFingerprint => $composableBuilder(
    column: $table.requestFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RpcIdempotencyCacheTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $RpcIdempotencyCacheTableTable> {
  $$RpcIdempotencyCacheTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get responseJson => $composableBuilder(
    column: $table.responseJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestFingerprint => $composableBuilder(
    column: $table.requestFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RpcIdempotencyCacheTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RpcIdempotencyCacheTableTable,
          RpcIdempotencyCacheData,
          $$RpcIdempotencyCacheTableTableFilterComposer,
          $$RpcIdempotencyCacheTableTableOrderingComposer,
          $$RpcIdempotencyCacheTableTableAnnotationComposer,
          $$RpcIdempotencyCacheTableTableCreateCompanionBuilder,
          $$RpcIdempotencyCacheTableTableUpdateCompanionBuilder,
          (
            RpcIdempotencyCacheData,
            BaseReferences<
              _$AppDatabase,
              $RpcIdempotencyCacheTableTable,
              RpcIdempotencyCacheData
            >,
          ),
          RpcIdempotencyCacheData,
          PrefetchHooks Function()
        > {
  $$RpcIdempotencyCacheTableTableTableManager(
    _$AppDatabase db,
    $RpcIdempotencyCacheTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RpcIdempotencyCacheTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RpcIdempotencyCacheTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RpcIdempotencyCacheTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> responseJson = const Value.absent(),
                Value<String?> requestFingerprint = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RpcIdempotencyCacheTableCompanion(
                cacheKey: cacheKey,
                responseJson: responseJson,
                requestFingerprint: requestFingerprint,
                expiresAt: expiresAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String responseJson,
                Value<String?> requestFingerprint = const Value.absent(),
                required DateTime expiresAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RpcIdempotencyCacheTableCompanion.insert(
                cacheKey: cacheKey,
                responseJson: responseJson,
                requestFingerprint: requestFingerprint,
                expiresAt: expiresAt,
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

typedef $$RpcIdempotencyCacheTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RpcIdempotencyCacheTableTable,
      RpcIdempotencyCacheData,
      $$RpcIdempotencyCacheTableTableFilterComposer,
      $$RpcIdempotencyCacheTableTableOrderingComposer,
      $$RpcIdempotencyCacheTableTableAnnotationComposer,
      $$RpcIdempotencyCacheTableTableCreateCompanionBuilder,
      $$RpcIdempotencyCacheTableTableUpdateCompanionBuilder,
      (
        RpcIdempotencyCacheData,
        BaseReferences<
          _$AppDatabase,
          $RpcIdempotencyCacheTableTable,
          RpcIdempotencyCacheData
        >,
      ),
      RpcIdempotencyCacheData,
      PrefetchHooks Function()
    >;
typedef $$AgentActionRemoteAuditTableTableCreateCompanionBuilder =
    AgentActionRemoteAuditTableCompanion Function({
      required String id,
      required DateTime occurredAt,
      required String rpcMethod,
      Value<String?> actionId,
      Value<String?> executionId,
      Value<String?> traceId,
      Value<String?> requestedBy,
      required String outcome,
      Value<String?> reasonCode,
      Value<int?> rpcErrorCode,
      Value<bool> credentialPresent,
      Value<String?> clientId,
      Value<String?> tokenJti,
      Value<String?> runtimeInstanceId,
      Value<String?> runtimeSessionId,
      Value<String?> idempotencyKey,
      Value<int> rowid,
    });
typedef $$AgentActionRemoteAuditTableTableUpdateCompanionBuilder =
    AgentActionRemoteAuditTableCompanion Function({
      Value<String> id,
      Value<DateTime> occurredAt,
      Value<String> rpcMethod,
      Value<String?> actionId,
      Value<String?> executionId,
      Value<String?> traceId,
      Value<String?> requestedBy,
      Value<String> outcome,
      Value<String?> reasonCode,
      Value<int?> rpcErrorCode,
      Value<bool> credentialPresent,
      Value<String?> clientId,
      Value<String?> tokenJti,
      Value<String?> runtimeInstanceId,
      Value<String?> runtimeSessionId,
      Value<String?> idempotencyKey,
      Value<int> rowid,
    });

class $$AgentActionRemoteAuditTableTableFilterComposer
    extends Composer<_$AppDatabase, $AgentActionRemoteAuditTableTable> {
  $$AgentActionRemoteAuditTableTableFilterComposer({
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

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rpcMethod => $composableBuilder(
    column: $table.rpcMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get traceId => $composableBuilder(
    column: $table.traceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestedBy => $composableBuilder(
    column: $table.requestedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rpcErrorCode => $composableBuilder(
    column: $table.rpcErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get credentialPresent => $composableBuilder(
    column: $table.credentialPresent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenJti => $composableBuilder(
    column: $table.tokenJti,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runtimeInstanceId => $composableBuilder(
    column: $table.runtimeInstanceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runtimeSessionId => $composableBuilder(
    column: $table.runtimeSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentActionRemoteAuditTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentActionRemoteAuditTableTable> {
  $$AgentActionRemoteAuditTableTableOrderingComposer({
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

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rpcMethod => $composableBuilder(
    column: $table.rpcMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get traceId => $composableBuilder(
    column: $table.traceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestedBy => $composableBuilder(
    column: $table.requestedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rpcErrorCode => $composableBuilder(
    column: $table.rpcErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get credentialPresent => $composableBuilder(
    column: $table.credentialPresent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenJti => $composableBuilder(
    column: $table.tokenJti,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runtimeInstanceId => $composableBuilder(
    column: $table.runtimeInstanceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runtimeSessionId => $composableBuilder(
    column: $table.runtimeSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentActionRemoteAuditTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentActionRemoteAuditTableTable> {
  $$AgentActionRemoteAuditTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rpcMethod =>
      $composableBuilder(column: $table.rpcMethod, builder: (column) => column);

  GeneratedColumn<String> get actionId =>
      $composableBuilder(column: $table.actionId, builder: (column) => column);

  GeneratedColumn<String> get executionId => $composableBuilder(
    column: $table.executionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get traceId =>
      $composableBuilder(column: $table.traceId, builder: (column) => column);

  GeneratedColumn<String> get requestedBy => $composableBuilder(
    column: $table.requestedBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rpcErrorCode => $composableBuilder(
    column: $table.rpcErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get credentialPresent => $composableBuilder(
    column: $table.credentialPresent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get tokenJti =>
      $composableBuilder(column: $table.tokenJti, builder: (column) => column);

  GeneratedColumn<String> get runtimeInstanceId => $composableBuilder(
    column: $table.runtimeInstanceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get runtimeSessionId => $composableBuilder(
    column: $table.runtimeSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );
}

class $$AgentActionRemoteAuditTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentActionRemoteAuditTableTable,
          AgentActionRemoteAuditData,
          $$AgentActionRemoteAuditTableTableFilterComposer,
          $$AgentActionRemoteAuditTableTableOrderingComposer,
          $$AgentActionRemoteAuditTableTableAnnotationComposer,
          $$AgentActionRemoteAuditTableTableCreateCompanionBuilder,
          $$AgentActionRemoteAuditTableTableUpdateCompanionBuilder,
          (
            AgentActionRemoteAuditData,
            BaseReferences<
              _$AppDatabase,
              $AgentActionRemoteAuditTableTable,
              AgentActionRemoteAuditData
            >,
          ),
          AgentActionRemoteAuditData,
          PrefetchHooks Function()
        > {
  $$AgentActionRemoteAuditTableTableTableManager(
    _$AppDatabase db,
    $AgentActionRemoteAuditTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentActionRemoteAuditTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AgentActionRemoteAuditTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AgentActionRemoteAuditTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String> rpcMethod = const Value.absent(),
                Value<String?> actionId = const Value.absent(),
                Value<String?> executionId = const Value.absent(),
                Value<String?> traceId = const Value.absent(),
                Value<String?> requestedBy = const Value.absent(),
                Value<String> outcome = const Value.absent(),
                Value<String?> reasonCode = const Value.absent(),
                Value<int?> rpcErrorCode = const Value.absent(),
                Value<bool> credentialPresent = const Value.absent(),
                Value<String?> clientId = const Value.absent(),
                Value<String?> tokenJti = const Value.absent(),
                Value<String?> runtimeInstanceId = const Value.absent(),
                Value<String?> runtimeSessionId = const Value.absent(),
                Value<String?> idempotencyKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentActionRemoteAuditTableCompanion(
                id: id,
                occurredAt: occurredAt,
                rpcMethod: rpcMethod,
                actionId: actionId,
                executionId: executionId,
                traceId: traceId,
                requestedBy: requestedBy,
                outcome: outcome,
                reasonCode: reasonCode,
                rpcErrorCode: rpcErrorCode,
                credentialPresent: credentialPresent,
                clientId: clientId,
                tokenJti: tokenJti,
                runtimeInstanceId: runtimeInstanceId,
                runtimeSessionId: runtimeSessionId,
                idempotencyKey: idempotencyKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime occurredAt,
                required String rpcMethod,
                Value<String?> actionId = const Value.absent(),
                Value<String?> executionId = const Value.absent(),
                Value<String?> traceId = const Value.absent(),
                Value<String?> requestedBy = const Value.absent(),
                required String outcome,
                Value<String?> reasonCode = const Value.absent(),
                Value<int?> rpcErrorCode = const Value.absent(),
                Value<bool> credentialPresent = const Value.absent(),
                Value<String?> clientId = const Value.absent(),
                Value<String?> tokenJti = const Value.absent(),
                Value<String?> runtimeInstanceId = const Value.absent(),
                Value<String?> runtimeSessionId = const Value.absent(),
                Value<String?> idempotencyKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentActionRemoteAuditTableCompanion.insert(
                id: id,
                occurredAt: occurredAt,
                rpcMethod: rpcMethod,
                actionId: actionId,
                executionId: executionId,
                traceId: traceId,
                requestedBy: requestedBy,
                outcome: outcome,
                reasonCode: reasonCode,
                rpcErrorCode: rpcErrorCode,
                credentialPresent: credentialPresent,
                clientId: clientId,
                tokenJti: tokenJti,
                runtimeInstanceId: runtimeInstanceId,
                runtimeSessionId: runtimeSessionId,
                idempotencyKey: idempotencyKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentActionRemoteAuditTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentActionRemoteAuditTableTable,
      AgentActionRemoteAuditData,
      $$AgentActionRemoteAuditTableTableFilterComposer,
      $$AgentActionRemoteAuditTableTableOrderingComposer,
      $$AgentActionRemoteAuditTableTableAnnotationComposer,
      $$AgentActionRemoteAuditTableTableCreateCompanionBuilder,
      $$AgentActionRemoteAuditTableTableUpdateCompanionBuilder,
      (
        AgentActionRemoteAuditData,
        BaseReferences<
          _$AppDatabase,
          $AgentActionRemoteAuditTableTable,
          AgentActionRemoteAuditData
        >,
      ),
      AgentActionRemoteAuditData,
      PrefetchHooks Function()
    >;
typedef $$AgentActionCapturedOutputChunkTableTableCreateCompanionBuilder =
    AgentActionCapturedOutputChunkTableCompanion Function({
      required String executionId,
      required String stream,
      required int chunkIndex,
      required int utf8Offset,
      required String payload,
      Value<int> rowid,
    });
typedef $$AgentActionCapturedOutputChunkTableTableUpdateCompanionBuilder =
    AgentActionCapturedOutputChunkTableCompanion Function({
      Value<String> executionId,
      Value<String> stream,
      Value<int> chunkIndex,
      Value<int> utf8Offset,
      Value<String> payload,
      Value<int> rowid,
    });

class $$AgentActionCapturedOutputChunkTableTableFilterComposer
    extends Composer<_$AppDatabase, $AgentActionCapturedOutputChunkTableTable> {
  $$AgentActionCapturedOutputChunkTableTableFilterComposer({
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

  ColumnFilters<String> get stream => $composableBuilder(
    column: $table.stream,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get utf8Offset => $composableBuilder(
    column: $table.utf8Offset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentActionCapturedOutputChunkTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentActionCapturedOutputChunkTableTable> {
  $$AgentActionCapturedOutputChunkTableTableOrderingComposer({
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

  ColumnOrderings<String> get stream => $composableBuilder(
    column: $table.stream,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get utf8Offset => $composableBuilder(
    column: $table.utf8Offset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentActionCapturedOutputChunkTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentActionCapturedOutputChunkTableTable> {
  $$AgentActionCapturedOutputChunkTableTableAnnotationComposer({
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

  GeneratedColumn<String> get stream =>
      $composableBuilder(column: $table.stream, builder: (column) => column);

  GeneratedColumn<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get utf8Offset => $composableBuilder(
    column: $table.utf8Offset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$AgentActionCapturedOutputChunkTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentActionCapturedOutputChunkTableTable,
          AgentActionCapturedOutputChunkData,
          $$AgentActionCapturedOutputChunkTableTableFilterComposer,
          $$AgentActionCapturedOutputChunkTableTableOrderingComposer,
          $$AgentActionCapturedOutputChunkTableTableAnnotationComposer,
          $$AgentActionCapturedOutputChunkTableTableCreateCompanionBuilder,
          $$AgentActionCapturedOutputChunkTableTableUpdateCompanionBuilder,
          (
            AgentActionCapturedOutputChunkData,
            BaseReferences<
              _$AppDatabase,
              $AgentActionCapturedOutputChunkTableTable,
              AgentActionCapturedOutputChunkData
            >,
          ),
          AgentActionCapturedOutputChunkData,
          PrefetchHooks Function()
        > {
  $$AgentActionCapturedOutputChunkTableTableTableManager(
    _$AppDatabase db,
    $AgentActionCapturedOutputChunkTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentActionCapturedOutputChunkTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AgentActionCapturedOutputChunkTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AgentActionCapturedOutputChunkTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> executionId = const Value.absent(),
                Value<String> stream = const Value.absent(),
                Value<int> chunkIndex = const Value.absent(),
                Value<int> utf8Offset = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentActionCapturedOutputChunkTableCompanion(
                executionId: executionId,
                stream: stream,
                chunkIndex: chunkIndex,
                utf8Offset: utf8Offset,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String executionId,
                required String stream,
                required int chunkIndex,
                required int utf8Offset,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => AgentActionCapturedOutputChunkTableCompanion.insert(
                executionId: executionId,
                stream: stream,
                chunkIndex: chunkIndex,
                utf8Offset: utf8Offset,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentActionCapturedOutputChunkTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentActionCapturedOutputChunkTableTable,
      AgentActionCapturedOutputChunkData,
      $$AgentActionCapturedOutputChunkTableTableFilterComposer,
      $$AgentActionCapturedOutputChunkTableTableOrderingComposer,
      $$AgentActionCapturedOutputChunkTableTableAnnotationComposer,
      $$AgentActionCapturedOutputChunkTableTableCreateCompanionBuilder,
      $$AgentActionCapturedOutputChunkTableTableUpdateCompanionBuilder,
      (
        AgentActionCapturedOutputChunkData,
        BaseReferences<
          _$AppDatabase,
          $AgentActionCapturedOutputChunkTableTable,
          AgentActionCapturedOutputChunkData
        >,
      ),
      AgentActionCapturedOutputChunkData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConfigTableTableTableManager get configTable =>
      $$ConfigTableTableTableManager(_db, _db.configTable);
  $$ClientTokenCacheTableTableTableManager get clientTokenCacheTable =>
      $$ClientTokenCacheTableTableTableManager(_db, _db.clientTokenCacheTable);
  $$AgentActionDefinitionTableTableTableManager
  get agentActionDefinitionTable =>
      $$AgentActionDefinitionTableTableTableManager(
        _db,
        _db.agentActionDefinitionTable,
      );
  $$AgentActionTriggerTableTableTableManager get agentActionTriggerTable =>
      $$AgentActionTriggerTableTableTableManager(
        _db,
        _db.agentActionTriggerTable,
      );
  $$AgentActionExecutionTableTableTableManager get agentActionExecutionTable =>
      $$AgentActionExecutionTableTableTableManager(
        _db,
        _db.agentActionExecutionTable,
      );
  $$RpcIdempotencyCacheTableTableTableManager get rpcIdempotencyCacheTable =>
      $$RpcIdempotencyCacheTableTableTableManager(
        _db,
        _db.rpcIdempotencyCacheTable,
      );
  $$AgentActionRemoteAuditTableTableTableManager
  get agentActionRemoteAuditTable =>
      $$AgentActionRemoteAuditTableTableTableManager(
        _db,
        _db.agentActionRemoteAuditTable,
      );
  $$AgentActionCapturedOutputChunkTableTableTableManager
  get agentActionCapturedOutputChunkTable =>
      $$AgentActionCapturedOutputChunkTableTableTableManager(
        _db,
        _db.agentActionCapturedOutputChunkTable,
      );
}
