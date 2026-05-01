import 'package:plug_agente/core/constants/app_version.g.dart' as app_version;
import 'package:plug_agente/core/constants/connection_constants.dart';

class AppConstants {
  static const String appName = 'Plug Database';
  static const String appVersion = app_version.appVersion;

  static const String defaultServerUrl = 'https://api.example.com';
  static const String defaultHubUrl = 'wss://api.example.com/hub';

  static const int connectionTimeoutSeconds = 30;
  static const int publicApiTimeoutSeconds = 15;
  static const int hubAvailabilityProbeTimeoutSeconds = 4;
  static const int queryTimeoutSeconds = 60;
  static const int reconnectIntervalSeconds = 5;
  static const String defaultHubAvailabilityProbePath = '/health';

  /// Hub burst recovery attempts (same value as [ConnectionConstants.defaultHubRecoveryBurstMaxAttempts]).
  static const int maxReconnectAttempts = ConnectionConstants.defaultHubRecoveryBurstMaxAttempts;

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
  static const int httpStatusForbidden = 403;
  static const int httpStatusNotFound = 404;
  static const int httpStatusConflict = 409;
  static const int httpStatusTooManyRequests = 429;

  /// Path template: replace `{agentId}` with the agent UUID.
  static String agentHubProfilePath(String agentId) => '/api/v1/agents/$agentId/profile';

  static const int userAgentInitPollIntervalMs = 10;
  static const String notificationAppUserModelGuid = 'A181BB32-71A7-4B9E-9C3F-8E2D1B4A5C6D';

  static const Duration dashboardMetricsInterval = Duration(seconds: 5);

  /// Max in-memory items for WebSocket log and SQL investigation dashboard feeds.
  static const int dashboardDiagnosticFeedMaxItems = 500;
  static const Duration clientTokenDebounceDelay = Duration(milliseconds: 250);
  static const Duration formTransitionDelay = Duration(milliseconds: 100);
  static const Duration ruleDialogTransition = Duration(milliseconds: 120);
}
