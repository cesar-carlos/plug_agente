class AppConstants {
  static const String appName = 'Plug Database';
  static const String appVersion = '1.0.0';
  
  static const String defaultServerUrl = 'https://api.example.com';
  static const String defaultHubUrl = 'wss://api.example.com/hub';
  
  static const int connectionTimeoutSeconds = 30;
  static const int queryTimeoutSeconds = 60;
  static const int reconnectIntervalSeconds = 5;
  static const int maxReconnectAttempts = 10;
  
  static const String databaseConfigFileName = 'database_config.json';
  static const String agentConfigFileName = 'agent_config.json';
  
  static const String socketEventQueryRequest = 'query:request';
  static const String socketEventQueryResponse = 'query:response';
  static const String socketEventAgentRegister = 'agent:register';
  static const String socketEventAgentUnregister = 'agent:unregister';
  
  static const String authLoginPath = '/auth/login';
  static const String authRefreshPath = '/auth/refresh';
  static const int authTimeoutSeconds = 30;
  static const int refreshTokenExpiryHours = 24;
  
  static const int httpStatusOk = 200;
  static const int httpStatusUnauthorized = 401;
}