class Config {
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

  const Config({
    required this.id,
    this.serverUrl = 'https://api.example.com', // Default for migration/new
    this.agentId = '',
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

  Config copyWith({
    String? id,
    String? serverUrl,
    String? agentId,
    String? authToken,
    String? refreshToken,
    String? authUsername,
    String? authPassword,
    String? driverName,
    String? connectionString,
    String? username,
    String? password,
    String? databaseName,
    String? host,
    int? port,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Config(
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
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Config && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}