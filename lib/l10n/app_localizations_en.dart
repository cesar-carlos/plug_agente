// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navDatabaseSettings => 'Database';

  @override
  String get navPlayground => 'Playground';

  @override
  String get navSettings => 'Settings';

  @override
  String get navWebSocketSettings => 'WebSocket connection';

  @override
  String get mainDegradedModeTitle => 'Degraded mode active';

  @override
  String get mainDegradedModeDescription =>
      'The application is running with limited capabilities:';

  @override
  String get titlePlayground => 'Playground Database';

  @override
  String get titleConfig => 'Settings - Plug Database';

  @override
  String get modalTitleSuccess => 'Success';

  @override
  String get modalTitleError => 'Error';

  @override
  String get modalTitleAuthError => 'Authentication Error';

  @override
  String get modalTitleConnectionError => 'Connection Error';

  @override
  String get modalTitleConfigError => 'Configuration Error';

  @override
  String get modalTitleConnectionEstablished => 'Connection Established';

  @override
  String get modalTitleDriverNotFound => 'Driver Not Found';

  @override
  String get modalTitleConnectionSuccessful => 'Connection Successful';

  @override
  String get modalTitleConnectionFailed => 'Connection Failed';

  @override
  String get modalTitleConfigSaved => 'Configuration Saved';

  @override
  String get modalTitleErrorTestingConnection => 'Error Testing Connection';

  @override
  String get modalTitleErrorVerifyingDriver => 'Error Verifying Driver';

  @override
  String get modalTitleErrorSaving => 'Error Saving';

  @override
  String get modalTitleConnectionStatus => 'Connection Status';

  @override
  String get msgAuthenticatedSuccessfully => 'Authenticated successfully!';

  @override
  String get msgWebSocketConnectedSuccessfully =>
      'Connected to WebSocket server successfully!';

  @override
  String get msgDatabaseConnectionSuccessful =>
      'Database connection established successfully!';

  @override
  String get msgConfigSavedSuccessfully => 'Configuration saved successfully!';

  @override
  String get msgConnectionSuccessful => 'success';

  @override
  String get msgOdbcDriverNameRequired => 'ODBC Driver name is required';

  @override
  String get msgConnectionCheckFailed =>
      'Could not connect to database. Check credentials and settings.';

  @override
  String get btnOk => 'OK';

  @override
  String get btnCancel => 'Cancel';

  @override
  String get btnRetry => 'Retry';

  @override
  String get errorTitleValidation => 'Invalid data';

  @override
  String get errorTitleNetwork => 'Network error';

  @override
  String get errorTitleDatabase => 'Database error';

  @override
  String get errorTitleServer => 'Server error';

  @override
  String get errorTitleNotFound => 'Not found';

  @override
  String get queryNoResults => 'No results';

  @override
  String get queryNoResultsMessage =>
      'Execute a SELECT query to see results here.';

  @override
  String get queryTotalRecords => 'Total records';

  @override
  String get queryExecutionTime => 'Execution time';

  @override
  String get queryAffectedRows => 'Affected rows';

  @override
  String get queryErrorTitle => 'Query error';

  @override
  String get queryErrorShowDetails => 'View details';

  @override
  String get querySqlLabel => 'SQL query';

  @override
  String get querySqlHint => 'SELECT * FROM table...';

  @override
  String get queryActionExecute => 'Run';

  @override
  String get queryActionTestConnection => 'Test connection';

  @override
  String get queryActionClear => 'Clear';

  @override
  String get queryActionCancel => 'Cancel';

  @override
  String get queryConnectionStatusTitle => 'Connection status';

  @override
  String get queryConnectionTesting => 'Testing connection...';

  @override
  String get queryConnectionSuccess => 'Connection established successfully';

  @override
  String get queryConnectionFailure => 'Connection failed';

  @override
  String get queryCancelledByUser => 'Query cancelled by user';

  @override
  String get queryStreamingErrorPrefix => 'Streaming error';

  @override
  String get queryStreamingMode => 'Streaming mode';

  @override
  String get querySqlHandlingModePreserve => 'Preserve SQL';

  @override
  String get querySqlHandlingModePreserveHint =>
      'Runs SQL exactly as sent, without pagination rewrite';

  @override
  String get queryPlaygroundHintLastRunPreserve =>
      'Last run: SQL preserved (no pagination rewrite by the agent).';

  @override
  String get queryPlaygroundHintLastRunManagedPagination =>
      'Last run: managed pagination — SQL may have been rewritten for the database dialect.';

  @override
  String get queryPlaygroundHintLastRunManaged =>
      'Last run: managed mode — agent limits and adjustments may apply to the SQL.';

  @override
  String get queryPlaygroundHintLastRunStreaming =>
      'Last run: streaming mode — results received as a continuous stream.';

  @override
  String queryPlaygroundStreamingRowCapHint(int max) {
    return 'Display limited to $max rows in streaming (memory). The server-side query was stopped when that limit was reached.';
  }

  @override
  String get queryStreamingModeHint => 'For large datasets (thousands of rows)';

  @override
  String get queryStreamingProgress => 'Processing';

  @override
  String get queryStreamingRows => 'rows';

  @override
  String get queryPaginationPage => 'Page';

  @override
  String get queryPaginationPageSize => 'Rows per page';

  @override
  String get queryPaginationPrevious => 'Previous';

  @override
  String get queryPaginationNext => 'Next';

  @override
  String get queryPaginationShowing => 'Showing';

  @override
  String get queryResultSetLabel => 'Result set';

  @override
  String get queryExecuteGenericError => 'Failed to execute query';

  @override
  String get dashboardDescription =>
      'Monitor your agent status and database connections here.';

  @override
  String get connectionStatusConnected => 'Connected';

  @override
  String get connectionStatusConnecting => 'Connecting...';

  @override
  String get connectionStatusError => 'Connection error';

  @override
  String get connectionStatusDisconnected => 'Disconnected';

  @override
  String get connectionStatusDbConnected => 'DB: connected';

  @override
  String get connectionStatusDbDisconnected => 'DB: disconnected';

  @override
  String get dashboardMetricsTitle => 'ODBC metrics';

  @override
  String get dashboardMetricsQueries => 'Queries executed';

  @override
  String get dashboardMetricsSuccess => 'Success';

  @override
  String get dashboardMetricsErrors => 'Errors';

  @override
  String get dashboardMetricsSuccessRate => 'Success rate';

  @override
  String get dashboardMetricsAvgLatency => 'Average latency';

  @override
  String get dashboardMetricsMaxLatency => 'Maximum latency';

  @override
  String get dashboardMetricsTotalRows => 'Total rows';

  @override
  String get dashboardMetricsPeriod => 'Period';

  @override
  String get dashboardMetricsPeriod1h => 'Last 1 hour';

  @override
  String get dashboardMetricsPeriod24h => 'Last 24 hours';

  @override
  String get dashboardMetricsPeriodAll => 'All time';

  @override
  String get wsLogTitle => 'WebSocket messages';

  @override
  String get wsLogEnabled => 'Enabled';

  @override
  String get wsLogClear => 'Clear';

  @override
  String get wsLogNoMessages => 'No messages yet';

  @override
  String get wsLogAuthChecks => 'Auth checks';

  @override
  String get wsLogAllowed => 'Allowed';

  @override
  String get wsLogDenied => 'Denied';

  @override
  String get wsLogDenialRate => 'Denial rate';

  @override
  String get wsLogP95Latency => 'P95 auth latency';

  @override
  String get wsLogP99Latency => 'P99 auth latency';

  @override
  String get wsLogPreserveSqlDeprecatedUses =>
      'preserve_sql usage (deprecated)';

  @override
  String get odbcDriverNotFound =>
      'The configured ODBC driver was not found on this computer. Review the driver and data source in settings.';

  @override
  String get odbcAuthFailed =>
      'Could not authenticate to the database. Check username, password and permissions.';

  @override
  String get odbcServerUnreachable =>
      'Could not connect to the database server. Check host, port, VPN and network availability.';

  @override
  String get odbcConnectionTimeout =>
      'The connection to the database took longer than expected. Confirm the server is accessible and try again.';

  @override
  String get odbcConnectionFailed =>
      'Could not establish connection to the database.';

  @override
  String get odbcDetailPrefix => 'ODBC detail';
}
