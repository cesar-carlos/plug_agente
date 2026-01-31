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
  String get navPlayground => 'Playground';

  @override
  String get navSettings => 'Settings';

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
  String get dashboardDescription =>
      'Monitor your agent status and database connections here.';
}
