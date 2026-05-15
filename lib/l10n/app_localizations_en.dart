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
  String get navAgentProfile => 'Agent Profile';

  @override
  String get navDatabaseSettings => 'Database';

  @override
  String get navWebSocketSettings => 'WebSocket connection';

  @override
  String formFieldRequired(String fieldLabel) {
    return '$fieldLabel is required.';
  }

  @override
  String get agentProfileLoading => 'Loading agent profile...';

  @override
  String get agentProfileFormSectionTitle => 'Registration details';

  @override
  String get agentProfileSectionIdentity => 'Identification';

  @override
  String get agentProfileSectionContact => 'Contact';

  @override
  String get agentProfileSectionAddress => 'Address';

  @override
  String get agentProfileSectionNotes => 'Notes';

  @override
  String get agentProfileFieldName => 'Name';

  @override
  String get agentProfileFieldTradeName => 'Trade name';

  @override
  String get agentProfileFieldDocument => 'Tax ID (CPF/CNPJ)';

  @override
  String get agentProfileFieldPhone => 'Phone';

  @override
  String get agentProfileFieldMobile => 'Mobile';

  @override
  String get agentProfileFieldEmail => 'Email';

  @override
  String get agentProfileFieldStreet => 'Street address';

  @override
  String get agentProfileFieldNumber => 'Number';

  @override
  String get agentProfileFieldDistrict => 'District';

  @override
  String get agentProfileFieldPostalCode => 'Postal code';

  @override
  String get agentProfileFieldCity => 'City';

  @override
  String get agentProfileFieldState => 'State';

  @override
  String get agentProfileFieldNotes => 'Note';

  @override
  String get agentProfileActionLookupCnpj => 'Look up CNPJ';

  @override
  String get agentProfileActionLookupCep => 'Look up postal code';

  @override
  String get agentProfileActionSave => 'Save profile';

  @override
  String get agentProfileLookupCnpjInvalid => 'Enter a valid 14-digit CNPJ to look up.';

  @override
  String get agentProfileLookupCepInvalid => 'Enter a valid 8-digit postal code to look up.';

  @override
  String agentProfileValidationMaxLength(String fieldLabel, int maxLength) {
    return '$fieldLabel must be at most $maxLength characters.';
  }

  @override
  String agentProfileValidationNotesMaxLength(int max) {
    return 'Note must be at most $max characters.';
  }

  @override
  String get agentProfileValidationDocumentInvalid => 'Invalid CPF/CNPJ.';

  @override
  String get agentProfileValidationPostalCodeInvalid => 'Invalid postal code. Enter 8 digits.';

  @override
  String get agentProfileValidationPhoneInvalid => 'Invalid phone number.';

  @override
  String get agentProfileValidationMobileInvalid => 'Invalid mobile number.';

  @override
  String get agentProfileValidationEmailInvalid => 'Invalid email address.';

  @override
  String get agentProfileValidationDocumentTypeMismatch => 'Document type does not match the CPF/CNPJ entered.';

  @override
  String get agentProfileValidationDocumentTypeEnum => 'Document type must be cpf or cnpj.';

  @override
  String get agentProfileValidationStateInvalid => 'State must be exactly 2 letters.';

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
  String get msgWebSocketConnectedSuccessfully => 'Connected to WebSocket server successfully!';

  @override
  String get msgDatabaseConnectionSuccessful => 'Database connection established successfully!';

  @override
  String get msgConfigSavedSuccessfully => 'Configuration saved successfully!';

  @override
  String get msgConnectionSuccessful => 'success';

  @override
  String get msgOdbcDriverNameRequired => 'ODBC Driver name is required';

  @override
  String get msgConnectionCheckFailed => 'Could not connect to database. Check credentials and settings.';

  @override
  String get btnOk => 'OK';

  @override
  String get btnCancel => 'Cancel';

  @override
  String get queryNoResults => 'No results';

  @override
  String get queryNoResultsMessage => 'Execute a SELECT query to see results here.';

  @override
  String get queryTotalRecords => 'Total records';

  @override
  String get queryExecutionTime => 'Execution time';

  @override
  String get queryAffectedRows => 'Affected rows';

  @override
  String get dashboardDescription => 'Monitor your agent status and database connections here.';

  @override
  String get odbcDriverNotFound =>
      'The configured ODBC driver was not found on this computer. Review the driver and data source in settings.';

  @override
  String get odbcAuthFailed => 'Could not authenticate to the database. Check username, password and permissions.';

  @override
  String get odbcServerUnreachable =>
      'Could not connect to the database server. Check host, port, VPN and network availability.';

  @override
  String get odbcConnectionTimeout =>
      'The connection to the database took longer than expected. Confirm the server is accessible and try again.';

  @override
  String get odbcConnectionFailed => 'Could not establish connection to the database.';

  @override
  String get odbcDetailPrefix => 'ODBC detail';

  @override
  String get agentProfileSaveSuccessLocal => 'Profile saved on this computer.';

  @override
  String get agentProfileSaveSuccessSynced => 'Profile saved and synchronized with the server.';

  @override
  String get agentProfileHubSavePartialTitle => 'Saved locally';

  @override
  String agentProfileHubSavePartialMessage(String errorDetail) {
    return 'The profile was saved on this computer, but updating the server failed. Data will be sent on the next connection.\n\nDetail: $errorDetail';
  }

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
  String get dashboardMetricsMaxLatency => 'Max latency';

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
  String get wsLogPreserveSqlDeprecatedUses => 'preserve_sql (deprecated) usage';

  @override
  String get wsLogTabStream => 'Stream';

  @override
  String get wsLogTabSqlInvestigation => 'SQL';

  @override
  String get wsSqlInvestigationClear => 'Clear SQL log';

  @override
  String get wsSqlInvestigationEmpty => 'No SQL investigation events yet';

  @override
  String get wsSqlInvestigationKindAuth => 'Authorization denied';

  @override
  String get wsSqlInvestigationKindExec => 'Execution error';

  @override
  String get wsSqlInvestigationRpcId => 'Request ID';

  @override
  String get wsSqlInvestigationInternalId => 'Internal execution ID';

  @override
  String get wsSqlInvestigationReason => 'Reason';

  @override
  String get wsSqlInvestigationOriginalSql => 'SQL received';

  @override
  String get wsSqlInvestigationEffectiveSql => 'SQL sent to database';

  @override
  String get wsSqlInvestigationNotExecuted => 'Not executed on database';

  @override
  String get wsSqlInvestigationError => 'Error';

  @override
  String get wsSqlInvestigationExecutedInDb => 'Sent to ODBC server';

  @override
  String get wsSqlInvestigationExecution => 'Execution';

  @override
  String get wsSqlInvestigationMetaClientId => 'Client ID';

  @override
  String get wsSqlInvestigationMetaResource => 'Resource';

  @override
  String get wsSqlInvestigationMetaOperation => 'Operation';

  @override
  String get wsSqlInvestigationShowMore => 'Show more';

  @override
  String get wsSqlInvestigationShowLess => 'Show less';

  @override
  String get wsSqlInvestigationCopy => 'Copy';

  @override
  String get wsSqlInvestigationCopyTooltip => 'Copy SQL to clipboard';

  @override
  String get wsSqlInvestigationClearTooltip => 'Clear the SQL investigation event list';

  @override
  String get wsLogClearTooltip => 'Clear WebSocket message log';

  @override
  String get wsLogToggleEnabledTooltip => 'Enable or pause WebSocket message capture';

  @override
  String get mainDegradedModeTitle => 'Degraded mode active';

  @override
  String get mainDegradedModeDescription => 'The app is running with limited features:';

  @override
  String get playgroundDescription => 'Write SQL queries, test the connection, and watch results in real time.';

  @override
  String get playgroundShortcutExecute => 'F5 or Ctrl+Enter to execute';

  @override
  String get playgroundShortcutTestConnection => 'Ctrl+Shift+C to test connection';

  @override
  String get playgroundShortcutClear => 'Ctrl+L to clear the editor';

  @override
  String get queryErrorTitle => 'Query error';

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
  String get formDropdownSelectPrefix => 'Select ';

  @override
  String get queryConnectionStatusTitle => 'Connection status';

  @override
  String get queryValidationEmpty => 'The query cannot be empty';

  @override
  String get queryValidationConnectionStringEmpty => 'The connection string cannot be empty';

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
  String queryPlaygroundStreamingRowCapHint(int max) {
    return 'Display limited to $max rows in streaming (memory). The server query was stopped when this limit was reached.';
  }

  @override
  String get queryPlaygroundHintLastRunPreserve => 'Last run: SQL preserved (no pagination rewrite by the agent).';

  @override
  String get queryPlaygroundHintLastRunManagedPagination =>
      'Last run: managed pagination — SQL may have been rewritten for your database dialect.';

  @override
  String get queryPlaygroundHintLastRunManaged =>
      'Last run: managed mode — agent limits and adjustments may apply to the SQL.';

  @override
  String get queryPlaygroundHintLastRunStreaming =>
      'Last run: streaming mode — results received as a continuous stream.';

  @override
  String get querySqlLabel => 'SQL query';

  @override
  String get querySqlHint => 'SELECT * FROM table...';

  @override
  String get queryActionExecute => 'Execute';

  @override
  String get queryActionTestConnection => 'Test connection';

  @override
  String get queryActionClear => 'Clear';

  @override
  String get queryActionCancel => 'Cancel';

  @override
  String get querySqlHandlingModePreserve => 'Preserve SQL';

  @override
  String get querySqlHandlingModePreserveHint => 'Runs the SQL exactly as sent, without pagination rewrite';

  @override
  String get queryStreamingMode => 'Streaming mode';

  @override
  String get queryStreamingModeHint => 'For large datasets (thousands of rows)';

  @override
  String get queryErrorShowDetails => 'Show details';

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
  String get btnRetry => 'Retry';

  @override
  String get queryExecuteUnexpectedError => 'Failed to execute the query';

  @override
  String odbcDriverNotFoundTest(String driverName) {
    return 'ODBC driver \"$driverName\" was not found. Make sure it is installed before testing the connection.';
  }

  @override
  String odbcDriverNotFoundSave(String driverName) {
    return 'ODBC driver \"$driverName\" was not found. Make sure it is installed before saving the configuration.';
  }

  @override
  String get configTabGeneral => 'General';

  @override
  String get configTabPreferences => 'Preferences';

  @override
  String get configTabUpdatesAbout => 'Updates & about';

  @override
  String get configTabBackup => 'Backup';

  @override
  String get configTabWebSocket => 'WebSocket';

  @override
  String get configBackupSectionTitle => 'Local backup';

  @override
  String get configBackupIntro =>
      'Export or restore the local agent database (configuration) and the global settings file. The archive may contain hub credentials stored in the database. Secrets stored only in Windows secure storage are not included—you may need to sign in again after a restore.';

  @override
  String get configBackupDuplicateNote =>
      'Restoring the same backup on two machines can register the same agent twice. The app checks the hub when possible; if that check fails, you must confirm that you accept the risk.';

  @override
  String get configBackupSingleInstanceNote => 'Do not run two copies of the app against the same global data folder.';

  @override
  String configBackupRestoreDiagnosticsHint(String fileName) {
    return 'If restore fails after the app closes, details are saved as $fileName in the app data folder.';
  }

  @override
  String get configBackupButtonExport => 'Export backup…';

  @override
  String get configBackupButtonRestore => 'Restore from backup…';

  @override
  String get configBackupExporting => 'Exporting backup…';

  @override
  String get configBackupRestoring => 'Preparing restore…';

  @override
  String get configBackupExportSuccessTitle => 'Backup saved';

  @override
  String get configBackupExportSuccessMessage => 'The backup file was created successfully.';

  @override
  String get configBackupRestoreDialogTitle => 'Restore backup';

  @override
  String get configBackupRestoreDialogBody =>
      'This replaces the local database and settings. The application will close—start it again afterward. Current files are copied to .bak before replacement.';

  @override
  String get configBackupRestoreDuplicateWarning =>
      'This agent ID appears connected on the hub. Restoring may duplicate an active session unless the other machine is offline.';

  @override
  String get configBackupRestoreVerifyWarning =>
      'Could not verify whether this agent is already connected (network or expired session). Confirm that no other machine is using this same backup.';

  @override
  String get configBackupRestoreInstallationMismatch =>
      'This backup was created on another installation (different installation ID).';

  @override
  String get configBackupCheckboxAcknowledgeDuplicate =>
      'I confirm the other session is offline or I accept the risk of a duplicate agent.';

  @override
  String get configBackupCheckboxAcknowledgeUncertain =>
      'I understand the hub could not be verified and I accept the risk.';

  @override
  String get configBackupRestoreConfirm => 'Restore and exit';

  @override
  String get configBackupCancel => 'Cancel';

  @override
  String get configBackupErrMissingManifestOrDb => 'The archive is missing manifest or database files.';

  @override
  String get configBackupErrInvalidManifest => 'The backup manifest is invalid.';

  @override
  String get configBackupErrUnsupportedFormat => 'This backup format is not supported.';

  @override
  String get configBackupErrDbVersion => 'Could not read the schema version from the backup database.';

  @override
  String get configBackupErrNewerBackup =>
      'This backup was created with a newer app version. Update the app before restoring.';

  @override
  String get configBackupErrInvalidEntry => 'The archive contains an invalid file entry.';

  @override
  String get configBackupErrExportDbNotFound => 'Local database file was not found.';

  @override
  String get configBackupErrExportZip => 'Failed to build the backup archive.';

  @override
  String get configBackupErrExportWrite => 'Could not write the backup file.';

  @override
  String get configBackupErrExportGeneric => 'Unexpected error while exporting backup.';

  @override
  String get configBackupErrReadZip => 'Could not read the backup file.';

  @override
  String get configBackupErrStageGeneric => 'Failed to read the backup archive.';

  @override
  String get configBackupErrApplyMissingDb => 'Staged database file is missing.';

  @override
  String get configBackupErrApplyWrite => 'Could not apply backup files.';

  @override
  String get configBackupRestoreFailedTitle => 'Restore failed';

  @override
  String get configBackupExportFailedTitle => 'Export failed';

  @override
  String get configBackupRestoreRestartNotice => 'The application will close. Start it again to use the restored data.';

  @override
  String get configBackupRestoreOlderSchemaNote =>
      'This backup uses an older database schema. The app will migrate it on the next start.';

  @override
  String get configLastUpdateNever => 'Never checked';

  @override
  String get configUpdatesChecking => 'Checking for updates...';

  @override
  String get configLastUpdatePrefix => 'Last check: ';

  @override
  String get configLastBackgroundUpdatePrefix => 'Last background check: ';

  @override
  String get configLastAutomaticUpdatePrefix => 'Last automatic check: ';

  @override
  String get configUpdatesAvailable => 'A new version is available. Follow the instructions to update.';

  @override
  String get configUpdatesNotAvailable => 'You are already on the latest version.';

  @override
  String get configUpdatesNotAvailableHint =>
      'If you just published a new version, wait up to 5 minutes and try again.';

  @override
  String get configAutomaticSilentUpdatesToggle => 'Install updates automatically';

  @override
  String get configAutomaticSilentUpdatesDescription =>
      'Downloads, validates, and starts the installer silently. Windows may still request UAC.';

  @override
  String get configAutomaticSilentUpdatesEnabled => 'Automatic update installation enabled.';

  @override
  String get configAutomaticSilentUpdatesDisabled => 'Automatic update installation disabled.';

  @override
  String get configAutomaticSilentUpdatesCheckNow => 'Try automatic update now';

  @override
  String get configAutoUpdateFeedOfficial => 'Feed: official';

  @override
  String get configAutoUpdateFeedCustom => 'Feed: custom';

  @override
  String get configAutoUpdateNotConfigured =>
      'Auto-update is unavailable because the configured feed is invalid. Remove AUTO_UPDATE_FEED_URL to use the official feed, or set it to a Sparkle feed (.xml).';

  @override
  String configAutoUpdateOfficialFeedExpected(String url) {
    return 'Official feed expected: $url';
  }

  @override
  String get configAutoUpdateNotSupported => 'Auto-update is not supported in this run mode.';

  @override
  String get configUpdateTechnicalNoData => 'No technical data for this check.';

  @override
  String get configUpdateTechnicalTitle => 'Technical details';

  @override
  String get configUpdateTechnicalBackgroundTitle => 'Background technical details';

  @override
  String get configUpdateTechnicalAutomaticTitle => 'Automatic update technical details';

  @override
  String get configUpdateTechnicalCurrentVersion => 'Current version';

  @override
  String get configUpdateTechnicalCheckedAt => 'Checked at';

  @override
  String get configUpdateTechnicalConfiguredFeed => 'Configured feed';

  @override
  String get configUpdateTechnicalRequestedFeed => 'Requested feed';

  @override
  String get configUpdateTechnicalOfficialFeedYes => 'yes';

  @override
  String get configUpdateTechnicalOfficialFeedNo => 'no';

  @override
  String get configUpdateTechnicalOfficialFeed => 'Official feed';

  @override
  String get configUpdateTechnicalProbeRequestUrl => 'Probe URL';

  @override
  String get configUpdateTechnicalProbeSucceeded => 'HTTP probe succeeded';

  @override
  String get configUpdateTechnicalCompletionSource => 'Check result';

  @override
  String get configUpdateTechnicalTriggerDurationMs => 'Trigger duration (ms)';

  @override
  String get configUpdateTechnicalTotalDurationMs => 'Total duration (ms)';

  @override
  String get configUpdateTechnicalFeedItemCount => 'Items in feed';

  @override
  String get configUpdateTechnicalRemoteVersion => 'Remote version';

  @override
  String get configUpdateTechnicalAssetName => 'Asset name';

  @override
  String get configUpdateTechnicalAssetUrl => 'Asset URL';

  @override
  String get configUpdateTechnicalAssetSize => 'Asset size';

  @override
  String get configUpdateTechnicalSha256 => 'Expected SHA-256';

  @override
  String get configUpdateTechnicalActualSha256 => 'Actual SHA-256';

  @override
  String get configUpdateTechnicalHashValidationStatus => 'Hash validation';

  @override
  String get configUpdateTechnicalRolloutChannel => 'Update channel';

  @override
  String get configUpdateTechnicalRolloutPercentage => 'Rollout percentage';

  @override
  String get configUpdateTechnicalRolloutBucket => 'Rollout bucket';

  @override
  String get configUpdateTechnicalRolloutEligible => 'Rollout eligible';

  @override
  String get configUpdateTechnicalPendingVersion => 'Pending version';

  @override
  String get configUpdateTechnicalInstallerPath => 'Installer path';

  @override
  String get configUpdateTechnicalInstallerLogPath => 'Installer log';

  @override
  String get configUpdateTechnicalInstallDirectory => 'Install directory';

  @override
  String get configUpdateTechnicalUpdateDirectorySecurity => 'Update directory security';

  @override
  String get configUpdateTechnicalInstallDirectoryWritable => 'Install directory writable';

  @override
  String get configUpdateTechnicalSilentStrategy => 'Silent update strategy';

  @override
  String get configUpdateTechnicalLauncherPath => 'Launcher path';

  @override
  String get configUpdateTechnicalLauncherStatusPath => 'Launcher status';

  @override
  String get configUpdateTechnicalLauncherState => 'Launcher state';

  @override
  String get configUpdateTechnicalAppPid => 'App PID';

  @override
  String get configUpdateTechnicalSignatureStatus => 'Signature status';

  @override
  String get configUpdateTechnicalSignatureRequired => 'Signature required';

  @override
  String get configUpdateTechnicalWaitForAppExitDurationMs => 'Wait for app exit (ms)';

  @override
  String get configUpdateTechnicalNonAdminExitCode => 'Non-admin exit code';

  @override
  String get configUpdateTechnicalNonAdminDurationMs => 'Non-admin duration (ms)';

  @override
  String get configUpdateTechnicalElevatedExitCode => 'Elevated exit code';

  @override
  String get configUpdateTechnicalElevatedDurationMs => 'Elevated duration (ms)';

  @override
  String get configUpdateTechnicalElevatedRetryStarted => 'Elevated retry started';

  @override
  String get configUpdateTechnicalElevatedCancelled => 'Elevated prompt cancelled';

  @override
  String get configUpdateTechnicalAutomaticFailureCount => 'Automatic failure count';

  @override
  String get configUpdateTechnicalAutomaticCooldownUntil => 'Automatic cooldown until';

  @override
  String get configUpdateTechnicalUpdaterError => 'Updater error';

  @override
  String get configUpdateTechnicalAppcastError => 'Error reading appcast';

  @override
  String get configUpdateCompletionSourceUpdateAvailable => 'Update available';

  @override
  String get configUpdateCompletionSourceUpdateNotAvailable => 'No update available';

  @override
  String get configUpdateCompletionSourceUpdaterError => 'Updater returned an error';

  @override
  String get configUpdateCompletionSourceTriggerTimeout => 'Timeout while triggering the updater';

  @override
  String get configUpdateCompletionSourceCompletionTimeout => 'Timeout while waiting for updater completion';

  @override
  String get configUpdateCompletionSourceTriggerFailure => 'Failed to start the update check';

  @override
  String get configUpdateCompletionSourceNotInitialized => 'Auto-update not initialized';

  @override
  String get configUpdateCompletionSourceCircuitOpen => 'Checks paused after repeated timeouts';

  @override
  String get configUpdateCompletionSourceAutomaticDisabled => 'Automatic installation disabled';

  @override
  String get configUpdateCompletionSourceAutomaticPendingCompleted => 'Pending automatic update completed';

  @override
  String get configUpdateCompletionSourceAutomaticPendingFailed => 'Pending automatic update did not complete';

  @override
  String get configUpdateCompletionSourceAutomaticUpdateNotAvailable => 'No automatic update available';

  @override
  String get configUpdateCompletionSourceAutomaticValidationFailure => 'Automatic update validation failed';

  @override
  String get configUpdateCompletionSourceAutomaticDownloadFailure => 'Automatic update download failed';

  @override
  String get configUpdateCompletionSourceAutomaticInstallStarted => 'Automatic installer started';

  @override
  String get configUpdateCompletionSourceAutomaticInstallFailure => 'Automatic installer failed to start';

  @override
  String get configUpdateCompletionSourceAutomaticCooldown => 'Automatic updates paused';

  @override
  String get configUpdateCompletionSourceAutomaticRolloutSkipped => 'Automatic update skipped by rollout';

  @override
  String get configCopyUpdateDiagnostics => 'Copy update diagnostics';

  @override
  String get configUpdateDiagnosticsCopied => 'Update diagnostics copied.';

  @override
  String get gsSectionAppearance => 'Appearance';

  @override
  String get gsToggleDarkTheme => 'Dark theme';

  @override
  String get gsSectionSystem => 'System';

  @override
  String get gsToggleStartWithWindows => 'Start with Windows';

  @override
  String get gsToggleStartMinimized => 'Start minimized';

  @override
  String get gsToggleStartMinimizedNextLaunchHint => 'Applies on the next Windows startup.';

  @override
  String get gsToggleStartMinimizedRequiresTray => 'Requires tray support in this environment.';

  @override
  String get gsToggleMinimizeToTray => 'Minimize to tray';

  @override
  String get gsToggleCloseToTray => 'Close to tray';

  @override
  String get gsSectionUpdates => 'Updates';

  @override
  String get gsCheckUpdatesWithDate => 'Check for updates';

  @override
  String get gsSectionAbout => 'About';

  @override
  String get gsLabelVersion => 'Version';

  @override
  String get gsLabelLicense => 'License';

  @override
  String get gsLicenseMit => 'MIT License';

  @override
  String get gsButtonOpenSettings => 'Open settings';

  @override
  String get gsButtonRepairStartup => 'Repair';

  @override
  String get gsStartupLaunchConfigurationReady => 'Startup entry is ready.';

  @override
  String get gsStartupLaunchConfigurationRepaired => 'Startup entry repaired.';

  @override
  String get gsStartupLaunchConfigurationRepairFailed => 'Startup entry needs repair';

  @override
  String get gsErrorStartupToggleFailed => 'Failed to change startup configuration';

  @override
  String get gsErrorStartupServiceUnavailable => 'Startup configuration is not available in this environment';

  @override
  String get gsErrorStartupOpenSystemSettingsFailed => 'Failed to open system settings';

  @override
  String get gsErrorSettingsPersistenceFailed => 'Failed to save local preference';

  @override
  String gsErrorWithDetail(String message, String detail) {
    return '$message: $detail';
  }

  @override
  String get gsStartupEnabledSuccess => 'App will start with Windows';

  @override
  String get gsStartupDisabledSuccess => 'App will not start with Windows anymore';

  @override
  String get diagnosticsSectionTitle => 'Advanced diagnostics';

  @override
  String get diagnosticsWarningTitle => 'Sensitive data in logs';

  @override
  String get diagnosticsWarningBody =>
      'The options below may log SQL or technical details in the application logs. Use only for debugging and disable in production when handling personal data or secrets.';

  @override
  String get diagnosticsOdbcPaginatedSqlLogLabel => 'Paginated SQL log (ODBC)';

  @override
  String get diagnosticsOdbcPaginatedSqlLogDescription =>
      'When enabled, the agent logs the final SQL after managed-pagination rewrite (developer log).';

  @override
  String get diagnosticsHubReconnectSectionTitle => 'Hub reconnect (offline recovery)';

  @override
  String get diagnosticsHubReconnectMaxTicksLabel => 'Max failed reconnect ticks before giving up';

  @override
  String get diagnosticsHubReconnectMaxTicksHint =>
      '0 keeps retrying indefinitely. Lower values stop sooner with an error.';

  @override
  String get diagnosticsHubReconnectIntervalLabel => 'Seconds between reconnect attempts (after burst)';

  @override
  String get diagnosticsHubReconnectIntervalHint =>
      'Allowed range: 5–86400. Interval changes apply the next time persistent retry starts.';

  @override
  String get diagnosticsHubReconnectEnvHint =>
      'If you clear overrides (Use defaults), values may still come from HUB_PERSISTENT_RETRY_MAX_FAILED_TICKS and HUB_PERSISTENT_RETRY_INTERVAL_SECONDS in the environment file, then built-in defaults.';

  @override
  String get diagnosticsHubReconnectApply => 'Apply hub retry settings';

  @override
  String get diagnosticsHubReconnectReset => 'Use defaults';

  @override
  String get diagnosticsHubReconnectSavedMessage => 'Hub reconnect tuning was saved.';

  @override
  String get diagnosticsHubReconnectInvalidMaxTicks => 'Enter a non-negative whole number.';

  @override
  String get diagnosticsHubReconnectInvalidInterval => 'Enter a whole number between 5 and 86400.';

  @override
  String get diagnosticsHubHardReloginEnabledLabel => 'Enable automatic hard relogin fallback';

  @override
  String get diagnosticsHubHardReloginEnabledDescription =>
      'When enabled, after repeated reconnect failures the agent will attempt logout, login with saved credentials, and then reconnect the socket.';

  @override
  String get diagnosticsHubHardReloginThresholdLabel => 'Failed reconnect attempts before hard relogin';

  @override
  String get diagnosticsHubHardReloginThresholdHint => 'Allowed range: 1-20. Lower values escalate sooner.';

  @override
  String get diagnosticsHubHardReloginInvalidThreshold => 'Enter a whole number between 1 and 20.';

  @override
  String get msgServerUrlRequired => 'Server URL is required';

  @override
  String get msgAgentIdRequired => 'Agent ID is required';

  @override
  String get msgAuthCredentialsRequired => 'Username and password are required';

  @override
  String get msgLoginRequiredBeforeConnect => 'Sign in before connecting to the hub';

  @override
  String get msgRpcInvalidRequest => 'Invalid request. Review the data sent.';

  @override
  String get msgRpcMethodNotFound => 'Method not supported by this version of the agent.';

  @override
  String get msgRpcAuthenticationFailed => 'Authentication failed. Get a new token and try again.';

  @override
  String get msgRpcUnauthorized => 'You do not have permission to execute this operation.';

  @override
  String get msgRpcTimeout => 'The operation exceeded the time limit. Try again.';

  @override
  String get msgRpcInvalidPayload => 'Failed to process the request data.';

  @override
  String get msgRpcNetworkError => 'Connection to the hub was lost. Try again.';

  @override
  String get msgRpcRateLimited => 'Too many requests in a short time. Wait and try again.';

  @override
  String get msgRpcReplayDetected => 'Duplicate request detected. Generate a new ID and try again.';

  @override
  String get msgRpcSqlValidationFailed => 'Invalid SQL command. Review the query sent.';

  @override
  String get msgRpcSqlExecutionFailed => 'Failed to execute the SQL command.';

  @override
  String get msgRpcConnectionPoolExhausted => 'Connection limit reached. Wait and try again.';

  @override
  String get msgRpcResultTooLarge => 'Result too large. Apply filters and try again.';

  @override
  String get msgRpcDatabaseConnectionFailed => 'Could not connect to the database.';

  @override
  String get msgRpcInvalidDatabaseConfig => 'Invalid database configuration. Review the connection settings.';

  @override
  String get msgRpcExecutionNotFound => 'Execution not found. It may have finished or never started.';

  @override
  String get msgRpcExecutionCancelled => 'Execution cancelled by the user.';

  @override
  String get msgRpcInternalError => 'Internal failure processing the request.';

  @override
  String get tabWebSocketConnection => 'WebSocket connection';

  @override
  String get tabClientTokenAuthorization => 'Client token authorization';

  @override
  String get tabWebSocketDiagnostics => 'Diagnostics';

  @override
  String get wsSectionConnection => 'WebSocket connection';

  @override
  String get wsSectionOptionalAuth => 'Authentication (optional)';

  @override
  String get wsFieldServerUrl => 'Server URL';

  @override
  String get wsFieldAgentId => 'Agent ID';

  @override
  String get wsFieldUsername => 'Username';

  @override
  String get wsHintServerUrl => 'https://api.example.com';

  @override
  String get wsHintAgentId => 'Generated automatically (read-only)';

  @override
  String get wsHintUsername => 'Username for authentication';

  @override
  String get wsHintPassword => 'Password for authentication';

  @override
  String get wsButtonAuthenticating => 'Signing in...';

  @override
  String get wsButtonLogout => 'Log out';

  @override
  String get wsButtonLogin => 'Log in';

  @override
  String get wsButtonDisconnect => 'Disconnect';

  @override
  String get wsButtonConnect => 'Connect';

  @override
  String get wsButtonSaveConfig => 'Save configuration';

  @override
  String get wsSectionOutboundCompression => 'Outbound compression (agent → hub)';

  @override
  String get wsFieldOutboundCompressionMode => 'Mode';

  @override
  String get wsOutboundCompressionOff => 'Off';

  @override
  String get wsOutboundCompressionGzip => 'Always GZIP';

  @override
  String get wsOutboundCompressionAuto => 'Automatic';

  @override
  String get wsOutboundCompressionDescription =>
      'Automatic: above the negotiated limit, the agent compresses with GZIP only if the result is smaller than JSON in UTF-8 (saves CPU and traffic on low-compressibility data).';

  @override
  String get wsSectionClientTokenPolicy => 'Client token policy (RPC)';

  @override
  String get wsFieldClientTokenPolicyIntrospection => 'Allow client_token.getPolicy introspection';

  @override
  String get wsClientTokenPolicyIntrospectionDescription =>
      'When disabled, the hub cannot call client_token.getPolicy to read permission metadata; SQL authorization with client_token is unaffected.';

  @override
  String get dbSectionTitle => 'Database configuration';

  @override
  String get dbFieldDatabaseDriver => 'Database driver';

  @override
  String get dbFieldOdbcDriverName => 'ODBC driver name';

  @override
  String get dbFieldHost => 'Host';

  @override
  String get dbHintHost => 'localhost';

  @override
  String get dbFieldPort => 'Port';

  @override
  String get dbHintPort => '1433';

  @override
  String get dbFieldDatabaseName => 'Database name';

  @override
  String get dbHintDatabaseName => 'Database name';

  @override
  String get dbFieldUsername => 'Username';

  @override
  String get dbHintUsername => 'Username';

  @override
  String get dbHintPassword => 'Password';

  @override
  String get dbButtonTestConnection => 'Test database connection';

  @override
  String get dbTabDatabase => 'Database';

  @override
  String get dbTabAdvanced => 'Advanced';

  @override
  String get odbcErrorPoolRange => 'Pool size must be between 1 and 20';

  @override
  String get odbcErrorLoginTimeoutRange => 'Login timeout must be between 1 and 120 seconds';

  @override
  String get odbcErrorBufferRange => 'Result buffer must be between 8 and 128 MB';

  @override
  String get odbcErrorChunkRange => 'Streaming chunk must be between 64 and 8192 KB';

  @override
  String get odbcErrorSaveFailed => 'Failed to save advanced settings. Try again.';

  @override
  String get odbcSuccessAppliedNow => 'Pool, timeout and streaming settings were saved and apply to new connections.';

  @override
  String get odbcSuccessAppliedGradually =>
      'Pool, timeout and streaming settings were saved. New options apply gradually to new connections.';

  @override
  String get odbcModalTitleSaved => 'Settings saved';

  @override
  String get odbcSectionTitle => 'Connection pool and timeouts';

  @override
  String get odbcBlockPool => 'Connection pool';

  @override
  String get odbcBlockPoolDescription =>
      'Multiple connections are reused automatically. Improves performance under high concurrency.';

  @override
  String get odbcFieldPoolSize => 'Maximum pool size';

  @override
  String get odbcHintPoolSize => '4';

  @override
  String get odbcBlockTimeouts => 'Timeouts';

  @override
  String get odbcFieldLoginTimeout => 'Login timeout (seconds)';

  @override
  String get odbcHintLoginTimeout => '30';

  @override
  String get odbcFieldResultBuffer => 'Result buffer (MB)';

  @override
  String get odbcHintResultBuffer => '32';

  @override
  String get odbcTextResultBufferHelp =>
      'Maximum in-memory buffer size for query results. Increasing may improve performance for large queries.';

  @override
  String get odbcBlockStreaming => 'Streaming';

  @override
  String get odbcFieldChunkSize => 'Chunk size (KB)';

  @override
  String get odbcHintChunkSize => '1024';

  @override
  String get odbcTextStreamingHelp =>
      'Chunk size sent to the UI during streaming queries. Larger values reduce update events and may improve throughput.';

  @override
  String get odbcTextQuickRecommendation => 'Quick recommendation:';

  @override
  String get odbcTextQuickRecommendationItems =>
      '• 256–512 KB: more frequent visual feedback\n• 1024 KB: general balance (default)\n• 2048–4096 KB: higher throughput for large datasets';

  @override
  String get odbcTextChunkWarning => 'If the UI freezes or memory use is high, reduce the chunk size.';

  @override
  String get odbcButtonRestoreDefault => 'Restore defaults';

  @override
  String get odbcButtonSaveAdvanced => 'Save advanced settings';

  @override
  String get ctSectionTitle => 'Client token authorization';

  @override
  String get ctFieldClientId => 'Client ID (auto-generated)';

  @override
  String get ctFieldAgentIdOptional => 'Agent ID (optional)';

  @override
  String get ctFieldName => 'Name (optional)';

  @override
  String get ctHintName => 'e.g. Client XYZ — Production';

  @override
  String get ctFieldPayloadJsonOptional => 'Payload JSON (optional)';

  @override
  String get ctHintClientId => 'Generated automatically';

  @override
  String get ctHintAgentId => 'agent-01';

  @override
  String get ctHintPayloadJson => 'JSON object (e.g. display_name, env)';

  @override
  String get ctFlagAllTables => 'All tables';

  @override
  String get ctFlagAllViews => 'All views';

  @override
  String get ctFlagAllPermissions => 'All permissions';

  @override
  String get ctSectionRulesByResource => 'Rules by resource';

  @override
  String get ctRuleTitlePrefix => 'Rule';

  @override
  String get ctButtonAddRule => 'Add rule';

  @override
  String get ctButtonCreateToken => 'Create token';

  @override
  String get ctButtonNewToken => 'New token';

  @override
  String get ctButtonRefreshList => 'Refresh list';

  @override
  String get ctButtonAutoRefreshOn => 'Auto refresh: on';

  @override
  String get ctButtonAutoRefreshOff => 'Auto refresh: off';

  @override
  String get ctButtonViewDetails => 'View details';

  @override
  String get ctButtonCopyClientToken => 'Copy token';

  @override
  String get ctTooltipCopyClientToken => 'Copy client token';

  @override
  String get ctInfoClientTokenCopied => 'Client token copied';

  @override
  String get ctInfoClientTokenLoadFailed => 'Could not load this token secret';

  @override
  String get ctInfoClientTokenUnavailable =>
      'Token unavailable for this record. Create a new token to copy the secret value.';

  @override
  String get ctButtonEdit => 'Edit';

  @override
  String get ctButtonClearFilters => 'Clear filters';

  @override
  String get ctSectionRegisteredTokens => 'Registered tokens';

  @override
  String get ctMsgNoTokenFound => 'No tokens found.';

  @override
  String get ctMsgNoTokenMatchFilter => 'No tokens match the applied filters.';

  @override
  String get ctFilterClientId => 'Filter by client ID or name';

  @override
  String get ctFilterStatus => 'Filter by status';

  @override
  String get ctFilterSort => 'Sort by';

  @override
  String get ctFilterStatusAll => 'All';

  @override
  String get ctFilterStatusActive => 'Active';

  @override
  String get ctFilterStatusRevoked => 'Revoked';

  @override
  String get ctSortNewest => 'Newest';

  @override
  String get ctSortOldest => 'Oldest';

  @override
  String get ctSortClientAsc => 'Client A-Z';

  @override
  String get ctSortClientDesc => 'Client Z-A';

  @override
  String get ctMsgTokenCreatedCopyNow => 'Token created successfully (copy and store it now):';

  @override
  String get ctLabelClient => 'Client';

  @override
  String get ctLabelId => 'ID';

  @override
  String get ctLabelAgent => 'Agent';

  @override
  String get ctLabelCreatedAt => 'Created at';

  @override
  String get ctLabelStatus => 'Status';

  @override
  String get ctLabelScope => 'Scope';

  @override
  String get ctLabelRules => 'Rules';

  @override
  String get ctLabelPayload => 'Payload';

  @override
  String get ctScopeAllPermissions => 'All permissions';

  @override
  String get ctScopeRestricted => 'Restricted permissions';

  @override
  String get ctScopeTables => 'Tables';

  @override
  String get ctScopeViews => 'Views';

  @override
  String get ctScopeNotInformed => 'not reported by the API';

  @override
  String get ctNoRulesConfigured => 'No specific rules configured';

  @override
  String get ctStatusRevoked => 'revoked';

  @override
  String get ctStatusActive => 'active';

  @override
  String get ctButtonRevoked => 'Revoked';

  @override
  String get ctButtonRevoke => 'Revoke';

  @override
  String get ctButtonDelete => 'Delete';

  @override
  String get ctConfirmRevokeTitle => 'Revoke token';

  @override
  String get ctConfirmRevokeMessage => 'Are you sure you want to revoke this token? It will stop working immediately.';

  @override
  String get ctConfirmDeleteTitle => 'Delete token';

  @override
  String get ctConfirmDeleteMessage => 'Are you sure you want to delete this token? This cannot be undone.';

  @override
  String get ctErrorRuleOrAllPermissionsRequired => 'Add at least one valid rule or enable all_permissions.';

  @override
  String get ctErrorRuleOrGlobalPermissionsRequired => 'Add at least one valid rule when global scope is disabled.';

  @override
  String get ctErrorGlobalPermissionRequired =>
      'Select at least one global permission when all_tables or all_views is enabled.';

  @override
  String get ctErrorPayloadMustBeJsonObject => 'Payload must be a valid JSON object.';

  @override
  String get ctErrorPayloadInvalidJson => 'Invalid JSON payload.';

  @override
  String get ctErrorPayloadDatabaseMustBeString => 'payload.database must be a string.';

  @override
  String get ctErrorPayloadDatabaseCannotBeEmpty => 'payload.database must not be empty.';

  @override
  String get ctPermissionRead => 'Read';

  @override
  String get ctPermissionUpdate => 'Update';

  @override
  String get ctPermissionDelete => 'Delete';

  @override
  String get ctRuleTypeTable => 'Table';

  @override
  String get ctRuleTypeView => 'View';

  @override
  String get ctRuleTypeUnknown => 'Unknown';

  @override
  String get ctRuleEffectAllow => 'Allow';

  @override
  String get ctRuleEffectDeny => 'Deny';

  @override
  String get ctDialogDismissCreateToken => 'Dismiss create token dialog';

  @override
  String get ctDialogDismissRule => 'Dismiss rule dialog';

  @override
  String get ctPermissionDdl => 'DDL';

  @override
  String get ctGlobalScopeRulesDisabled =>
      'Global scope is enabled. Resource rules are hidden and will be removed when you save this token.';

  @override
  String get ctGridColumnType => 'Type';

  @override
  String get ctGridColumnResource => 'Resource';

  @override
  String get ctGridColumnEffect => 'Effect';

  @override
  String get ctGridColumnPermissions => 'Permissions';

  @override
  String get ctGridColumnActions => 'Actions';

  @override
  String get ctNoRulesAdded => 'No rules added. Click \"Add rule\".';

  @override
  String get ctDialogAddRuleTitle => 'Add rule';

  @override
  String get ctDialogCreateTokenTitle => 'Create client token';

  @override
  String get ctDialogEditTokenTitle => 'Edit client token';

  @override
  String get ctButtonSaveTokenChanges => 'Save changes';

  @override
  String get ctDialogEditRuleTitle => 'Edit rule';

  @override
  String get ctDialogSaveRule => 'Save rule';

  @override
  String get ctEditUpdatesTokenHint => 'Changes will apply to the selected token.';

  @override
  String get ctDialogTokenDetailsTitle => 'Token details';

  @override
  String get ctRuleNoPermission => 'No permissions';

  @override
  String get ctTooltipEditRule => 'Edit rule';

  @override
  String get ctTooltipDeleteRule => 'Delete rule';

  @override
  String get ctTooltipEditToken => 'Edit token';

  @override
  String get ctErrorRuleResourceRequired => 'Enter at least one resource (schema.name).';

  @override
  String get ctErrorRulePermissionRequired => 'Select at least one permission for the rule.';

  @override
  String ctErrorRuleResourceInvalidChars(String resource) {
    return 'Invalid resource name: \"$resource\". Use only letters, numbers, underscores and an optional dot (schema.name).';
  }

  @override
  String ctRuleWarnDuplicates(String resources) {
    return 'The following rules already exist and will be replaced: $resources. Confirm to proceed.';
  }

  @override
  String get ctDialogConfirmReplace => 'Confirm replacement';

  @override
  String get ctRuleImportFile => 'Import .txt';

  @override
  String get ctButtonExportRules => 'Export rules';

  @override
  String get ctButtonImportRules => 'Import rules';

  @override
  String get ctExportRulesDefaultFileName => 'token_rules.txt';

  @override
  String ctImportRulesErrorInvalidFormat(int line, String content) {
    return 'Line $line: \"$content\" — invalid format. Each line must follow the full pattern: resource;type;effect;permissions (e.g. dbo.customers;table;allow;read).';
  }

  @override
  String get ctImportRulesErrorEmpty => 'The file is empty or contains no valid rules.';

  @override
  String get ctImportRulesErrorFileTooLarge => 'The file exceeds the maximum allowed size (512 KB).';

  @override
  String ctImportRulesSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rules imported successfully.',
      one: '1 rule imported successfully.',
    );
    return '$_temp0';
  }

  @override
  String ctRuleImportSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rules imported successfully.',
      one: '1 rule imported successfully.',
    );
    return '$_temp0';
  }

  @override
  String get ctRuleImportErrorEmpty => 'The file is empty.';

  @override
  String get ctRuleImportErrorNoValidLines => 'No valid lines found in the file.';

  @override
  String get ctRuleImportErrorFileTooLarge => 'The file exceeds the maximum allowed size (512 KB).';

  @override
  String ctRuleImportErrorLineInvalid(int line, String content) {
    return 'Line $line: \"$content\" — invalid format. Use schema.name or schema.name;table;allow;read.';
  }

  @override
  String get ctRuleFieldType => 'Type';

  @override
  String get ctRuleFieldEffect => 'Effect';

  @override
  String get ctRuleFieldResource => 'Resource (schema.name)';

  @override
  String get ctRuleHintResource => 'dbo.customers; dbo.orders';

  @override
  String get ctLabelPayloadColon => 'Payload:';

  @override
  String get ctLabelRulesColon => 'Rules:';

  @override
  String get ctRuleFieldEffectColon => 'Effect:';

  @override
  String get ctGridColumnPermissionsColon => 'Permissions:';

  @override
  String get connectionStatusHubConnected => 'Hub: Connected';

  @override
  String get connectionStatusHubConnecting => 'Hub: Connecting...';

  @override
  String get connectionStatusHubReconnecting => 'Hub: Reconnecting...';

  @override
  String get connectionStatusHubReconnectingSigningIn => 'Hub: Signing in again...';

  @override
  String get connectionStatusHubReconnectingSocket => 'Hub: Restoring connection...';

  @override
  String get connectionStatusHubReconnectingWaitingHub => 'Hub: Waiting for server...';

  @override
  String get connectionStatusHubError => 'Hub: Connection error';

  @override
  String get connectionStatusHubDisconnected => 'Hub: Disconnected';

  @override
  String get msgHubPersistentRetryExhausted =>
      'Could not reach the hub after many attempts. Check the server URL, network, and sign-in, then tap Connect.';

  @override
  String get connectionStatusDatabaseConnected => 'DB: Connected';

  @override
  String get connectionStatusDatabaseDisconnected => 'DB: Disconnected';

  @override
  String get connectionStatusDatabaseTooltip =>
      'Last successful ODBC check (connection test or query). Not a permanent database session.';

  @override
  String get formHintCep => '00.000-000';

  @override
  String get formHintPhone => '(00) 0000-0000';

  @override
  String get formHintMobile => '(00) 00000-0000';

  @override
  String get formHintDocument => '000.000.000-00 or 00.000.000/0000-00';

  @override
  String get formHintState => 'SP';

  @override
  String get formValidationEmailInvalid => 'Invalid email address';

  @override
  String get formValidationUrlHttpHttps => 'Enter a URL starting with http:// or https://';

  @override
  String get formValidationCepDigits => 'Postal code must have 8 digits';

  @override
  String get formValidationPhoneDigits => 'Phone must have 10 digits (area code + number)';

  @override
  String get formValidationMobileDigits => 'Mobile must have 11 digits';

  @override
  String get formValidationMobileNineAfterDdd => 'Mobile must start with 9 after the area code';

  @override
  String get formValidationDocumentDigits => 'CPF (11) or CNPJ (14) digits';

  @override
  String get formValidationStateLetters => 'State must be 2 letters';

  @override
  String get formFieldLabelPassword => 'Password';

  @override
  String get formPasswordDefaultHint => 'Enter password';

  @override
  String formPasswordRequired(String fieldLabel) {
    return '$fieldLabel is required.';
  }

  @override
  String get formNumericInvalidValue => 'Invalid value';

  @override
  String formNumericMinValue(int min) {
    return 'Minimum value: $min';
  }

  @override
  String formNumericMaxValue(int max) {
    return 'Maximum value: $max';
  }
}
