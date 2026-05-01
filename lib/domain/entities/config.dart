// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: Config uses ID-based equality for collections and state comparison.

import 'package:plug_agente/core/constants/sql_anywhere_connection_string.dart';

class Config {
  const Config({
    required this.id,
    required this.driverName,
    required this.odbcDriverName,
    required this.connectionString,
    required this.username,
    required this.databaseName,
    required this.host,
    required this.port,
    required this.createdAt,
    required this.updatedAt,
    this.serverUrl = 'https://api.example.com',
    this.agentId = '',
    this.authToken,
    this.refreshToken,
    this.authUsername,
    this.authPassword,
    this.password,
    this.nome = '',
    this.nomeFantasia = '',
    this.cnaeCnpjCpf = '',
    this.telefone = '',
    this.celular = '',
    this.email = '',
    this.endereco = '',
    this.numeroEndereco = '',
    this.bairro = '',
    this.cep = '',
    this.nomeMunicipio = '',
    this.ufMunicipio = '',
    this.observacao = '',
    this.hubProfileVersion,
    this.hubProfileUpdatedAt,
  });

  static const Object _unset = Object();
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

  /// Last known catalog `profileVersion` on the hub after a successful PATCH (optional CAS).
  final int? hubProfileVersion;

  /// ISO-8601 timestamp from hub `profileUpdatedAt` when last sync succeeded.
  final String? hubProfileUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Config copyWith({
    String? id,
    String? serverUrl,
    String? agentId,
    Object? authToken = _unset,
    Object? refreshToken = _unset,
    Object? authUsername = _unset,
    Object? authPassword = _unset,
    String? driverName,
    String? odbcDriverName,
    String? connectionString,
    String? username,
    Object? password = _unset,
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
    Object? hubProfileVersion = _unset,
    Object? hubProfileUpdatedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Config(
      id: id ?? this.id,
      serverUrl: serverUrl ?? this.serverUrl,
      agentId: agentId ?? this.agentId,
      authToken: identical(authToken, _unset) ? this.authToken : authToken as String?,
      refreshToken: identical(refreshToken, _unset) ? this.refreshToken : refreshToken as String?,
      authUsername: identical(authUsername, _unset) ? this.authUsername : authUsername as String?,
      authPassword: identical(authPassword, _unset) ? this.authPassword : authPassword as String?,
      driverName: driverName ?? this.driverName,
      odbcDriverName: odbcDriverName ?? this.odbcDriverName,
      connectionString: connectionString ?? this.connectionString,
      username: username ?? this.username,
      password: identical(password, _unset) ? this.password : password as String?,
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
      hubProfileVersion: identical(hubProfileVersion, _unset) ? this.hubProfileVersion : hubProfileVersion as int?,
      hubProfileUpdatedAt: identical(hubProfileUpdatedAt, _unset)
          ? this.hubProfileUpdatedAt
          : hubProfileUpdatedAt as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Config && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  String resolveConnectionString() {
    final persisted = connectionString.trim();
    if (persisted.isNotEmpty) {
      return persisted;
    }

    final passwordSegment = password != null ? ';PWD=$password' : '';

    return switch (driverName) {
      'SQL Server' =>
        'DRIVER={${odbcDriverName.isNotEmpty ? odbcDriverName : 'ODBC Driver 17 for SQL Server'}};'
            'SERVER=$host,$port;DATABASE=$databaseName;UID=$username$passwordSegment',
      'PostgreSQL' =>
        'DRIVER={${odbcDriverName.isNotEmpty ? odbcDriverName : 'PostgreSQL Unicode'}};'
            'SERVER=$host;PORT=$port;DATABASE=$databaseName;UID=$username$passwordSegment',
      'SQL Anywhere' => SqlAnywhereConnectionString.build(
        driverName: odbcDriverName,
        username: username,
        database: databaseName,
        host: host,
        port: port,
        password: password,
      ),
      _ =>
        'DRIVER={${odbcDriverName.isNotEmpty ? odbcDriverName : driverName}};'
            'SERVER=$host;PORT=$port;DATABASE=$databaseName;UID=$username$passwordSegment',
    };
  }
}
