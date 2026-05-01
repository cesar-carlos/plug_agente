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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('pt')];

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

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

  /// No description provided for @navAgentProfile.
  ///
  /// In en, this message translates to:
  /// **'Agent Profile'**
  String get navAgentProfile;

  /// No description provided for @navDatabaseSettings.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get navDatabaseSettings;

  /// No description provided for @navWebSocketSettings.
  ///
  /// In en, this message translates to:
  /// **'WebSocket connection'**
  String get navWebSocketSettings;

  /// No description provided for @formFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'{fieldLabel} is required.'**
  String formFieldRequired(String fieldLabel);

  /// No description provided for @agentProfileLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading agent profile...'**
  String get agentProfileLoading;

  /// No description provided for @agentProfileFormSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Registration details'**
  String get agentProfileFormSectionTitle;

  /// No description provided for @agentProfileSectionIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identification'**
  String get agentProfileSectionIdentity;

  /// No description provided for @agentProfileSectionContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get agentProfileSectionContact;

  /// No description provided for @agentProfileSectionAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get agentProfileSectionAddress;

  /// No description provided for @agentProfileSectionNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get agentProfileSectionNotes;

  /// No description provided for @agentProfileFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get agentProfileFieldName;

  /// No description provided for @agentProfileFieldTradeName.
  ///
  /// In en, this message translates to:
  /// **'Trade name'**
  String get agentProfileFieldTradeName;

  /// No description provided for @agentProfileFieldDocument.
  ///
  /// In en, this message translates to:
  /// **'Tax ID (CPF/CNPJ)'**
  String get agentProfileFieldDocument;

  /// No description provided for @agentProfileFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get agentProfileFieldPhone;

  /// No description provided for @agentProfileFieldMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get agentProfileFieldMobile;

  /// No description provided for @agentProfileFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get agentProfileFieldEmail;

  /// No description provided for @agentProfileFieldStreet.
  ///
  /// In en, this message translates to:
  /// **'Street address'**
  String get agentProfileFieldStreet;

  /// No description provided for @agentProfileFieldNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get agentProfileFieldNumber;

  /// No description provided for @agentProfileFieldDistrict.
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get agentProfileFieldDistrict;

  /// No description provided for @agentProfileFieldPostalCode.
  ///
  /// In en, this message translates to:
  /// **'Postal code'**
  String get agentProfileFieldPostalCode;

  /// No description provided for @agentProfileFieldCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get agentProfileFieldCity;

  /// No description provided for @agentProfileFieldState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get agentProfileFieldState;

  /// No description provided for @agentProfileFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get agentProfileFieldNotes;

  /// No description provided for @agentProfileActionLookupCnpj.
  ///
  /// In en, this message translates to:
  /// **'Look up CNPJ'**
  String get agentProfileActionLookupCnpj;

  /// No description provided for @agentProfileActionLookupCep.
  ///
  /// In en, this message translates to:
  /// **'Look up postal code'**
  String get agentProfileActionLookupCep;

  /// No description provided for @agentProfileActionSave.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get agentProfileActionSave;

  /// No description provided for @agentProfileLookupCnpjInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 14-digit CNPJ to look up.'**
  String get agentProfileLookupCnpjInvalid;

  /// No description provided for @agentProfileLookupCepInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 8-digit postal code to look up.'**
  String get agentProfileLookupCepInvalid;

  /// No description provided for @agentProfileValidationMaxLength.
  ///
  /// In en, this message translates to:
  /// **'{fieldLabel} must be at most {maxLength} characters.'**
  String agentProfileValidationMaxLength(String fieldLabel, int maxLength);

  /// No description provided for @agentProfileValidationNotesMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Note must be at most {max} characters.'**
  String agentProfileValidationNotesMaxLength(int max);

  /// No description provided for @agentProfileValidationDocumentInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid CPF/CNPJ.'**
  String get agentProfileValidationDocumentInvalid;

  /// No description provided for @agentProfileValidationPostalCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid postal code. Enter 8 digits.'**
  String get agentProfileValidationPostalCodeInvalid;

  /// No description provided for @agentProfileValidationPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number.'**
  String get agentProfileValidationPhoneInvalid;

  /// No description provided for @agentProfileValidationMobileInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid mobile number.'**
  String get agentProfileValidationMobileInvalid;

  /// No description provided for @agentProfileValidationEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address.'**
  String get agentProfileValidationEmailInvalid;

  /// No description provided for @agentProfileValidationDocumentTypeMismatch.
  ///
  /// In en, this message translates to:
  /// **'Document type does not match the CPF/CNPJ entered.'**
  String get agentProfileValidationDocumentTypeMismatch;

  /// No description provided for @agentProfileValidationDocumentTypeEnum.
  ///
  /// In en, this message translates to:
  /// **'Document type must be cpf or cnpj.'**
  String get agentProfileValidationDocumentTypeEnum;

  /// No description provided for @agentProfileValidationStateInvalid.
  ///
  /// In en, this message translates to:
  /// **'State must be exactly 2 letters.'**
  String get agentProfileValidationStateInvalid;

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

  /// No description provided for @dashboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Monitor your agent status and database connections here.'**
  String get dashboardDescription;

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

  /// No description provided for @agentProfileSaveSuccessLocal.
  ///
  /// In en, this message translates to:
  /// **'Profile saved on this computer.'**
  String get agentProfileSaveSuccessLocal;

  /// No description provided for @agentProfileSaveSuccessSynced.
  ///
  /// In en, this message translates to:
  /// **'Profile saved and synchronized with the server.'**
  String get agentProfileSaveSuccessSynced;

  /// No description provided for @agentProfileHubSavePartialTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved locally'**
  String get agentProfileHubSavePartialTitle;

  /// No description provided for @agentProfileHubSavePartialMessage.
  ///
  /// In en, this message translates to:
  /// **'The profile was saved on this computer, but updating the server failed. Data will be sent on the next connection.\n\nDetail: {errorDetail}'**
  String agentProfileHubSavePartialMessage(String errorDetail);

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
  /// **'Max latency'**
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
  /// **'preserve_sql (deprecated) usage'**
  String get wsLogPreserveSqlDeprecatedUses;

  /// No description provided for @wsLogTabStream.
  ///
  /// In en, this message translates to:
  /// **'Stream'**
  String get wsLogTabStream;

  /// No description provided for @wsLogTabSqlInvestigation.
  ///
  /// In en, this message translates to:
  /// **'SQL'**
  String get wsLogTabSqlInvestigation;

  /// No description provided for @wsSqlInvestigationClear.
  ///
  /// In en, this message translates to:
  /// **'Clear SQL log'**
  String get wsSqlInvestigationClear;

  /// No description provided for @wsSqlInvestigationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No SQL investigation events yet'**
  String get wsSqlInvestigationEmpty;

  /// No description provided for @wsSqlInvestigationKindAuth.
  ///
  /// In en, this message translates to:
  /// **'Authorization denied'**
  String get wsSqlInvestigationKindAuth;

  /// No description provided for @wsSqlInvestigationKindExec.
  ///
  /// In en, this message translates to:
  /// **'Execution error'**
  String get wsSqlInvestigationKindExec;

  /// No description provided for @wsSqlInvestigationRpcId.
  ///
  /// In en, this message translates to:
  /// **'Request ID'**
  String get wsSqlInvestigationRpcId;

  /// No description provided for @wsSqlInvestigationInternalId.
  ///
  /// In en, this message translates to:
  /// **'Internal execution ID'**
  String get wsSqlInvestigationInternalId;

  /// No description provided for @wsSqlInvestigationReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get wsSqlInvestigationReason;

  /// No description provided for @wsSqlInvestigationOriginalSql.
  ///
  /// In en, this message translates to:
  /// **'SQL received'**
  String get wsSqlInvestigationOriginalSql;

  /// No description provided for @wsSqlInvestigationEffectiveSql.
  ///
  /// In en, this message translates to:
  /// **'SQL sent to database'**
  String get wsSqlInvestigationEffectiveSql;

  /// No description provided for @wsSqlInvestigationNotExecuted.
  ///
  /// In en, this message translates to:
  /// **'Not executed on database'**
  String get wsSqlInvestigationNotExecuted;

  /// No description provided for @wsSqlInvestigationError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get wsSqlInvestigationError;

  /// No description provided for @wsSqlInvestigationExecutedInDb.
  ///
  /// In en, this message translates to:
  /// **'Sent to ODBC server'**
  String get wsSqlInvestigationExecutedInDb;

  /// No description provided for @wsSqlInvestigationExecution.
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get wsSqlInvestigationExecution;

  /// No description provided for @wsSqlInvestigationMetaClientId.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get wsSqlInvestigationMetaClientId;

  /// No description provided for @wsSqlInvestigationMetaResource.
  ///
  /// In en, this message translates to:
  /// **'Resource'**
  String get wsSqlInvestigationMetaResource;

  /// No description provided for @wsSqlInvestigationMetaOperation.
  ///
  /// In en, this message translates to:
  /// **'Operation'**
  String get wsSqlInvestigationMetaOperation;

  /// No description provided for @wsSqlInvestigationShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get wsSqlInvestigationShowMore;

  /// No description provided for @wsSqlInvestigationShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get wsSqlInvestigationShowLess;

  /// No description provided for @wsSqlInvestigationCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get wsSqlInvestigationCopy;

  /// No description provided for @wsSqlInvestigationCopyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy SQL to clipboard'**
  String get wsSqlInvestigationCopyTooltip;

  /// No description provided for @wsSqlInvestigationClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear the SQL investigation event list'**
  String get wsSqlInvestigationClearTooltip;

  /// No description provided for @wsLogClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear WebSocket message log'**
  String get wsLogClearTooltip;

  /// No description provided for @wsLogToggleEnabledTooltip.
  ///
  /// In en, this message translates to:
  /// **'Enable or pause WebSocket message capture'**
  String get wsLogToggleEnabledTooltip;

  /// No description provided for @mainDegradedModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Degraded mode active'**
  String get mainDegradedModeTitle;

  /// No description provided for @mainDegradedModeDescription.
  ///
  /// In en, this message translates to:
  /// **'The app is running with limited features:'**
  String get mainDegradedModeDescription;

  /// No description provided for @playgroundDescription.
  ///
  /// In en, this message translates to:
  /// **'Write SQL queries, test the connection, and watch results in real time.'**
  String get playgroundDescription;

  /// No description provided for @playgroundShortcutExecute.
  ///
  /// In en, this message translates to:
  /// **'F5 or Ctrl+Enter to execute'**
  String get playgroundShortcutExecute;

  /// No description provided for @playgroundShortcutTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+Shift+C to test connection'**
  String get playgroundShortcutTestConnection;

  /// No description provided for @playgroundShortcutClear.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+L to clear the editor'**
  String get playgroundShortcutClear;

  /// No description provided for @queryErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Query error'**
  String get queryErrorTitle;

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

  /// No description provided for @formDropdownSelectPrefix.
  ///
  /// In en, this message translates to:
  /// **'Select '**
  String get formDropdownSelectPrefix;

  /// No description provided for @queryConnectionStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection status'**
  String get queryConnectionStatusTitle;

  /// No description provided for @queryValidationEmpty.
  ///
  /// In en, this message translates to:
  /// **'The query cannot be empty'**
  String get queryValidationEmpty;

  /// No description provided for @queryValidationConnectionStringEmpty.
  ///
  /// In en, this message translates to:
  /// **'The connection string cannot be empty'**
  String get queryValidationConnectionStringEmpty;

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

  /// No description provided for @queryPlaygroundStreamingRowCapHint.
  ///
  /// In en, this message translates to:
  /// **'Display limited to {max} rows in streaming (memory). The server query was stopped when this limit was reached.'**
  String queryPlaygroundStreamingRowCapHint(int max);

  /// No description provided for @queryPlaygroundHintLastRunPreserve.
  ///
  /// In en, this message translates to:
  /// **'Last run: SQL preserved (no pagination rewrite by the agent).'**
  String get queryPlaygroundHintLastRunPreserve;

  /// No description provided for @queryPlaygroundHintLastRunManagedPagination.
  ///
  /// In en, this message translates to:
  /// **'Last run: managed pagination — SQL may have been rewritten for your database dialect.'**
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
  /// **'Execute'**
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

  /// No description provided for @querySqlHandlingModePreserve.
  ///
  /// In en, this message translates to:
  /// **'Preserve SQL'**
  String get querySqlHandlingModePreserve;

  /// No description provided for @querySqlHandlingModePreserveHint.
  ///
  /// In en, this message translates to:
  /// **'Runs the SQL exactly as sent, without pagination rewrite'**
  String get querySqlHandlingModePreserveHint;

  /// No description provided for @queryStreamingMode.
  ///
  /// In en, this message translates to:
  /// **'Streaming mode'**
  String get queryStreamingMode;

  /// No description provided for @queryStreamingModeHint.
  ///
  /// In en, this message translates to:
  /// **'For large datasets (thousands of rows)'**
  String get queryStreamingModeHint;

  /// No description provided for @queryErrorShowDetails.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get queryErrorShowDetails;

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

  /// No description provided for @btnRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get btnRetry;

  /// No description provided for @queryExecuteUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Failed to execute the query'**
  String get queryExecuteUnexpectedError;

  /// No description provided for @odbcDriverNotFoundTest.
  ///
  /// In en, this message translates to:
  /// **'ODBC driver \"{driverName}\" was not found. Make sure it is installed before testing the connection.'**
  String odbcDriverNotFoundTest(String driverName);

  /// No description provided for @odbcDriverNotFoundSave.
  ///
  /// In en, this message translates to:
  /// **'ODBC driver \"{driverName}\" was not found. Make sure it is installed before saving the configuration.'**
  String odbcDriverNotFoundSave(String driverName);

  /// No description provided for @configTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get configTabGeneral;

  /// No description provided for @configTabWebSocket.
  ///
  /// In en, this message translates to:
  /// **'WebSocket'**
  String get configTabWebSocket;

  /// No description provided for @configLastUpdateNever.
  ///
  /// In en, this message translates to:
  /// **'Never checked'**
  String get configLastUpdateNever;

  /// No description provided for @configUpdatesChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates...'**
  String get configUpdatesChecking;

  /// No description provided for @configLastUpdatePrefix.
  ///
  /// In en, this message translates to:
  /// **'Last check: '**
  String get configLastUpdatePrefix;

  /// No description provided for @configUpdatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'A new version is available. Follow the instructions to update.'**
  String get configUpdatesAvailable;

  /// No description provided for @configUpdatesNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'You are already on the latest version.'**
  String get configUpdatesNotAvailable;

  /// No description provided for @configUpdatesNotAvailableHint.
  ///
  /// In en, this message translates to:
  /// **'If you just published a new version, wait up to 5 minutes and try again.'**
  String get configUpdatesNotAvailableHint;

  /// No description provided for @configAutoUpdateNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Auto-update is not configured. Set AUTO_UPDATE_FEED_URL to a Sparkle feed (.xml).'**
  String get configAutoUpdateNotConfigured;

  /// No description provided for @configAutoUpdateOfficialFeedExpected.
  ///
  /// In en, this message translates to:
  /// **'Official feed expected: {url}'**
  String configAutoUpdateOfficialFeedExpected(String url);

  /// No description provided for @configAutoUpdateNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Auto-update is not supported in this run mode.'**
  String get configAutoUpdateNotSupported;

  /// No description provided for @configUpdateTechnicalNoData.
  ///
  /// In en, this message translates to:
  /// **'No technical data for this check.'**
  String get configUpdateTechnicalNoData;

  /// No description provided for @configUpdateTechnicalTitle.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get configUpdateTechnicalTitle;

  /// No description provided for @configUpdateTechnicalCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get configUpdateTechnicalCurrentVersion;

  /// No description provided for @configUpdateTechnicalCheckedAt.
  ///
  /// In en, this message translates to:
  /// **'Checked at'**
  String get configUpdateTechnicalCheckedAt;

  /// No description provided for @configUpdateTechnicalConfiguredFeed.
  ///
  /// In en, this message translates to:
  /// **'Configured feed'**
  String get configUpdateTechnicalConfiguredFeed;

  /// No description provided for @configUpdateTechnicalRequestedFeed.
  ///
  /// In en, this message translates to:
  /// **'Requested feed'**
  String get configUpdateTechnicalRequestedFeed;

  /// No description provided for @configUpdateTechnicalOfficialFeedYes.
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get configUpdateTechnicalOfficialFeedYes;

  /// No description provided for @configUpdateTechnicalOfficialFeedNo.
  ///
  /// In en, this message translates to:
  /// **'no'**
  String get configUpdateTechnicalOfficialFeedNo;

  /// No description provided for @configUpdateTechnicalOfficialFeed.
  ///
  /// In en, this message translates to:
  /// **'Official feed'**
  String get configUpdateTechnicalOfficialFeed;

  /// No description provided for @configUpdateTechnicalFeedItemCount.
  ///
  /// In en, this message translates to:
  /// **'Items in feed'**
  String get configUpdateTechnicalFeedItemCount;

  /// No description provided for @configUpdateTechnicalRemoteVersion.
  ///
  /// In en, this message translates to:
  /// **'Remote version'**
  String get configUpdateTechnicalRemoteVersion;

  /// No description provided for @configUpdateTechnicalUpdaterError.
  ///
  /// In en, this message translates to:
  /// **'Updater error'**
  String get configUpdateTechnicalUpdaterError;

  /// No description provided for @configUpdateTechnicalAppcastError.
  ///
  /// In en, this message translates to:
  /// **'Error reading appcast'**
  String get configUpdateTechnicalAppcastError;

  /// No description provided for @gsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get gsSectionAppearance;

  /// No description provided for @gsToggleDarkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get gsToggleDarkTheme;

  /// No description provided for @gsSectionSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get gsSectionSystem;

  /// No description provided for @gsToggleStartWithWindows.
  ///
  /// In en, this message translates to:
  /// **'Start with Windows'**
  String get gsToggleStartWithWindows;

  /// No description provided for @gsToggleStartMinimized.
  ///
  /// In en, this message translates to:
  /// **'Start minimized'**
  String get gsToggleStartMinimized;

  /// No description provided for @gsToggleMinimizeToTray.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray'**
  String get gsToggleMinimizeToTray;

  /// No description provided for @gsToggleCloseToTray.
  ///
  /// In en, this message translates to:
  /// **'Close to tray'**
  String get gsToggleCloseToTray;

  /// No description provided for @gsSectionUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get gsSectionUpdates;

  /// No description provided for @gsCheckUpdatesWithDate.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get gsCheckUpdatesWithDate;

  /// No description provided for @gsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get gsSectionAbout;

  /// No description provided for @gsLabelVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get gsLabelVersion;

  /// No description provided for @gsLabelLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get gsLabelLicense;

  /// No description provided for @gsLicenseMit.
  ///
  /// In en, this message translates to:
  /// **'MIT License'**
  String get gsLicenseMit;

  /// No description provided for @gsButtonOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get gsButtonOpenSettings;

  /// No description provided for @gsErrorStartupToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change startup configuration'**
  String get gsErrorStartupToggleFailed;

  /// No description provided for @gsErrorStartupServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Startup configuration is not available in this environment'**
  String get gsErrorStartupServiceUnavailable;

  /// No description provided for @gsErrorStartupOpenSystemSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open system settings'**
  String get gsErrorStartupOpenSystemSettingsFailed;

  /// Combines the translated error message with an optional technical detail.
  ///
  /// In en, this message translates to:
  /// **'{message}: {detail}'**
  String gsErrorWithDetail(String message, String detail);

  /// No description provided for @gsStartupEnabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'App will start with Windows'**
  String get gsStartupEnabledSuccess;

  /// No description provided for @gsStartupDisabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'App will not start with Windows anymore'**
  String get gsStartupDisabledSuccess;

  /// No description provided for @diagnosticsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced diagnostics'**
  String get diagnosticsSectionTitle;

  /// No description provided for @diagnosticsWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Sensitive data in logs'**
  String get diagnosticsWarningTitle;

  /// No description provided for @diagnosticsWarningBody.
  ///
  /// In en, this message translates to:
  /// **'The options below may log SQL or technical details in the application logs. Use only for debugging and disable in production when handling personal data or secrets.'**
  String get diagnosticsWarningBody;

  /// No description provided for @diagnosticsOdbcPaginatedSqlLogLabel.
  ///
  /// In en, this message translates to:
  /// **'Paginated SQL log (ODBC)'**
  String get diagnosticsOdbcPaginatedSqlLogLabel;

  /// No description provided for @diagnosticsOdbcPaginatedSqlLogDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, the agent logs the final SQL after managed-pagination rewrite (developer log).'**
  String get diagnosticsOdbcPaginatedSqlLogDescription;

  /// No description provided for @diagnosticsHubReconnectSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Hub reconnect (offline recovery)'**
  String get diagnosticsHubReconnectSectionTitle;

  /// No description provided for @diagnosticsHubReconnectMaxTicksLabel.
  ///
  /// In en, this message translates to:
  /// **'Max failed reconnect ticks before giving up'**
  String get diagnosticsHubReconnectMaxTicksLabel;

  /// No description provided for @diagnosticsHubReconnectMaxTicksHint.
  ///
  /// In en, this message translates to:
  /// **'0 keeps retrying indefinitely. Lower values stop sooner with an error.'**
  String get diagnosticsHubReconnectMaxTicksHint;

  /// No description provided for @diagnosticsHubReconnectIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Seconds between reconnect attempts (after burst)'**
  String get diagnosticsHubReconnectIntervalLabel;

  /// No description provided for @diagnosticsHubReconnectIntervalHint.
  ///
  /// In en, this message translates to:
  /// **'Allowed range: 5–86400. Interval changes apply the next time persistent retry starts.'**
  String get diagnosticsHubReconnectIntervalHint;

  /// No description provided for @diagnosticsHubReconnectEnvHint.
  ///
  /// In en, this message translates to:
  /// **'If you clear overrides (Use defaults), values may still come from HUB_PERSISTENT_RETRY_MAX_FAILED_TICKS and HUB_PERSISTENT_RETRY_INTERVAL_SECONDS in the environment file, then built-in defaults.'**
  String get diagnosticsHubReconnectEnvHint;

  /// No description provided for @diagnosticsHubReconnectApply.
  ///
  /// In en, this message translates to:
  /// **'Apply hub retry settings'**
  String get diagnosticsHubReconnectApply;

  /// No description provided for @diagnosticsHubReconnectReset.
  ///
  /// In en, this message translates to:
  /// **'Use defaults'**
  String get diagnosticsHubReconnectReset;

  /// No description provided for @diagnosticsHubReconnectSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'Hub reconnect tuning was saved.'**
  String get diagnosticsHubReconnectSavedMessage;

  /// No description provided for @diagnosticsHubReconnectInvalidMaxTicks.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative whole number.'**
  String get diagnosticsHubReconnectInvalidMaxTicks;

  /// No description provided for @diagnosticsHubReconnectInvalidInterval.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number between 5 and 86400.'**
  String get diagnosticsHubReconnectInvalidInterval;

  /// No description provided for @diagnosticsHubHardReloginEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Enable automatic hard relogin fallback'**
  String get diagnosticsHubHardReloginEnabledLabel;

  /// No description provided for @diagnosticsHubHardReloginEnabledDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, after repeated reconnect failures the agent will attempt logout, login with saved credentials, and then reconnect the socket.'**
  String get diagnosticsHubHardReloginEnabledDescription;

  /// No description provided for @diagnosticsHubHardReloginThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Failed reconnect attempts before hard relogin'**
  String get diagnosticsHubHardReloginThresholdLabel;

  /// No description provided for @diagnosticsHubHardReloginThresholdHint.
  ///
  /// In en, this message translates to:
  /// **'Allowed range: 1-20. Lower values escalate sooner.'**
  String get diagnosticsHubHardReloginThresholdHint;

  /// No description provided for @diagnosticsHubHardReloginInvalidThreshold.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number between 1 and 20.'**
  String get diagnosticsHubHardReloginInvalidThreshold;

  /// No description provided for @msgServerUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Server URL is required'**
  String get msgServerUrlRequired;

  /// No description provided for @msgAgentIdRequired.
  ///
  /// In en, this message translates to:
  /// **'Agent ID is required'**
  String get msgAgentIdRequired;

  /// No description provided for @msgAuthCredentialsRequired.
  ///
  /// In en, this message translates to:
  /// **'Username and password are required'**
  String get msgAuthCredentialsRequired;

  /// No description provided for @msgLoginRequiredBeforeConnect.
  ///
  /// In en, this message translates to:
  /// **'Sign in before connecting to the hub'**
  String get msgLoginRequiredBeforeConnect;

  /// No description provided for @msgRpcInvalidRequest.
  ///
  /// In en, this message translates to:
  /// **'Invalid request. Review the data sent.'**
  String get msgRpcInvalidRequest;

  /// No description provided for @msgRpcMethodNotFound.
  ///
  /// In en, this message translates to:
  /// **'Method not supported by this version of the agent.'**
  String get msgRpcMethodNotFound;

  /// No description provided for @msgRpcAuthenticationFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Get a new token and try again.'**
  String get msgRpcAuthenticationFailed;

  /// No description provided for @msgRpcUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to execute this operation.'**
  String get msgRpcUnauthorized;

  /// No description provided for @msgRpcTimeout.
  ///
  /// In en, this message translates to:
  /// **'The operation exceeded the time limit. Try again.'**
  String get msgRpcTimeout;

  /// No description provided for @msgRpcInvalidPayload.
  ///
  /// In en, this message translates to:
  /// **'Failed to process the request data.'**
  String get msgRpcInvalidPayload;

  /// No description provided for @msgRpcNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Connection to the hub was lost. Try again.'**
  String get msgRpcNetworkError;

  /// No description provided for @msgRpcRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests in a short time. Wait and try again.'**
  String get msgRpcRateLimited;

  /// No description provided for @msgRpcReplayDetected.
  ///
  /// In en, this message translates to:
  /// **'Duplicate request detected. Generate a new ID and try again.'**
  String get msgRpcReplayDetected;

  /// No description provided for @msgRpcSqlValidationFailed.
  ///
  /// In en, this message translates to:
  /// **'Invalid SQL command. Review the query sent.'**
  String get msgRpcSqlValidationFailed;

  /// No description provided for @msgRpcSqlExecutionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to execute the SQL command.'**
  String get msgRpcSqlExecutionFailed;

  /// No description provided for @msgRpcConnectionPoolExhausted.
  ///
  /// In en, this message translates to:
  /// **'Connection limit reached. Wait and try again.'**
  String get msgRpcConnectionPoolExhausted;

  /// No description provided for @msgRpcResultTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Result too large. Apply filters and try again.'**
  String get msgRpcResultTooLarge;

  /// No description provided for @msgRpcDatabaseConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the database.'**
  String get msgRpcDatabaseConnectionFailed;

  /// No description provided for @msgRpcInvalidDatabaseConfig.
  ///
  /// In en, this message translates to:
  /// **'Invalid database configuration. Review the connection settings.'**
  String get msgRpcInvalidDatabaseConfig;

  /// No description provided for @msgRpcExecutionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Execution not found. It may have finished or never started.'**
  String get msgRpcExecutionNotFound;

  /// No description provided for @msgRpcExecutionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Execution cancelled by the user.'**
  String get msgRpcExecutionCancelled;

  /// No description provided for @msgRpcInternalError.
  ///
  /// In en, this message translates to:
  /// **'Internal failure processing the request.'**
  String get msgRpcInternalError;

  /// No description provided for @tabWebSocketConnection.
  ///
  /// In en, this message translates to:
  /// **'WebSocket connection'**
  String get tabWebSocketConnection;

  /// No description provided for @tabClientTokenAuthorization.
  ///
  /// In en, this message translates to:
  /// **'Client token authorization'**
  String get tabClientTokenAuthorization;

  /// No description provided for @tabWebSocketDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get tabWebSocketDiagnostics;

  /// No description provided for @wsSectionConnection.
  ///
  /// In en, this message translates to:
  /// **'WebSocket connection'**
  String get wsSectionConnection;

  /// No description provided for @wsSectionOptionalAuth.
  ///
  /// In en, this message translates to:
  /// **'Authentication (optional)'**
  String get wsSectionOptionalAuth;

  /// No description provided for @wsFieldServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get wsFieldServerUrl;

  /// No description provided for @wsFieldAgentId.
  ///
  /// In en, this message translates to:
  /// **'Agent ID'**
  String get wsFieldAgentId;

  /// No description provided for @wsFieldUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get wsFieldUsername;

  /// No description provided for @wsHintServerUrl.
  ///
  /// In en, this message translates to:
  /// **'https://api.example.com'**
  String get wsHintServerUrl;

  /// No description provided for @wsHintAgentId.
  ///
  /// In en, this message translates to:
  /// **'Generated automatically (read-only)'**
  String get wsHintAgentId;

  /// No description provided for @wsHintUsername.
  ///
  /// In en, this message translates to:
  /// **'Username for authentication'**
  String get wsHintUsername;

  /// No description provided for @wsHintPassword.
  ///
  /// In en, this message translates to:
  /// **'Password for authentication'**
  String get wsHintPassword;

  /// No description provided for @wsButtonAuthenticating.
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get wsButtonAuthenticating;

  /// No description provided for @wsButtonLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get wsButtonLogout;

  /// No description provided for @wsButtonLogin.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get wsButtonLogin;

  /// No description provided for @wsButtonDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get wsButtonDisconnect;

  /// No description provided for @wsButtonConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get wsButtonConnect;

  /// No description provided for @wsButtonSaveConfig.
  ///
  /// In en, this message translates to:
  /// **'Save configuration'**
  String get wsButtonSaveConfig;

  /// No description provided for @wsSectionOutboundCompression.
  ///
  /// In en, this message translates to:
  /// **'Outbound compression (agent → hub)'**
  String get wsSectionOutboundCompression;

  /// No description provided for @wsFieldOutboundCompressionMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get wsFieldOutboundCompressionMode;

  /// No description provided for @wsOutboundCompressionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get wsOutboundCompressionOff;

  /// No description provided for @wsOutboundCompressionGzip.
  ///
  /// In en, this message translates to:
  /// **'Always GZIP'**
  String get wsOutboundCompressionGzip;

  /// No description provided for @wsOutboundCompressionAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get wsOutboundCompressionAuto;

  /// No description provided for @wsOutboundCompressionDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatic: above the negotiated limit, the agent compresses with GZIP only if the result is smaller than JSON in UTF-8 (saves CPU and traffic on low-compressibility data).'**
  String get wsOutboundCompressionDescription;

  /// No description provided for @wsSectionClientTokenPolicy.
  ///
  /// In en, this message translates to:
  /// **'Client token policy (RPC)'**
  String get wsSectionClientTokenPolicy;

  /// No description provided for @wsFieldClientTokenPolicyIntrospection.
  ///
  /// In en, this message translates to:
  /// **'Allow client_token.getPolicy introspection'**
  String get wsFieldClientTokenPolicyIntrospection;

  /// No description provided for @wsClientTokenPolicyIntrospectionDescription.
  ///
  /// In en, this message translates to:
  /// **'When disabled, the hub cannot call client_token.getPolicy to read permission metadata; SQL authorization with client_token is unaffected.'**
  String get wsClientTokenPolicyIntrospectionDescription;

  /// No description provided for @dbSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Database configuration'**
  String get dbSectionTitle;

  /// No description provided for @dbFieldDatabaseDriver.
  ///
  /// In en, this message translates to:
  /// **'Database driver'**
  String get dbFieldDatabaseDriver;

  /// No description provided for @dbFieldOdbcDriverName.
  ///
  /// In en, this message translates to:
  /// **'ODBC driver name'**
  String get dbFieldOdbcDriverName;

  /// No description provided for @dbFieldHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get dbFieldHost;

  /// No description provided for @dbHintHost.
  ///
  /// In en, this message translates to:
  /// **'localhost'**
  String get dbHintHost;

  /// No description provided for @dbFieldPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get dbFieldPort;

  /// No description provided for @dbHintPort.
  ///
  /// In en, this message translates to:
  /// **'1433'**
  String get dbHintPort;

  /// No description provided for @dbFieldDatabaseName.
  ///
  /// In en, this message translates to:
  /// **'Database name'**
  String get dbFieldDatabaseName;

  /// No description provided for @dbHintDatabaseName.
  ///
  /// In en, this message translates to:
  /// **'Database name'**
  String get dbHintDatabaseName;

  /// No description provided for @dbFieldUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get dbFieldUsername;

  /// No description provided for @dbHintUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get dbHintUsername;

  /// No description provided for @dbHintPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get dbHintPassword;

  /// No description provided for @dbButtonTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test database connection'**
  String get dbButtonTestConnection;

  /// No description provided for @dbTabDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get dbTabDatabase;

  /// No description provided for @dbTabAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get dbTabAdvanced;

  /// No description provided for @odbcErrorPoolRange.
  ///
  /// In en, this message translates to:
  /// **'Pool size must be between 1 and 20'**
  String get odbcErrorPoolRange;

  /// No description provided for @odbcErrorLoginTimeoutRange.
  ///
  /// In en, this message translates to:
  /// **'Login timeout must be between 1 and 120 seconds'**
  String get odbcErrorLoginTimeoutRange;

  /// No description provided for @odbcErrorBufferRange.
  ///
  /// In en, this message translates to:
  /// **'Result buffer must be between 8 and 128 MB'**
  String get odbcErrorBufferRange;

  /// No description provided for @odbcErrorChunkRange.
  ///
  /// In en, this message translates to:
  /// **'Streaming chunk must be between 64 and 8192 KB'**
  String get odbcErrorChunkRange;

  /// No description provided for @odbcErrorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save advanced settings. Try again.'**
  String get odbcErrorSaveFailed;

  /// No description provided for @odbcSuccessAppliedNow.
  ///
  /// In en, this message translates to:
  /// **'Pool, timeout and streaming settings were saved and apply to new connections.'**
  String get odbcSuccessAppliedNow;

  /// No description provided for @odbcSuccessAppliedGradually.
  ///
  /// In en, this message translates to:
  /// **'Pool, timeout and streaming settings were saved. New options apply gradually to new connections.'**
  String get odbcSuccessAppliedGradually;

  /// No description provided for @odbcSuccessPoolModeRestartAppend.
  ///
  /// In en, this message translates to:
  /// **' Restart the app for the ODBC pool mode change to take effect.'**
  String get odbcSuccessPoolModeRestartAppend;

  /// No description provided for @odbcModalTitleSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get odbcModalTitleSaved;

  /// No description provided for @odbcSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection pool and timeouts'**
  String get odbcSectionTitle;

  /// No description provided for @odbcBlockPool.
  ///
  /// In en, this message translates to:
  /// **'Connection pool'**
  String get odbcBlockPool;

  /// No description provided for @odbcBlockPoolDescription.
  ///
  /// In en, this message translates to:
  /// **'Multiple connections are reused automatically. Improves performance under high concurrency.'**
  String get odbcBlockPoolDescription;

  /// No description provided for @odbcFieldPoolSize.
  ///
  /// In en, this message translates to:
  /// **'Maximum pool size'**
  String get odbcFieldPoolSize;

  /// No description provided for @odbcHintPoolSize.
  ///
  /// In en, this message translates to:
  /// **'4'**
  String get odbcHintPoolSize;

  /// No description provided for @odbcFieldNativePool.
  ///
  /// In en, this message translates to:
  /// **'Native ODBC pool (experimental)'**
  String get odbcFieldNativePool;

  /// No description provided for @odbcTextNativePoolHelp.
  ///
  /// In en, this message translates to:
  /// **'Off by default: each query uses a dedicated connection with the configured buffer (more stable). Enable only to test performance or when the driver/package handles buffers in the native pool. Restart the app after changing for it to take effect.'**
  String get odbcTextNativePoolHelp;

  /// No description provided for @odbcFieldNativePoolCheckoutValidation.
  ///
  /// In en, this message translates to:
  /// **'Validate connection when checking out from native pool'**
  String get odbcFieldNativePoolCheckoutValidation;

  /// No description provided for @odbcTextNativePoolCheckoutValidationHelp.
  ///
  /// In en, this message translates to:
  /// **'On by default. Disable only for benchmarks or advanced tuning when comparing native pool checkout validation cost.'**
  String get odbcTextNativePoolCheckoutValidationHelp;

  /// No description provided for @odbcBlockTimeouts.
  ///
  /// In en, this message translates to:
  /// **'Timeouts'**
  String get odbcBlockTimeouts;

  /// No description provided for @odbcFieldLoginTimeout.
  ///
  /// In en, this message translates to:
  /// **'Login timeout (seconds)'**
  String get odbcFieldLoginTimeout;

  /// No description provided for @odbcHintLoginTimeout.
  ///
  /// In en, this message translates to:
  /// **'30'**
  String get odbcHintLoginTimeout;

  /// No description provided for @odbcFieldResultBuffer.
  ///
  /// In en, this message translates to:
  /// **'Result buffer (MB)'**
  String get odbcFieldResultBuffer;

  /// No description provided for @odbcHintResultBuffer.
  ///
  /// In en, this message translates to:
  /// **'32'**
  String get odbcHintResultBuffer;

  /// No description provided for @odbcTextResultBufferHelp.
  ///
  /// In en, this message translates to:
  /// **'Maximum in-memory buffer size for query results. Increasing may improve performance for large queries.'**
  String get odbcTextResultBufferHelp;

  /// No description provided for @odbcBlockStreaming.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get odbcBlockStreaming;

  /// No description provided for @odbcFieldChunkSize.
  ///
  /// In en, this message translates to:
  /// **'Chunk size (KB)'**
  String get odbcFieldChunkSize;

  /// No description provided for @odbcHintChunkSize.
  ///
  /// In en, this message translates to:
  /// **'1024'**
  String get odbcHintChunkSize;

  /// No description provided for @odbcTextStreamingHelp.
  ///
  /// In en, this message translates to:
  /// **'Chunk size sent to the UI during streaming queries. Larger values reduce update events and may improve throughput.'**
  String get odbcTextStreamingHelp;

  /// No description provided for @odbcTextQuickRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Quick recommendation:'**
  String get odbcTextQuickRecommendation;

  /// No description provided for @odbcTextQuickRecommendationItems.
  ///
  /// In en, this message translates to:
  /// **'• 256–512 KB: more frequent visual feedback\n• 1024 KB: general balance (default)\n• 2048–4096 KB: higher throughput for large datasets'**
  String get odbcTextQuickRecommendationItems;

  /// No description provided for @odbcTextChunkWarning.
  ///
  /// In en, this message translates to:
  /// **'If the UI freezes or memory use is high, reduce the chunk size.'**
  String get odbcTextChunkWarning;

  /// No description provided for @odbcButtonRestoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get odbcButtonRestoreDefault;

  /// No description provided for @odbcButtonSaveAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Save advanced settings'**
  String get odbcButtonSaveAdvanced;

  /// No description provided for @ctSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Client token authorization'**
  String get ctSectionTitle;

  /// No description provided for @ctFieldClientId.
  ///
  /// In en, this message translates to:
  /// **'Client ID (auto-generated)'**
  String get ctFieldClientId;

  /// No description provided for @ctFieldAgentIdOptional.
  ///
  /// In en, this message translates to:
  /// **'Agent ID (optional)'**
  String get ctFieldAgentIdOptional;

  /// No description provided for @ctFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get ctFieldName;

  /// No description provided for @ctHintName.
  ///
  /// In en, this message translates to:
  /// **'e.g. Client XYZ — Production'**
  String get ctHintName;

  /// No description provided for @ctFieldPayloadJsonOptional.
  ///
  /// In en, this message translates to:
  /// **'Payload JSON (optional)'**
  String get ctFieldPayloadJsonOptional;

  /// No description provided for @ctHintClientId.
  ///
  /// In en, this message translates to:
  /// **'Generated automatically'**
  String get ctHintClientId;

  /// No description provided for @ctHintAgentId.
  ///
  /// In en, this message translates to:
  /// **'agent-01'**
  String get ctHintAgentId;

  /// No description provided for @ctHintPayloadJson.
  ///
  /// In en, this message translates to:
  /// **'JSON object (e.g. display_name, env)'**
  String get ctHintPayloadJson;

  /// No description provided for @ctFlagAllTables.
  ///
  /// In en, this message translates to:
  /// **'all_tables'**
  String get ctFlagAllTables;

  /// No description provided for @ctFlagAllViews.
  ///
  /// In en, this message translates to:
  /// **'all_views'**
  String get ctFlagAllViews;

  /// No description provided for @ctFlagAllPermissions.
  ///
  /// In en, this message translates to:
  /// **'all_permissions'**
  String get ctFlagAllPermissions;

  /// No description provided for @ctSectionRulesByResource.
  ///
  /// In en, this message translates to:
  /// **'Rules by resource'**
  String get ctSectionRulesByResource;

  /// No description provided for @ctRuleTitlePrefix.
  ///
  /// In en, this message translates to:
  /// **'Rule'**
  String get ctRuleTitlePrefix;

  /// No description provided for @ctButtonAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get ctButtonAddRule;

  /// No description provided for @ctButtonCreateToken.
  ///
  /// In en, this message translates to:
  /// **'Create token'**
  String get ctButtonCreateToken;

  /// No description provided for @ctButtonNewToken.
  ///
  /// In en, this message translates to:
  /// **'New token'**
  String get ctButtonNewToken;

  /// No description provided for @ctButtonRefreshList.
  ///
  /// In en, this message translates to:
  /// **'Refresh list'**
  String get ctButtonRefreshList;

  /// No description provided for @ctButtonAutoRefreshOn.
  ///
  /// In en, this message translates to:
  /// **'Auto refresh: on'**
  String get ctButtonAutoRefreshOn;

  /// No description provided for @ctButtonAutoRefreshOff.
  ///
  /// In en, this message translates to:
  /// **'Auto refresh: off'**
  String get ctButtonAutoRefreshOff;

  /// No description provided for @ctButtonViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get ctButtonViewDetails;

  /// No description provided for @ctButtonCopyClientToken.
  ///
  /// In en, this message translates to:
  /// **'Copy token'**
  String get ctButtonCopyClientToken;

  /// No description provided for @ctTooltipCopyClientToken.
  ///
  /// In en, this message translates to:
  /// **'Copy client token'**
  String get ctTooltipCopyClientToken;

  /// No description provided for @ctInfoClientTokenCopied.
  ///
  /// In en, this message translates to:
  /// **'Client token copied'**
  String get ctInfoClientTokenCopied;

  /// No description provided for @ctInfoClientTokenUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Token unavailable for this record. Create a new token to copy the secret value.'**
  String get ctInfoClientTokenUnavailable;

  /// No description provided for @ctButtonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get ctButtonEdit;

  /// No description provided for @ctButtonClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get ctButtonClearFilters;

  /// No description provided for @ctSectionRegisteredTokens.
  ///
  /// In en, this message translates to:
  /// **'Registered tokens'**
  String get ctSectionRegisteredTokens;

  /// No description provided for @ctMsgNoTokenFound.
  ///
  /// In en, this message translates to:
  /// **'No tokens found.'**
  String get ctMsgNoTokenFound;

  /// No description provided for @ctMsgNoTokenMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No tokens match the applied filters.'**
  String get ctMsgNoTokenMatchFilter;

  /// No description provided for @ctFilterClientId.
  ///
  /// In en, this message translates to:
  /// **'Filter by client ID'**
  String get ctFilterClientId;

  /// No description provided for @ctFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter by status'**
  String get ctFilterStatus;

  /// No description provided for @ctFilterSort.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get ctFilterSort;

  /// No description provided for @ctFilterStatusAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ctFilterStatusAll;

  /// No description provided for @ctFilterStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get ctFilterStatusActive;

  /// No description provided for @ctFilterStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get ctFilterStatusRevoked;

  /// No description provided for @ctSortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get ctSortNewest;

  /// No description provided for @ctSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get ctSortOldest;

  /// No description provided for @ctSortClientAsc.
  ///
  /// In en, this message translates to:
  /// **'Client A-Z'**
  String get ctSortClientAsc;

  /// No description provided for @ctSortClientDesc.
  ///
  /// In en, this message translates to:
  /// **'Client Z-A'**
  String get ctSortClientDesc;

  /// No description provided for @ctMsgTokenCreatedCopyNow.
  ///
  /// In en, this message translates to:
  /// **'Token created successfully (copy and store it now):'**
  String get ctMsgTokenCreatedCopyNow;

  /// No description provided for @ctLabelClient.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get ctLabelClient;

  /// No description provided for @ctLabelId.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get ctLabelId;

  /// No description provided for @ctLabelAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get ctLabelAgent;

  /// No description provided for @ctLabelCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get ctLabelCreatedAt;

  /// No description provided for @ctLabelStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get ctLabelStatus;

  /// No description provided for @ctLabelScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get ctLabelScope;

  /// No description provided for @ctLabelRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get ctLabelRules;

  /// No description provided for @ctLabelPayload.
  ///
  /// In en, this message translates to:
  /// **'Payload'**
  String get ctLabelPayload;

  /// No description provided for @ctScopeAllPermissions.
  ///
  /// In en, this message translates to:
  /// **'All permissions'**
  String get ctScopeAllPermissions;

  /// No description provided for @ctScopeRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted permissions'**
  String get ctScopeRestricted;

  /// No description provided for @ctScopeTables.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get ctScopeTables;

  /// No description provided for @ctScopeViews.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get ctScopeViews;

  /// No description provided for @ctScopeNotInformed.
  ///
  /// In en, this message translates to:
  /// **'not reported by the API'**
  String get ctScopeNotInformed;

  /// No description provided for @ctStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'revoked'**
  String get ctStatusRevoked;

  /// No description provided for @ctStatusActive.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get ctStatusActive;

  /// No description provided for @ctButtonRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get ctButtonRevoked;

  /// No description provided for @ctButtonRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get ctButtonRevoke;

  /// No description provided for @ctButtonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get ctButtonDelete;

  /// No description provided for @ctConfirmRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke token'**
  String get ctConfirmRevokeTitle;

  /// No description provided for @ctConfirmRevokeMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to revoke this token? It will stop working immediately.'**
  String get ctConfirmRevokeMessage;

  /// No description provided for @ctConfirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete token'**
  String get ctConfirmDeleteTitle;

  /// No description provided for @ctConfirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this token? This cannot be undone.'**
  String get ctConfirmDeleteMessage;

  /// No description provided for @ctErrorRuleOrAllPermissionsRequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one valid rule or enable all_permissions.'**
  String get ctErrorRuleOrAllPermissionsRequired;

  /// No description provided for @ctErrorPayloadMustBeJsonObject.
  ///
  /// In en, this message translates to:
  /// **'Payload must be a valid JSON object.'**
  String get ctErrorPayloadMustBeJsonObject;

  /// No description provided for @ctErrorPayloadInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON payload.'**
  String get ctErrorPayloadInvalidJson;

  /// No description provided for @ctPermissionRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get ctPermissionRead;

  /// No description provided for @ctPermissionUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get ctPermissionUpdate;

  /// No description provided for @ctPermissionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get ctPermissionDelete;

  /// No description provided for @ctGridColumnType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get ctGridColumnType;

  /// No description provided for @ctGridColumnResource.
  ///
  /// In en, this message translates to:
  /// **'Resource'**
  String get ctGridColumnResource;

  /// No description provided for @ctGridColumnEffect.
  ///
  /// In en, this message translates to:
  /// **'Effect'**
  String get ctGridColumnEffect;

  /// No description provided for @ctGridColumnPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get ctGridColumnPermissions;

  /// No description provided for @ctGridColumnActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get ctGridColumnActions;

  /// No description provided for @ctNoRulesAdded.
  ///
  /// In en, this message translates to:
  /// **'No rules added. Click \"Add rule\".'**
  String get ctNoRulesAdded;

  /// No description provided for @ctDialogAddRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get ctDialogAddRuleTitle;

  /// No description provided for @ctDialogCreateTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Create client token'**
  String get ctDialogCreateTokenTitle;

  /// No description provided for @ctDialogEditTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit client token'**
  String get ctDialogEditTokenTitle;

  /// No description provided for @ctButtonSaveTokenChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get ctButtonSaveTokenChanges;

  /// No description provided for @ctDialogEditRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get ctDialogEditRuleTitle;

  /// No description provided for @ctDialogSaveRule.
  ///
  /// In en, this message translates to:
  /// **'Save rule'**
  String get ctDialogSaveRule;

  /// No description provided for @ctEditUpdatesTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Changes will apply to the selected token.'**
  String get ctEditUpdatesTokenHint;

  /// No description provided for @ctDialogTokenDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Token details'**
  String get ctDialogTokenDetailsTitle;

  /// No description provided for @ctRuleNoPermission.
  ///
  /// In en, this message translates to:
  /// **'No permissions'**
  String get ctRuleNoPermission;

  /// No description provided for @ctTooltipEditRule.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get ctTooltipEditRule;

  /// No description provided for @ctTooltipDeleteRule.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get ctTooltipDeleteRule;

  /// No description provided for @ctTooltipEditToken.
  ///
  /// In en, this message translates to:
  /// **'Edit token'**
  String get ctTooltipEditToken;

  /// No description provided for @ctErrorRuleResourceRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one resource (schema.name).'**
  String get ctErrorRuleResourceRequired;

  /// No description provided for @ctErrorRulePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one permission for the rule.'**
  String get ctErrorRulePermissionRequired;

  /// No description provided for @ctErrorRuleResourceInvalidChars.
  ///
  /// In en, this message translates to:
  /// **'Invalid resource name: \"{resource}\". Use only letters, numbers, underscores and an optional dot (schema.name).'**
  String ctErrorRuleResourceInvalidChars(String resource);

  /// No description provided for @ctRuleWarnDuplicates.
  ///
  /// In en, this message translates to:
  /// **'The following rules already exist and will be replaced: {resources}. Confirm to proceed.'**
  String ctRuleWarnDuplicates(String resources);

  /// No description provided for @ctDialogConfirmReplace.
  ///
  /// In en, this message translates to:
  /// **'Confirm replacement'**
  String get ctDialogConfirmReplace;

  /// No description provided for @ctRuleImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import .txt'**
  String get ctRuleImportFile;

  /// No description provided for @ctButtonExportRules.
  ///
  /// In en, this message translates to:
  /// **'Export rules'**
  String get ctButtonExportRules;

  /// No description provided for @ctButtonImportRules.
  ///
  /// In en, this message translates to:
  /// **'Import rules'**
  String get ctButtonImportRules;

  /// No description provided for @ctExportRulesDefaultFileName.
  ///
  /// In en, this message translates to:
  /// **'token_rules.txt'**
  String get ctExportRulesDefaultFileName;

  /// No description provided for @ctImportRulesErrorInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Line {line}: \"{content}\" — invalid format. Each line must follow the full pattern: resource;type;effect;permissions (e.g. dbo.customers;table;allow;read).'**
  String ctImportRulesErrorInvalidFormat(int line, String content);

  /// No description provided for @ctImportRulesErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'The file is empty or contains no valid rules.'**
  String get ctImportRulesErrorEmpty;

  /// No description provided for @ctImportRulesErrorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file exceeds the maximum allowed size (512 KB).'**
  String get ctImportRulesErrorFileTooLarge;

  /// No description provided for @ctImportRulesSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 rule imported successfully.} other{{count} rules imported successfully.}}'**
  String ctImportRulesSuccess(int count);

  /// No description provided for @ctRuleImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 rule imported successfully.} other{{count} rules imported successfully.}}'**
  String ctRuleImportSuccess(int count);

  /// No description provided for @ctRuleImportErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'The file is empty.'**
  String get ctRuleImportErrorEmpty;

  /// No description provided for @ctRuleImportErrorNoValidLines.
  ///
  /// In en, this message translates to:
  /// **'No valid lines found in the file.'**
  String get ctRuleImportErrorNoValidLines;

  /// No description provided for @ctRuleImportErrorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file exceeds the maximum allowed size (512 KB).'**
  String get ctRuleImportErrorFileTooLarge;

  /// No description provided for @ctRuleImportErrorLineInvalid.
  ///
  /// In en, this message translates to:
  /// **'Line {line}: \"{content}\" — invalid format. Use schema.name or schema.name;table;allow;read.'**
  String ctRuleImportErrorLineInvalid(int line, String content);

  /// No description provided for @ctRuleFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get ctRuleFieldType;

  /// No description provided for @ctRuleFieldEffect.
  ///
  /// In en, this message translates to:
  /// **'Effect'**
  String get ctRuleFieldEffect;

  /// No description provided for @ctRuleFieldResource.
  ///
  /// In en, this message translates to:
  /// **'Resource (schema.name)'**
  String get ctRuleFieldResource;

  /// No description provided for @ctRuleHintResource.
  ///
  /// In en, this message translates to:
  /// **'dbo.customers; dbo.orders'**
  String get ctRuleHintResource;

  /// No description provided for @ctLabelPayloadColon.
  ///
  /// In en, this message translates to:
  /// **'Payload:'**
  String get ctLabelPayloadColon;

  /// No description provided for @ctLabelRulesColon.
  ///
  /// In en, this message translates to:
  /// **'Rules:'**
  String get ctLabelRulesColon;

  /// No description provided for @ctRuleFieldEffectColon.
  ///
  /// In en, this message translates to:
  /// **'Effect:'**
  String get ctRuleFieldEffectColon;

  /// No description provided for @ctGridColumnPermissionsColon.
  ///
  /// In en, this message translates to:
  /// **'Permissions:'**
  String get ctGridColumnPermissionsColon;

  /// No description provided for @connectionStatusHubConnected.
  ///
  /// In en, this message translates to:
  /// **'Hub: Connected'**
  String get connectionStatusHubConnected;

  /// No description provided for @connectionStatusHubConnecting.
  ///
  /// In en, this message translates to:
  /// **'Hub: Connecting...'**
  String get connectionStatusHubConnecting;

  /// No description provided for @connectionStatusHubReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Hub: Reconnecting...'**
  String get connectionStatusHubReconnecting;

  /// No description provided for @connectionStatusHubError.
  ///
  /// In en, this message translates to:
  /// **'Hub: Connection error'**
  String get connectionStatusHubError;

  /// No description provided for @connectionStatusHubDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Hub: Disconnected'**
  String get connectionStatusHubDisconnected;

  /// No description provided for @msgHubPersistentRetryExhausted.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the hub after many attempts. Check the server URL, network, and sign-in, then tap Connect.'**
  String get msgHubPersistentRetryExhausted;

  /// No description provided for @connectionStatusDatabaseConnected.
  ///
  /// In en, this message translates to:
  /// **'DB: Connected'**
  String get connectionStatusDatabaseConnected;

  /// No description provided for @connectionStatusDatabaseDisconnected.
  ///
  /// In en, this message translates to:
  /// **'DB: Disconnected'**
  String get connectionStatusDatabaseDisconnected;

  /// No description provided for @connectionStatusDatabaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Last successful ODBC check (connection test or query). Not a permanent database session.'**
  String get connectionStatusDatabaseTooltip;

  /// No description provided for @formHintCep.
  ///
  /// In en, this message translates to:
  /// **'00.000-000'**
  String get formHintCep;

  /// No description provided for @formHintPhone.
  ///
  /// In en, this message translates to:
  /// **'(00) 0000-0000'**
  String get formHintPhone;

  /// No description provided for @formHintMobile.
  ///
  /// In en, this message translates to:
  /// **'(00) 00000-0000'**
  String get formHintMobile;

  /// No description provided for @formHintDocument.
  ///
  /// In en, this message translates to:
  /// **'000.000.000-00 or 00.000.000/0000-00'**
  String get formHintDocument;

  /// No description provided for @formHintState.
  ///
  /// In en, this message translates to:
  /// **'SP'**
  String get formHintState;

  /// No description provided for @formValidationEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get formValidationEmailInvalid;

  /// No description provided for @formValidationUrlHttpHttps.
  ///
  /// In en, this message translates to:
  /// **'Enter a URL starting with http:// or https://'**
  String get formValidationUrlHttpHttps;

  /// No description provided for @formValidationCepDigits.
  ///
  /// In en, this message translates to:
  /// **'Postal code must have 8 digits'**
  String get formValidationCepDigits;

  /// No description provided for @formValidationPhoneDigits.
  ///
  /// In en, this message translates to:
  /// **'Phone must have 10 digits (area code + number)'**
  String get formValidationPhoneDigits;

  /// No description provided for @formValidationMobileDigits.
  ///
  /// In en, this message translates to:
  /// **'Mobile must have 11 digits'**
  String get formValidationMobileDigits;

  /// No description provided for @formValidationMobileNineAfterDdd.
  ///
  /// In en, this message translates to:
  /// **'Mobile must start with 9 after the area code'**
  String get formValidationMobileNineAfterDdd;

  /// No description provided for @formValidationDocumentDigits.
  ///
  /// In en, this message translates to:
  /// **'CPF (11) or CNPJ (14) digits'**
  String get formValidationDocumentDigits;

  /// No description provided for @formValidationStateLetters.
  ///
  /// In en, this message translates to:
  /// **'State must be 2 letters'**
  String get formValidationStateLetters;

  /// No description provided for @formFieldLabelPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get formFieldLabelPassword;

  /// No description provided for @formPasswordDefaultHint.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get formPasswordDefaultHint;

  /// No description provided for @formPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'{fieldLabel} is required.'**
  String formPasswordRequired(String fieldLabel);

  /// No description provided for @formNumericInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid value'**
  String get formNumericInvalidValue;

  /// No description provided for @formNumericMinValue.
  ///
  /// In en, this message translates to:
  /// **'Minimum value: {min}'**
  String formNumericMinValue(int min);

  /// No description provided for @formNumericMaxValue.
  ///
  /// In en, this message translates to:
  /// **'Maximum value: {max}'**
  String formNumericMaxValue(int max);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'pt'].contains(locale.languageCode);

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
