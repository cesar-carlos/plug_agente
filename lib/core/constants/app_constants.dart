import 'package:plug_agente/core/constants/app_version.g.dart' as app_version;

class AppConstants {
  static const String appName = 'Plug Database';
  static const String appVersion = app_version.appVersion;

  static const String defaultServerUrl = 'https://api.example.com';
  static const String defaultHubUrl = 'wss://api.example.com/hub';

  static const int connectionTimeoutSeconds = 30;
  static const int queryTimeoutSeconds = 60;
  static const int reconnectIntervalSeconds = 5;
  static const int maxReconnectAttempts = 3;

  static const String databaseConfigFileName = 'database_config.json';
  static const String agentConfigFileName = 'agent_config.json';

  static const String socketEventAgentRegister = 'agent:register';
  static const String socketEventAgentUnregister = 'agent:unregister';

  static const String authAgentLoginPath = '/api/v1/auth/agent-login';
  static const String authAgentLoginCompatPath = '/auth/agent-login';
  static const String authLoginPath = '/auth/login'; // Legacy fallback.
  static const String authRefreshPath = '/api/v1/auth/refresh';
  static const String authRefreshCompatPath = '/auth/refresh';
  static const int authTimeoutSeconds = 30;
  static const int refreshTokenExpiryHours = 24;

  static const int httpStatusOk = 200;
  static const int httpStatusUnauthorized = 401;
  static const int httpStatusNotFound = 404;
  static const int httpStatusTooManyRequests = 429;

  static const int userAgentInitPollIntervalMs = 10;
  static const String notificationAppUserModelGuid = 'A181BB32-71A7-4B9E-9C3F-8E2D1B4A5C6D';

  static const Duration windowShowInitialDelay = Duration(milliseconds: 100);
  static const Duration windowShowRestoreDelay = Duration(milliseconds: 200);
  static const Duration windowShowFinalDelay = Duration(milliseconds: 300);
  static const Duration trayInitDelay = Duration(milliseconds: 100);
  static const Duration trayContextMenuDelay = Duration(milliseconds: 50);
  static const Duration trayIconClickDelay = Duration(milliseconds: 200);
  static const Duration dashboardMetricsInterval = Duration(seconds: 5);
  static const Duration clientTokenDebounceDelay = Duration(milliseconds: 250);
  static const Duration formTransitionDelay = Duration(milliseconds: 100);
  static const Duration ruleDialogTransition = Duration(milliseconds: 120);
}
