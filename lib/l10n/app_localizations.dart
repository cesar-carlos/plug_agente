import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navDatabaseSettings.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get navDatabaseSettings;

  /// No description provided for @navPlayground.
  ///
  /// In en, this message translates to:
  /// **'Playground'**
  String get navPlayground;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navWebSocketSettings.
  ///
  /// In en, this message translates to:
  /// **'WebSocket connection'**
  String get navWebSocketSettings;

  /// No description provided for @mainDegradedModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Degraded mode active'**
  String get mainDegradedModeTitle;

  /// No description provided for @mainDegradedModeDescription.
  ///
  /// In en, this message translates to:
  /// **'The application is running with limited capabilities:'**
  String get mainDegradedModeDescription;

  /// No description provided for @titlePlayground.
  ///
  /// In en, this message translates to:
  /// **'Playground Database'**
  String get titlePlayground;

  /// No description provided for @titleConfig.
  ///
  /// In en, this message translates to:
  /// **'Settings - Plug Database'**
  String get titleConfig;

  /// No description provided for @modalTitleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get modalTitleSuccess;

  /// No description provided for @modalTitleError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get modalTitleError;

  /// No description provided for @modalTitleAuthError.
  ///
  /// In en, this message translates to:
  /// **'Authentication Error'**
  String get modalTitleAuthError;

  /// No description provided for @modalTitleConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get modalTitleConnectionError;

  /// No description provided for @modalTitleConfigError.
  ///
  /// In en, this message translates to:
  /// **'Configuration Error'**
  String get modalTitleConfigError;

  /// No description provided for @modalTitleConnectionEstablished.
  ///
  /// In en, this message translates to:
  /// **'Connection Established'**
  String get modalTitleConnectionEstablished;

  /// No description provided for @modalTitleDriverNotFound.
  ///
  /// In en, this message translates to:
  /// **'Driver Not Found'**
  String get modalTitleDriverNotFound;

  /// No description provided for @modalTitleConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Connection Successful'**
  String get modalTitleConnectionSuccessful;

  /// No description provided for @modalTitleConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get modalTitleConnectionFailed;

  /// No description provided for @modalTitleConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'Configuration Saved'**
  String get modalTitleConfigSaved;

  /// No description provided for @modalTitleErrorTestingConnection.
  ///
  /// In en, this message translates to:
  /// **'Error Testing Connection'**
  String get modalTitleErrorTestingConnection;

  /// No description provided for @modalTitleErrorVerifyingDriver.
  ///
  /// In en, this message translates to:
  /// **'Error Verifying Driver'**
  String get modalTitleErrorVerifyingDriver;

  /// No description provided for @modalTitleErrorSaving.
  ///
  /// In en, this message translates to:
  /// **'Error Saving'**
  String get modalTitleErrorSaving;

  /// No description provided for @modalTitleConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection Status'**
  String get modalTitleConnectionStatus;

  /// No description provided for @msgAuthenticatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Authenticated successfully!'**
  String get msgAuthenticatedSuccessfully;

  /// No description provided for @msgWebSocketConnectedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Connected to WebSocket server successfully!'**
  String get msgWebSocketConnectedSuccessfully;

  /// No description provided for @msgDatabaseConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Database connection established successfully!'**
  String get msgDatabaseConnectionSuccessful;

  /// No description provided for @msgConfigSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Configuration saved successfully!'**
  String get msgConfigSavedSuccessfully;

  /// No description provided for @msgConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'success'**
  String get msgConnectionSuccessful;

  /// No description provided for @msgOdbcDriverNameRequired.
  ///
  /// In en, this message translates to:
  /// **'ODBC Driver name is required'**
  String get msgOdbcDriverNameRequired;

  /// No description provided for @msgConnectionCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to database. Check credentials and settings.'**
  String get msgConnectionCheckFailed;

  /// No description provided for @btnOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get btnOk;

  /// No description provided for @btnCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get btnCancel;

  /// No description provided for @btnRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get btnRetry;

  /// No description provided for @errorTitleValidation.
  ///
  /// In en, this message translates to:
  /// **'Invalid data'**
  String get errorTitleValidation;

  /// No description provided for @errorTitleNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get errorTitleNetwork;

  /// No description provided for @errorTitleDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database error'**
  String get errorTitleDatabase;

  /// No description provided for @errorTitleServer.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get errorTitleServer;

  /// No description provided for @errorTitleNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorTitleNotFound;

  /// No description provided for @queryNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get queryNoResults;

  /// No description provided for @queryNoResultsMessage.
  ///
  /// In en, this message translates to:
  /// **'Execute a SELECT query to see results here.'**
  String get queryNoResultsMessage;

  /// No description provided for @queryTotalRecords.
  ///
  /// In en, this message translates to:
  /// **'Total records'**
  String get queryTotalRecords;

  /// No description provided for @queryExecutionTime.
  ///
  /// In en, this message translates to:
  /// **'Execution time'**
  String get queryExecutionTime;

  /// No description provided for @queryAffectedRows.
  ///
  /// In en, this message translates to:
  /// **'Affected rows'**
  String get queryAffectedRows;

  /// No description provided for @queryErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Query error'**
  String get queryErrorTitle;

  /// No description provided for @queryErrorShowDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get queryErrorShowDetails;

  /// No description provided for @querySqlLabel.
  ///
  /// In en, this message translates to:
  /// **'SQL query'**
  String get querySqlLabel;

  /// No description provided for @querySqlHint.
  ///
  /// In en, this message translates to:
  /// **'SELECT * FROM table...'**
  String get querySqlHint;

  /// No description provided for @queryActionExecute.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get queryActionExecute;

  /// No description provided for @queryActionTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get queryActionTestConnection;

  /// No description provided for @queryActionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get queryActionClear;

  /// No description provided for @queryActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get queryActionCancel;

  /// No description provided for @queryConnectionStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection status'**
  String get queryConnectionStatusTitle;

  /// No description provided for @queryConnectionTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing connection...'**
  String get queryConnectionTesting;

  /// No description provided for @queryConnectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection established successfully'**
  String get queryConnectionSuccess;

  /// No description provided for @queryConnectionFailure.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get queryConnectionFailure;

  /// No description provided for @queryCancelledByUser.
  ///
  /// In en, this message translates to:
  /// **'Query cancelled by user'**
  String get queryCancelledByUser;

  /// No description provided for @queryStreamingErrorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Streaming error'**
  String get queryStreamingErrorPrefix;

  /// No description provided for @queryStreamingMode.
  ///
  /// In en, this message translates to:
  /// **'Streaming mode'**
  String get queryStreamingMode;

  /// No description provided for @querySqlHandlingModePreserve.
  ///
  /// In en, this message translates to:
  /// **'Preserve SQL'**
  String get querySqlHandlingModePreserve;

  /// No description provided for @querySqlHandlingModePreserveHint.
  ///
  /// In en, this message translates to:
  /// **'Runs SQL exactly as sent, without pagination rewrite'**
  String get querySqlHandlingModePreserveHint;

  /// No description provided for @queryPlaygroundHintLastRunPreserve.
  ///
  /// In en, this message translates to:
  /// **'Last run: SQL preserved (no pagination rewrite by the agent).'**
  String get queryPlaygroundHintLastRunPreserve;

  /// No description provided for @queryPlaygroundHintLastRunManagedPagination.
  ///
  /// In en, this message translates to:
  /// **'Last run: managed pagination — SQL may have been rewritten for the database dialect.'**
  String get queryPlaygroundHintLastRunManagedPagination;

  /// No description provided for @queryPlaygroundHintLastRunManaged.
  ///
  /// In en, this message translates to:
  /// **'Last run: managed mode — agent limits and adjustments may apply to the SQL.'**
  String get queryPlaygroundHintLastRunManaged;

  /// No description provided for @queryPlaygroundHintLastRunStreaming.
  ///
  /// In en, this message translates to:
  /// **'Last run: streaming mode — results received as a continuous stream.'**
  String get queryPlaygroundHintLastRunStreaming;

  /// No description provided for @queryPlaygroundStreamingRowCapHint.
  ///
  /// In en, this message translates to:
  /// **'Display limited to {max} rows in streaming (memory). The server-side query was stopped when that limit was reached.'**
  String queryPlaygroundStreamingRowCapHint(int max);

  /// No description provided for @queryStreamingModeHint.
  ///
  /// In en, this message translates to:
  /// **'For large datasets (thousands of rows)'**
  String get queryStreamingModeHint;

  /// No description provided for @queryStreamingProgress.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get queryStreamingProgress;

  /// No description provided for @queryStreamingRows.
  ///
  /// In en, this message translates to:
  /// **'rows'**
  String get queryStreamingRows;

  /// No description provided for @queryPaginationPage.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get queryPaginationPage;

  /// No description provided for @queryPaginationPageSize.
  ///
  /// In en, this message translates to:
  /// **'Rows per page'**
  String get queryPaginationPageSize;

  /// No description provided for @queryPaginationPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get queryPaginationPrevious;

  /// No description provided for @queryPaginationNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get queryPaginationNext;

  /// No description provided for @queryPaginationShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing'**
  String get queryPaginationShowing;

  /// No description provided for @queryResultSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Result set'**
  String get queryResultSetLabel;

  /// No description provided for @queryExecuteGenericError.
  ///
  /// In en, this message translates to:
  /// **'Failed to execute query'**
  String get queryExecuteGenericError;

  /// No description provided for @dashboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Monitor your agent status and database connections here.'**
  String get dashboardDescription;

  /// No description provided for @connectionStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionStatusConnected;

  /// No description provided for @connectionStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connectionStatusConnecting;

  /// No description provided for @connectionStatusError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get connectionStatusError;

  /// No description provided for @connectionStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get connectionStatusDisconnected;

  /// No description provided for @connectionStatusDbConnected.
  ///
  /// In en, this message translates to:
  /// **'DB: connected'**
  String get connectionStatusDbConnected;

  /// No description provided for @connectionStatusDbDisconnected.
  ///
  /// In en, this message translates to:
  /// **'DB: disconnected'**
  String get connectionStatusDbDisconnected;

  /// No description provided for @dashboardMetricsTitle.
  ///
  /// In en, this message translates to:
  /// **'ODBC metrics'**
  String get dashboardMetricsTitle;

  /// No description provided for @dashboardMetricsQueries.
  ///
  /// In en, this message translates to:
  /// **'Queries executed'**
  String get dashboardMetricsQueries;

  /// No description provided for @dashboardMetricsSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get dashboardMetricsSuccess;

  /// No description provided for @dashboardMetricsErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get dashboardMetricsErrors;

  /// No description provided for @dashboardMetricsSuccessRate.
  ///
  /// In en, this message translates to:
  /// **'Success rate'**
  String get dashboardMetricsSuccessRate;

  /// No description provided for @dashboardMetricsAvgLatency.
  ///
  /// In en, this message translates to:
  /// **'Average latency'**
  String get dashboardMetricsAvgLatency;

  /// No description provided for @dashboardMetricsMaxLatency.
  ///
  /// In en, this message translates to:
  /// **'Maximum latency'**
  String get dashboardMetricsMaxLatency;

  /// No description provided for @dashboardMetricsTotalRows.
  ///
  /// In en, this message translates to:
  /// **'Total rows'**
  String get dashboardMetricsTotalRows;

  /// No description provided for @dashboardMetricsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get dashboardMetricsPeriod;

  /// No description provided for @dashboardMetricsPeriod1h.
  ///
  /// In en, this message translates to:
  /// **'Last 1 hour'**
  String get dashboardMetricsPeriod1h;

  /// No description provided for @dashboardMetricsPeriod24h.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get dashboardMetricsPeriod24h;

  /// No description provided for @dashboardMetricsPeriodAll.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get dashboardMetricsPeriodAll;

  /// No description provided for @wsLogTitle.
  ///
  /// In en, this message translates to:
  /// **'WebSocket messages'**
  String get wsLogTitle;

  /// No description provided for @wsLogEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get wsLogEnabled;

  /// No description provided for @wsLogClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get wsLogClear;

  /// No description provided for @wsLogNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get wsLogNoMessages;

  /// No description provided for @wsLogAuthChecks.
  ///
  /// In en, this message translates to:
  /// **'Auth checks'**
  String get wsLogAuthChecks;

  /// No description provided for @wsLogAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get wsLogAllowed;

  /// No description provided for @wsLogDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get wsLogDenied;

  /// No description provided for @wsLogDenialRate.
  ///
  /// In en, this message translates to:
  /// **'Denial rate'**
  String get wsLogDenialRate;

  /// No description provided for @wsLogP95Latency.
  ///
  /// In en, this message translates to:
  /// **'P95 auth latency'**
  String get wsLogP95Latency;

  /// No description provided for @wsLogP99Latency.
  ///
  /// In en, this message translates to:
  /// **'P99 auth latency'**
  String get wsLogP99Latency;

  /// No description provided for @wsLogPreserveSqlDeprecatedUses.
  ///
  /// In en, this message translates to:
  /// **'preserve_sql usage (deprecated)'**
  String get wsLogPreserveSqlDeprecatedUses;

  /// No description provided for @odbcDriverNotFound.
  ///
  /// In en, this message translates to:
  /// **'The configured ODBC driver was not found on this computer. Review the driver and data source in settings.'**
  String get odbcDriverNotFound;

  /// No description provided for @odbcAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not authenticate to the database. Check username, password and permissions.'**
  String get odbcAuthFailed;

  /// No description provided for @odbcServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the database server. Check host, port, VPN and network availability.'**
  String get odbcServerUnreachable;

  /// No description provided for @odbcConnectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'The connection to the database took longer than expected. Confirm the server is accessible and try again.'**
  String get odbcConnectionTimeout;

  /// No description provided for @odbcConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not establish connection to the database.'**
  String get odbcConnectionFailed;

  /// No description provided for @odbcDetailPrefix.
  ///
  /// In en, this message translates to:
  /// **'ODBC detail'**
  String get odbcDetailPrefix;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
