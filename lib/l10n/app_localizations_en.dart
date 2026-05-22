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
  String get navAgentActions => 'System Actions';

  @override
  String get agentActionsRefresh => 'Refresh';

  @override
  String get agentActionsRunSelected => 'Run selected';

  @override
  String get agentActionsTestSelected => 'Test action';

  @override
  String get agentActionsCancelExecution => 'Cancel execution';

  @override
  String get agentActionsDeleteSelected => 'Delete action';

  @override
  String get agentActionsDeleteConfirmTitle => 'Delete action';

  @override
  String agentActionsDeleteConfirmMessage(Object actionName) {
    return 'Delete \"$actionName\"? Execution history is preserved, but this action can no longer be run.';
  }

  @override
  String get agentActionsDeleteConfirm => 'Delete';

  @override
  String get agentActionsDeleteCancel => 'Cancel';

  @override
  String get agentActionsExportBundle => 'Export actions…';

  @override
  String get agentActionsImportBundle => 'Import actions…';

  @override
  String get agentActionsExportBundleDefaultFileName => 'plug_agente_actions.json';

  @override
  String get agentActionsExportBundleSuccessTitle => 'Actions exported';

  @override
  String get agentActionsExportBundleSuccessMessage =>
      'The sanitized action bundle was saved. Secret values were not included; configure placeholders on the target machine.';

  @override
  String get agentActionsImportBundleSuccessTitle => 'Actions imported';

  @override
  String agentActionsImportBundleSuccessMessage(int definitionCount, int triggerCount) {
    String _temp0 = intl.Intl.pluralLogic(
      definitionCount,
      locale: localeName,
      other: '$definitionCount actions',
      one: '1 action',
    );
    String _temp1 = intl.Intl.pluralLogic(
      triggerCount,
      locale: localeName,
      other: '$triggerCount triggers',
      one: '1 trigger',
    );
    return 'Imported $_temp0 and $_temp1. Definitions need validation before run.';
  }

  @override
  String agentActionsImportBundleSecretsMessage(Object secretNames) {
    return 'Configure these secret placeholders on this machine: $secretNames.';
  }

  @override
  String get agentActionsConfirmImportBundleTitle => 'Import actions';

  @override
  String get agentActionsConfirmImportBundleMessage =>
      'Import actions from a JSON bundle? Existing actions with the same id will be updated. Triggers are imported paused and remote execution requires reapproval.';

  @override
  String get agentActionsConfirmImportBundleConfirm => 'Import';

  @override
  String get agentActionsConfirmImportBundleCancel => 'Cancel';

  @override
  String get agentActionsBundleTransferFailedTitle => 'Action bundle transfer failed';

  @override
  String get agentActionsBundlePickerError => 'Could not open the file picker.';

  @override
  String get agentActionsTestSuccessTitle => 'Action test completed';

  @override
  String get agentActionsTestCanRunMessage => 'The action configuration is valid and the action can run.';

  @override
  String get agentActionsTestValidButInactiveMessage =>
      'The action configuration is valid, but the action is not active.';

  @override
  String get agentActionsTestPreviewTitle => 'Redacted test preview';

  @override
  String get agentActionsTestPreviewCommandLabel => 'Prepared command';

  @override
  String get agentActionsTestPreviewUnavailableTitle => 'Preview unavailable';

  @override
  String get agentActionsTestPreviewDiagnosticEngine => 'Engine';

  @override
  String get agentActionsTestPreviewDiagnosticConnectionLabel => 'Connection';

  @override
  String get agentActionsTestPreviewDiagnosticCatalogCount => 'Catalog connections';

  @override
  String get agentActionsTestPreviewDiagnosticDefaultConfig => 'Used default config';

  @override
  String get agentActionsTestPreviewDiagnosticYes => 'Yes';

  @override
  String get agentActionsTestPreviewDiagnosticNo => 'No';

  @override
  String get agentActionsFormCreateTitle => 'New command line action';

  @override
  String get agentActionsFormEditTitle => 'Command line action';

  @override
  String get agentActionsFormCreateDeveloperTitle => 'New developer action';

  @override
  String get agentActionsFormEditDeveloperTitle => 'Developer action';

  @override
  String get agentActionsFormCreateExecutableTitle => 'New executable action';

  @override
  String get agentActionsFormEditExecutableTitle => 'Executable action';

  @override
  String get agentActionsFormExecutablePath => 'Executable path';

  @override
  String get agentActionsFormArguments => 'Arguments';

  @override
  String get agentActionsFormArgumentsHint => 'Enter one argument per line.';

  @override
  String get agentActionsFormBrowseExecutablePath => 'Browse executable';

  @override
  String get agentActionsFormCreateScriptTitle => 'New script action';

  @override
  String get agentActionsFormEditScriptTitle => 'Script action';

  @override
  String get agentActionsFormScriptPath => 'Script path';

  @override
  String get agentActionsFormInterpreterPath => 'Interpreter path (optional)';

  @override
  String get agentActionsFormInterpreterPathHint =>
      'Leave empty to use the default interpreter for the script extension.';

  @override
  String get agentActionsFormBrowseScriptPath => 'Browse script';

  @override
  String get agentActionsFormBrowseInterpreterPath => 'Browse interpreter';

  @override
  String get agentActionsFormCreatePowerShellTitle => 'New PowerShell action';

  @override
  String get agentActionsFormEditPowerShellTitle => 'PowerShell action';

  @override
  String get agentActionsFormPowerShellMode => 'PowerShell mode';

  @override
  String get agentActionsFormPowerShellModeCommand => 'Command';

  @override
  String get agentActionsFormPowerShellModeScript => 'Script .ps1';

  @override
  String get agentActionsFormPowerShellExecutable => 'PowerShell executable';

  @override
  String get agentActionsFormPowerShellExecutableWindows => 'Windows PowerShell';

  @override
  String get agentActionsFormPowerShellExecutablePwsh => 'PowerShell 7';

  @override
  String get agentActionsFormPowerShellCommand => 'PowerShell command';

  @override
  String get agentActionsFormPowerShellScriptPath => 'PowerShell script path';

  @override
  String get agentActionsFormBrowsePowerShellScriptPath => 'Browse PowerShell script';

  @override
  String get agentActionsFormPowerShellScriptPathInvalid => 'Use a .ps1 file for PowerShell script mode.';

  @override
  String get agentActionsFormPowerShellModeUnavailable =>
      'The selected PowerShell mode is unavailable in the current runtime.';

  @override
  String get agentActionsFormCreateJarTitle => 'New JAR action';

  @override
  String get agentActionsFormEditJarTitle => 'JAR action';

  @override
  String get agentActionsFormJarPath => 'JAR file path';

  @override
  String get agentActionsFormJavaExecutablePath => 'Java executable path (optional)';

  @override
  String get agentActionsFormJavaExecutablePathHint => 'Leave empty to use java.exe from PATH.';

  @override
  String get agentActionsFormBrowseJarPath => 'Browse JAR file';

  @override
  String get agentActionsFormBrowseJavaExecutablePath => 'Browse java.exe';

  @override
  String get agentActionsFormCreateEmailTitle => 'New email action';

  @override
  String get agentActionsFormEditEmailTitle => 'Email action';

  @override
  String get agentActionsFormSmtpProfileId => 'SMTP profile secret name';

  @override
  String get agentActionsFormSmtpProfileIdHint => 'Name of the secret that stores the SMTP JSON profile.';

  @override
  String get agentActionsFormEmailFrom => 'From address';

  @override
  String get agentActionsFormEmailTo => 'To recipients';

  @override
  String get agentActionsFormEmailToHint => 'One email address per line.';

  @override
  String get agentActionsFormEmailCc => 'Cc recipients (optional)';

  @override
  String get agentActionsFormEmailCcHint => 'One email address per line.';

  @override
  String get agentActionsFormEmailBcc => 'Bcc recipients (optional)';

  @override
  String get agentActionsFormEmailBccHint => 'One email address per line.';

  @override
  String get agentActionsFormEmailSubject => 'Subject template';

  @override
  String get agentActionsFormEmailSubjectHint => 'Use context tokens resolved from the optional context JSON file.';

  @override
  String get agentActionsFormEmailBody => 'Body template';

  @override
  String get agentActionsFormEmailBodyHint =>
      'Plain text body. Use context tokens resolved from the optional context JSON file.';

  @override
  String get agentActionsFormEmailAttachments => 'Attachment paths (optional)';

  @override
  String get agentActionsFormEmailAttachmentsHint =>
      'One file path per line. Allowed types are validated by the action policy.';

  @override
  String get agentActionsFormCreateComObjectTitle => 'New COM object action';

  @override
  String get agentActionsFormEditComObjectTitle => 'COM object action';

  @override
  String get agentActionsFormComProgId => 'COM ProgID';

  @override
  String get agentActionsFormComMemberName => 'COM member';

  @override
  String get agentActionsFormComArguments => 'Arguments (JSON object)';

  @override
  String get agentActionsFormComArgumentsHint => 'Use a flat JSON object with string, number, or boolean values.';

  @override
  String get agentActionsFormInvalidComArguments => 'Arguments must be a valid JSON object.';

  @override
  String get agentActionsFormNew => 'New';

  @override
  String get agentActionsFormSave => 'Save action';

  @override
  String get agentActionsFormName => 'Name';

  @override
  String get agentActionsFormDescription => 'Description';

  @override
  String get agentActionsFormType => 'Type';

  @override
  String get agentActionsFormCommand => 'Command';

  @override
  String get agentActionsFormWorkingDirectory => 'Working directory';

  @override
  String get agentActionsFormExecutorPath => 'Executor.exe path';

  @override
  String get agentActionsFormProjectPath => '.7Proj file path';

  @override
  String get agentActionsFormData7ConfigPath => 'Data7.Config path';

  @override
  String get agentActionsFormBrowseExecutorPath => 'Browse Executor.exe';

  @override
  String get agentActionsFormBrowseProjectPath => 'Browse .7Proj file';

  @override
  String get agentActionsFormBrowseData7ConfigPath => 'Browse Data7.Config';

  @override
  String get agentActionsFormBrowseFileError => 'Could not open the file picker for this action.';

  @override
  String get agentActionsFormUseDefaultExecutorPath => 'Use default Executor';

  @override
  String get agentActionsFormUseDefaultConfigBinPath => 'Use default config (bin)';

  @override
  String get agentActionsFormUseDefaultConfigRootPath => 'Use default config (root)';

  @override
  String get agentActionsFormExecutorPathHintExpectedFileName => 'The executor path must end with Executor.exe.';

  @override
  String get agentActionsFormExecutorPathHintDefault => 'The executor is pointing to the default Data7 path.';

  @override
  String get agentActionsFormExecutorPathHintMissing => 'The selected Executor.exe was not found at this path.';

  @override
  String get agentActionsFormExecutorPathHintDirectory =>
      'The executor path points to a directory, not an Executor.exe file.';

  @override
  String get agentActionsFormProjectPathHintExpectedExtension => 'The project must point to a .7Proj file.';

  @override
  String get agentActionsFormProjectPathHintMissing => 'The selected .7Proj file was not found at this path.';

  @override
  String get agentActionsFormProjectPathHintDirectory => 'The project path points to a directory, not a .7Proj file.';

  @override
  String get agentActionsFormData7ConfigPathHintExpectedFileName => 'The config path must end with Data7.Config.';

  @override
  String get agentActionsFormData7ConfigPathHintDefaultBin =>
      'The Data7.Config path is using the default C:\\Data7\\bin location.';

  @override
  String get agentActionsFormData7ConfigPathHintDefaultRoot =>
      'The Data7.Config path is using the default C:\\Data7 location.';

  @override
  String get agentActionsFormData7ConfigPathHintMissing => 'The selected Data7.Config was not found at this path.';

  @override
  String get agentActionsFormData7ConfigPathHintDirectory =>
      'The config path points to a directory, not a Data7.Config file.';

  @override
  String get agentActionsFormPathHintInspectionFailed =>
      'Could not inspect this local path right now. Review permissions, links, or disk availability.';

  @override
  String get agentActionsFormReloadConnections => 'Reload connections';

  @override
  String get agentActionsFormDefaultConfigResolved => 'Using the Data7.Config found in the default location.';

  @override
  String agentActionsFormResolvedConfigPath(Object path) {
    return 'Resolved config: $path';
  }

  @override
  String agentActionsFormLoadedConfigPath(Object path) {
    return 'Connections loaded from: $path';
  }

  @override
  String get agentActionsFormConnectionId => 'Connection ID';

  @override
  String get agentActionsFormConnectionSelector => 'Loaded connection';

  @override
  String get agentActionsFormConnectionSelectorPlaceholder => 'Select a loaded connection';

  @override
  String get agentActionsFormConnectionSearch => 'Filter loaded connections';

  @override
  String get agentActionsFormConnectionFilterEmpty => 'No loaded connection matches this filter.';

  @override
  String get agentActionsFormConnectionLabel => 'Safe connection label';

  @override
  String get agentActionsFormConnectionMissingTitle => 'Saved connection not found';

  @override
  String get agentActionsFormConnectionMissingMessage =>
      'The saved connection no longer exists in the loaded Data7.Config. Reload the connections, select another valid connection, and save the action again.';

  @override
  String get agentActionsFormConnectionUnknownTitle => 'Connection ID is outside the loaded catalog';

  @override
  String get agentActionsFormConnectionUnknownMessage =>
      'The entered ID does not belong to the catalog loaded right now. Select a valid connection from the list or reload the connections before saving.';

  @override
  String get agentActionsFormConnectionChangedTitle => 'Connection changed since the last validation';

  @override
  String get agentActionsFormConnectionChangedMessage =>
      'The loaded connection changed since the saved snapshot. Review the configuration and save the action again before running it.';

  @override
  String get agentActionsFormUnsupportedType =>
      'The visual editor for this action type is not available on this screen yet.';

  @override
  String get agentActionsFormState => 'State';

  @override
  String get agentActionsHelpTypeTitle => 'Action type';

  @override
  String get agentActionsHelpTypeMessage =>
      'Defines the runner and internal contract used to save and run this action. After the action is created, the type becomes read-only to avoid accidental runner changes.';

  @override
  String get agentActionsHelpStateTitle => 'Action state';

  @override
  String get agentActionsHelpStateMessage =>
      'Controls whether the action can run. Actions that need validation remain visible, but should not run automatically until reviewed.';

  @override
  String get agentActionsHelpCommandTitle => 'Command';

  @override
  String get agentActionsHelpCommandMessage =>
      'Line sent directly to the command-line runner. Include the executable and arguments as they would be called on Windows; secret placeholders stay in text for secure runtime resolution.';

  @override
  String get agentActionsHelpPowerShellModeTitle => 'PowerShell mode';

  @override
  String get agentActionsHelpPowerShellModeMessage =>
      'Command saves a generated PowerShell wrapper as a command line action. Script .ps1 saves as a script action and reuses the script runner.';

  @override
  String get agentActionsHelpPowerShellExecutableTitle => 'PowerShell executable';

  @override
  String get agentActionsHelpPowerShellExecutableMessage =>
      'Choose powershell.exe for Windows PowerShell or pwsh.exe for PowerShell 7. The executable must be available on PATH or in the process environment.';

  @override
  String get agentActionsHelpPowerShellCommandTitle => 'PowerShell command';

  @override
  String get agentActionsHelpPowerShellCommandMessage =>
      'Content passed to PowerShell through -Command. The editor builds the persisted wrapper and preserves secret placeholders for the current scanner.';

  @override
  String get agentActionsHelpPowerShellScriptTitle => 'PowerShell script';

  @override
  String get agentActionsHelpPowerShellScriptMessage =>
      'Path to a local .ps1 file. In PowerShell 7 mode, pwsh.exe is automatically stored as the script interpreter.';

  @override
  String get agentActionsHelpPathTitle => 'Main path';

  @override
  String get agentActionsHelpPathMessage =>
      'Main local path used by the runner, such as an executable, script, or input file. Prefer absolute paths; later changes may block execution according to the path change policy.';

  @override
  String get agentActionsHelpArgumentsTitle => 'Arguments';

  @override
  String get agentActionsHelpArgumentsMessage =>
      'Enter one argument per line. Each line becomes one argument list item, so do not combine multiple options on one line unless the target program expects that format.';

  @override
  String get agentActionsHelpWorkingDirectoryTitle => 'Working directory';

  @override
  String get agentActionsHelpWorkingDirectoryMessage =>
      'Initial process directory. Leave empty to use the runner default or enter an absolute path allowed by the path policy.';

  @override
  String get agentActionsHelpInterpreterTitle => 'Interpreter';

  @override
  String get agentActionsHelpInterpreterMessage =>
      'Executable used to open scripts. When empty, the runner chooses the default interpreter for the extension; fill it to force a specific version such as pwsh.exe or python.exe.';

  @override
  String get agentActionsHelpJarTitle => 'JAR file';

  @override
  String get agentActionsHelpJarMessage =>
      'The .jar file that Java will execute. The path is stored in the definition and participates in the path change policy.';

  @override
  String get agentActionsHelpEmailTitle => 'Email field';

  @override
  String get agentActionsHelpEmailMessage =>
      'Configuration used by the email runner. Recipient and attachment fields accept one item per line; the SMTP profile must exist in local configuration.';

  @override
  String get agentActionsHelpComTitle => 'COM object';

  @override
  String get agentActionsHelpComMessage =>
      'Identifies the COM object ProgID, the method or property called, and the arguments sent. Use only COM automations installed and tested on the local Windows machine.';

  @override
  String get agentActionsHelpDeveloperTitle => 'Developer Data7';

  @override
  String get agentActionsHelpDeveloperMessage =>
      'Configures the Executor.exe, .7Proj project, Data7.Config, and connection used to run the Developer action.';

  @override
  String get agentActionsHelpMaxAttemptsTitle => 'Maximum attempts';

  @override
  String get agentActionsHelpMaxAttemptsMessage =>
      'Maximum attempts for local runs and triggers. Remote runs stay at one attempt unless remote retry is enabled.';

  @override
  String get agentActionsHelpTimeoutTitle => 'Maximum runtime';

  @override
  String get agentActionsHelpTimeoutMessage =>
      'Local execution timeout in minutes. When reached, execution fails as timed out and the policy below decides whether the main process should be killed.';

  @override
  String get agentActionsHelpKillOnTimeoutTitle => 'Kill on timeout';

  @override
  String get agentActionsHelpKillOnTimeoutMessage =>
      'When enabled, the runner tries to kill the main process if execution exceeds the configured maximum runtime.';

  @override
  String get agentActionsHelpRemoteRetryTitle => 'Remote retry';

  @override
  String get agentActionsHelpRemoteRetryMessage =>
      'Allows Hub-started executions to use the retry policy. Enable only when repeating this action is safe.';

  @override
  String get agentActionsHelpRunElevatedTitle => 'Elevated execution';

  @override
  String get agentActionsHelpRunElevatedMessage =>
      'Runs through the elevated helper when available. Requires local helper installation and scheduled task setup.';

  @override
  String get agentActionsHelpContextInjectionTitle => 'Context injection';

  @override
  String get agentActionsHelpContextInjectionMessage =>
      'Defines how runtime parameters enter the execution: argument, file, environment variables, or stdin.';

  @override
  String get agentActionsHelpPathChangePolicyTitle => 'Path change policy';

  @override
  String get agentActionsHelpPathChangePolicyMessage =>
      'Controls what happens when paths or content snapshots change after validation: fail, warn, or allow.';

  @override
  String get agentActionsHelpRuntimeSchemaTitle => 'Runtime schema';

  @override
  String get agentActionsHelpRuntimeSchemaMessage =>
      'JSON Schema object used to validate runtimeParameters before execution. Use it when the Hub or triggers send parameters; leave empty to accept any object.';

  @override
  String get agentActionsHelpAllowedProfilesTitle => 'Allowed profiles';

  @override
  String get agentActionsHelpAllowedProfilesMessage =>
      'Restricts the action to the listed operational profiles. Empty means any agent profile is allowed.';

  @override
  String get agentActionsHelpAllowedEnvironmentVariablesTitle => 'Allowed variable names';

  @override
  String get agentActionsHelpAllowedEnvironmentVariablesMessage =>
      'Lists variable names that may be injected into the process. Use it to block unexpected names from runtime parameters or later edits.';

  @override
  String get agentActionsHelpEnvironmentVariablesTitle => 'Environment variables';

  @override
  String get agentActionsHelpEnvironmentVariablesMessage =>
      'Variables added to the child process as NAME=value, one per line. Secret placeholders remain resolved at runtime.';

  @override
  String get agentActionsHelpQueueTitle => 'Concurrency and queue';

  @override
  String get agentActionsHelpQueueMessage =>
      'Defines how many runs of this action may execute simultaneously, how many wait in queue, and whether new requests fail, wait, or replace a full queue.';

  @override
  String get agentActionsHelpPathAllowlistTitle => 'Directory allowlist';

  @override
  String get agentActionsHelpPathAllowlistMessage =>
      'Restricts allowed working directories and context files. Use absolute paths, one per line; empty adds no extra local allowlist.';

  @override
  String get agentActionsHelpProcessWindowTitle => 'Process window';

  @override
  String get agentActionsHelpProcessWindowMessage =>
      'Controls the locally started process window: normal, hidden, or minimized, according to Windows support.';

  @override
  String get agentActionsHelpCaptureTitle => 'Output capture';

  @override
  String get agentActionsHelpCaptureMessage =>
      'Controls whether stdout and stderr are stored in history. Redaction tries to mask secrets before persistence, but sensitive output should still be avoided.';

  @override
  String get agentActionsHelpEncodingTitle => 'Output encoding';

  @override
  String get agentActionsHelpEncodingMessage =>
      'Defines how captured stdout and stderr are decoded, using UTF-8 or the Windows system console.';

  @override
  String get agentActionsHelpAcceptedExitCodesTitle => 'Exit codes';

  @override
  String get agentActionsHelpAcceptedExitCodesMessage =>
      'Codes that count as success. The default is 0; additional values must be comma-separated.';

  @override
  String get agentActionsHelpOnAppExitTitle => 'When agent closes';

  @override
  String get agentActionsHelpOnAppExitMessage =>
      'Defines what to do with still-running processes when Plug Agent closes: try to stop them, leave them running, or block according to runner support.';

  @override
  String get agentActionsHelpRemoteExecutionTitle => 'Remote execution';

  @override
  String get agentActionsHelpRemoteExecutionMessage =>
      'Allows the Hub to execute this saved action over Socket.IO JSON-RPC. Requires local approval and should be enabled only for reviewed actions.';

  @override
  String get agentActionsHelpRemoteAdHocTitle => 'Remote ad-hoc';

  @override
  String get agentActionsHelpRemoteAdHocMessage =>
      'Allows free-form commands sent by the Hub when the global feature is enabled. Keep it disabled except in controlled environments because it greatly increases risk exposure.';

  @override
  String get agentActionsHelpNotificationsTitle => 'Notifications';

  @override
  String get agentActionsHelpNotificationsMessage =>
      'Controls desktop notifications shown when local runs finish with success, failure, or timeout.';

  @override
  String get agentActionsFormNotificationsTitle => 'Desktop notifications';

  @override
  String get agentActionsFormNotificationsDescription =>
      'Show a Windows notification when a local run reaches a terminal state.';

  @override
  String get agentActionsFormNotifyOnSuccess => 'Notify on success';

  @override
  String get agentActionsFormNotifyOnFailure => 'Notify on failure';

  @override
  String get agentActionsFormNotifyOnTimeout => 'Notify on timeout';

  @override
  String get agentActionNotificationSuccessBody => 'Execution finished successfully.';

  @override
  String get agentActionNotificationTimeoutBody => 'Execution exceeded the configured maximum runtime.';

  @override
  String get agentActionNotificationFailureFallbackBody => 'Execution finished with a failure.';

  @override
  String get agentActionsFormExecutionPoliciesTitle => 'Execution policies';

  @override
  String get agentActionsFormExecutionPoliciesDescription =>
      'Timeout and retry apply to local runs and scheduled triggers. Remote Hub runs stay at one attempt unless remote retry is enabled.';

  @override
  String get agentActionsFormPathChangePolicy => 'Path change policy';

  @override
  String get agentActionsFormPathChangePolicyFail => 'Fail if path or file content changed';

  @override
  String get agentActionsFormPathChangePolicyWarn => 'Warn if path or file content changed';

  @override
  String get agentActionsFormPathChangePolicyAllow => 'Allow path and content changes';

  @override
  String get agentActionsFormContextInjectionMode => 'Context injection mode';

  @override
  String get agentActionsFormContextInjectionArgument => 'Argument (default)';

  @override
  String get agentActionsFormContextInjectionFile => 'Context file (required at run)';

  @override
  String get agentActionsFormContextInjectionEnvironment => 'Environment variables';

  @override
  String get agentActionsFormContextInjectionStdin => 'Standard input';

  @override
  String get agentActionsFormRuntimeParameterSchema => 'Runtime parameters JSON schema (optional)';

  @override
  String get agentActionsFormRuntimeParameterSchemaHint =>
      'JSON Schema object validated against runtimeParameters on each run. Leave empty to skip.';

  @override
  String get agentActionsTestPreviewPathSnapshotWarnings => 'Path snapshot warnings';

  @override
  String get agentActionsFormMaxRuntimeMinutes => 'Maximum runtime (minutes)';

  @override
  String get agentActionsFormKillOnTimeout => 'Kill main process on timeout';

  @override
  String get agentActionsFormMaxAttempts => 'Maximum attempts';

  @override
  String get agentActionsFormAllowRemoteRetry => 'Allow retry on remote Hub runs';

  @override
  String get agentActionsFormRuntimePoliciesTitle => 'Runtime constraints';

  @override
  String get agentActionsFormRuntimePoliciesDescription =>
      'Operational profile gate, child-process environment, accepted exit codes, and behavior when the Plug agent closes. Empty allowed profiles means any profile.';

  @override
  String get agentActionsFormAllowedProfiles => 'Allowed operational profiles';

  @override
  String get agentActionsFormAllowedProfilesHint =>
      'Comma-separated (e.g. prod, homolog). Leave empty for any profile.';

  @override
  String get agentActionsFormAllowedEnvironmentVariableNames => 'Allowed environment variable names';

  @override
  String get agentActionsFormAllowedEnvironmentVariableNamesHint =>
      'Comma-separated (e.g. PLUG_API_URL, PLUG_TOKEN). Leave empty to allow any name used below or at runtime.';

  @override
  String get agentActionsFormEnvironmentVariables => 'Process environment variables';

  @override
  String get agentActionsFormEnvironmentVariablesHint =>
      'One NAME=value per line. Reference action secrets with the placeholder convention documented in the secrets section. Applied when the action starts a process; environment injection mode adds runtime parameters from the run request.';

  @override
  String get agentActionsFormEnvironmentVariablesInvalid =>
      'Environment variables must use one NAME=value per line with a valid variable name.';

  @override
  String agentActionsFormCurrentOperationalProfile(String profile) {
    return 'Current agent profile: $profile';
  }

  @override
  String get agentActionsFormCurrentOperationalProfileUnset =>
      'Current agent profile is not set (AGENT_OPERATIONAL_PROFILE).';

  @override
  String get agentActionsFormAcceptedExitCodes => 'Accepted exit codes';

  @override
  String get agentActionsFormAcceptedExitCodesHint => 'Comma-separated integers (default 0).';

  @override
  String get agentActionsFormInvalidExitCodes => 'Enter comma-separated integers for exit codes (e.g. 0, 1).';

  @override
  String get agentActionsFormProcessWindowMode => 'Process window';

  @override
  String get agentActionsFormProcessWindowModeNormal => 'Normal console';

  @override
  String get agentActionsFormProcessWindowModeHidden => 'Hidden (best effort)';

  @override
  String get agentActionsFormProcessWindowModeMinimized => 'Minimized (normal start)';

  @override
  String get agentActionsFormCapturePolicyDescription =>
      'Control whether process output is stored and redacted before persistence.';

  @override
  String get agentActionsFormCaptureStdout => 'Capture stdout';

  @override
  String get agentActionsFormCaptureStderr => 'Capture stderr';

  @override
  String get agentActionsFormRedactBeforePersisting => 'Redact output before saving';

  @override
  String get agentActionsFormQueuePolicyDescription =>
      'Limits concurrent runs and queue behavior for this action definition.';

  @override
  String get agentActionsFormMaxConcurrent => 'Max concurrent runs';

  @override
  String get agentActionsFormMaxQueued => 'Max queued runs';

  @override
  String get agentActionsFormInvalidQueueLimits => 'Enter positive integers for max concurrent and max queued runs.';

  @override
  String get agentActionsFormConcurrencyBehavior => 'When limit is reached';

  @override
  String get agentActionsFormConcurrencyAllowParallel => 'Allow parallel (no limit)';

  @override
  String get agentActionsFormConcurrencyEnqueue => 'Enqueue and wait';

  @override
  String get agentActionsFormConcurrencyReject => 'Reject new runs';

  @override
  String get agentActionsFormConcurrencyIgnore => 'Run anyway (ignore limit)';

  @override
  String get agentActionsFormPathAllowlistDescription =>
      'Optional directory allowlists. Leave empty to allow any path validated at runtime.';

  @override
  String get agentActionsFormAllowedWorkingDirectories => 'Allowed working directories';

  @override
  String get agentActionsFormAllowedContextDirectories => 'Allowed context directories';

  @override
  String get agentActionsFormPathAllowlistHint => 'Comma-separated absolute paths (e.g. C:\\\\Data7\\\\bin).';

  @override
  String get agentActionsFormOutputEncodingDescription =>
      'How captured stdout and stderr are decoded during execution.';

  @override
  String get agentActionsFormStdoutEncoding => 'Stdout encoding';

  @override
  String get agentActionsFormStderrEncoding => 'Stderr encoding';

  @override
  String get agentActionsFormOutputEncodingUtf8 => 'UTF-8';

  @override
  String get agentActionsFormOutputEncodingSystemConsole => 'System console (Windows)';

  @override
  String get agentActionsFormOnAppExit => 'When the agent closes';

  @override
  String get agentActionsFormOnAppExitKill => 'Kill main process';

  @override
  String get agentActionsFormOnAppExitWaitThenKill => 'Wait, then kill main process';

  @override
  String get agentActionsFormOnAppExitLeaveRunning => 'Leave process running';

  @override
  String get agentActionsFormRemotePoliciesTitle => 'Remote execution';

  @override
  String get agentActionsFormRemotePoliciesDescription =>
      'Allow the Hub to run this saved action over Socket.IO JSON-RPC. Requires explicit local approval.';

  @override
  String get agentActionsFormRemoteExecutionEnabled => 'Allow remote Hub execution';

  @override
  String get agentActionsFormRemoteAdHocEnabled => 'Allow remote ad-hoc commands';

  @override
  String get agentActionsFormRemoteApprovedHint => 'Remote execution is approved for this definition.';

  @override
  String get agentActionsFormRemoteApprovalRequired => 'Confirm remote execution before saving.';

  @override
  String get agentActionsFormRemoteReapprovalRequiredTitle => 'Remote re-approval required';

  @override
  String get agentActionsFormRemoteReapprovalRequiredMessage =>
      'Risk-bearing fields changed since the last remote approval. Confirm remote execution again before saving.';

  @override
  String get agentActionsConfirmRemoteReapprovalTitle => 'Re-approve remote execution?';

  @override
  String get agentActionsConfirmRemoteReapprovalMessage =>
      'Command, paths, or runtime policies changed. The Hub cannot run this action remotely until you confirm again.';

  @override
  String get agentActionsConfirmRemoteReapprovalConfirm => 'Re-approve';

  @override
  String get agentActionsConfirmRemoteReapprovalCancel => 'Cancel';

  @override
  String get agentActionsFormRemoteFeatureDisabledTitle => 'Remote agent actions are off';

  @override
  String get agentActionsFormRemoteFeatureDisabledMessage =>
      'Enable the remote agent actions feature flag before the Hub can call agent.action.* for this agent.';

  @override
  String get agentActionsFormRemoteAdHocFeatureDisabledTitle => 'Remote ad-hoc disabled';

  @override
  String get agentActionsFormRemoteAdHocFeatureDisabledMessage =>
      'Enable the remote ad-hoc feature flag to allow free-form hub commands on this agent.';

  @override
  String get agentActionsRiskRemote => 'Remote';

  @override
  String get agentActionsRiskRemoteAdHoc => 'Remote ad-hoc';

  @override
  String get agentActionsRiskRemoteReapproval => 'Re-approval required';

  @override
  String get agentActionsRiskAppCloseTrigger => 'App close trigger';

  @override
  String get agentActionsRiskSensitiveOutput => 'Unredacted output';

  @override
  String get agentActionsRiskLeaveProcessRunning => 'Leaves process running';

  @override
  String get agentActionsRiskUnsupportedType => 'Unsupported editor';

  @override
  String get agentActionsRiskNeedsValidation => 'Needs validation';

  @override
  String get agentActionsRiskSecretPlaceholders => 'Uses secrets';

  @override
  String get agentActionsNeedsValidationTitle => 'Validation required';

  @override
  String get agentActionsNeedsValidationMessage =>
      'Test this action locally before running or enabling remote execution.';

  @override
  String get agentActionsSecretPlaceholdersTitle => 'Secret placeholders referenced';

  @override
  String agentActionsSecretPlaceholdersMessage(String secretNames) {
    return 'This action references secrets: $secretNames. Configure them in secure storage before running.';
  }

  @override
  String get agentActionsMissingSecretsTitle => 'Missing secrets';

  @override
  String agentActionsMissingSecretsMessage(String secretNames) {
    return 'These secrets are not available locally: $secretNames.';
  }

  @override
  String get agentActionsSecretsSectionTitle => 'Action secrets';

  @override
  String get agentActionsSecretsSectionMessage =>
      'Configure values for each secret placeholder referenced by this action. Values are stored only in secure local storage.';

  @override
  String get agentActionsSecretStatusConfigured => 'Configured';

  @override
  String get agentActionsSecretStatusMissing => 'Missing';

  @override
  String get agentActionsSecretConfigure => 'Configure';

  @override
  String get agentActionsSecretUpdate => 'Update';

  @override
  String get agentActionsSecretRemove => 'Remove';

  @override
  String agentActionsSecretConfigureTitle(String secretName) {
    return 'Configure secret $secretName';
  }

  @override
  String get agentActionsSecretConfigureMessage =>
      'Enter the secret value. It will not appear in action definitions, logs, or execution history.';

  @override
  String get agentActionsSecretConfigureValueLabel => 'Secret value';

  @override
  String get agentActionsSecretConfigureValueHint => 'Enter value';

  @override
  String get agentActionsSecretConfigureSave => 'Save';

  @override
  String get agentActionsSecretConfigureCancel => 'Cancel';

  @override
  String get agentActionsSecretConfigureErrorTitle => 'Could not save secret';

  @override
  String get agentActionsSecretDeleteTitle => 'Remove secret?';

  @override
  String agentActionsSecretDeleteMessage(String secretName) {
    return 'Remove the locally stored value for \"$secretName\"? The action will fail until the secret is configured again.';
  }

  @override
  String get agentActionsSecretDeleteConfirm => 'Remove';

  @override
  String get agentActionsSecretDeleteCancel => 'Cancel';

  @override
  String get agentActionsSecretOperationErrorTitle => 'Secret operation failed';

  @override
  String get agentActionsHistoryFilterSearch => 'Search execution';

  @override
  String get agentActionsRiskRunnerUnavailable => 'Runner unavailable';

  @override
  String get agentActionsRiskElevated => 'Elevated execution';

  @override
  String get agentActionsActionTypeUnavailableTitle => 'Runner unavailable for this action type';

  @override
  String agentActionsActionTypeUnavailableMessage(String actionType) {
    return 'The agent subsystem is degraded and cannot run $actionType actions until the runner or capability is restored.';
  }

  @override
  String agentActionsQueueActiveIndicator(int pending, int running) {
    return '$pending pending · $running running in queue';
  }

  @override
  String get agentActionsConfirmRemoteTitle => 'Enable remote execution?';

  @override
  String get agentActionsConfirmRemoteMessage =>
      'The Hub will be able to run this saved action when scopes, token policy and feature flags allow it.';

  @override
  String get agentActionsConfirmRemoteConfirm => 'Enable remote';

  @override
  String get agentActionsConfirmRemoteCancel => 'Cancel';

  @override
  String get agentActionsConfirmRemoteAdHocTitle => 'Enable remote ad-hoc commands?';

  @override
  String get agentActionsConfirmRemoteAdHocMessage =>
      'Ad-hoc remote commands are high risk and should stay disabled unless you explicitly need them.';

  @override
  String get agentActionsConfirmRemoteAdHocConfirm => 'Enable ad-hoc';

  @override
  String get agentActionsConfirmRemoteAdHocCancel => 'Cancel';

  @override
  String get agentActionsConfirmAppCloseTriggerTitle => 'Add app-close trigger?';

  @override
  String get agentActionsConfirmAppCloseTriggerMessage =>
      'This trigger runs when the Plug agent closes and may start or stop processes while the app shuts down.';

  @override
  String get agentActionsConfirmAppCloseTriggerConfirm => 'Use app close';

  @override
  String get agentActionsConfirmAppCloseTriggerCancel => 'Cancel';

  @override
  String get agentActionsConfirmElevatedTitle => 'Enable elevated execution?';

  @override
  String get agentActionsConfirmElevatedMessage =>
      'Runs use the elevated helper and administrator privileges on this machine. Install and prepare the helper before enabling.';

  @override
  String get agentActionsConfirmElevatedConfirm => 'Enable elevated';

  @override
  String get agentActionsConfirmElevatedCancel => 'Cancel';

  @override
  String get agentActionsValidationTitle => 'Check the action fields';

  @override
  String get agentActionsMaintenanceMode => 'Maintenance mode';

  @override
  String get agentActionsMaintenanceModeInfoTitle => 'Maintenance mode is on';

  @override
  String get agentActionsMaintenanceModeInfoMessage =>
      'Scheduled runs, app start/close triggers, and remote runs are paused. You can still run actions from this screen and edit definitions.';

  @override
  String get agentActionsElevatedRunnerNotReadyTitle => 'Elevated runner not prepared';

  @override
  String get agentActionsElevatedRunnerNotReadyMessage =>
      'To use elevated execution, register the helper scheduled task with high privilege. Windows may prompt for UAC once.';

  @override
  String get agentActionsElevatedRunnerDegradedTitle => 'Elevated runner unavailable';

  @override
  String get agentActionsElevatedRunnerDegradedMessage =>
      'The elevated helper failed recently. Prepare it again before running actions with high privilege.';

  @override
  String get agentActionsElevatedRunnerPrepare => 'Prepare elevated runner';

  @override
  String get agentActionsElevatedRunnerPreparing => 'Preparing elevated runner...';

  @override
  String get agentActionsFormRunElevated => 'Run with elevated privilege (Windows helper)';

  @override
  String get agentActionsFormRunElevatedHint =>
      'Requires the helper executable and a prepared scheduled task on this agent.';

  @override
  String get agentActionsSubsystemStatusStartingTitle => 'Agent actions are starting';

  @override
  String get agentActionsSubsystemStatusStartingMessage =>
      'The subsystem is still initializing. Local run and test stay disabled until it is ready.';

  @override
  String get agentActionsSubsystemStatusDrainingTitle => 'Agent actions are shutting down';

  @override
  String get agentActionsSubsystemStatusDrainingMessage =>
      'New runs are blocked while the Plug agent closes. App-close triggers may still run.';

  @override
  String get agentActionsSubsystemStatusDegradedTitle => 'Some action types are unavailable';

  @override
  String agentActionsSubsystemStatusDegradedMessage(String types) {
    return 'Unavailable types: $types. Other actions may still run from this screen.';
  }

  @override
  String get agentActionsSubsystemStatusDisabledTitle => 'Agent actions subsystem disabled';

  @override
  String get agentActionsSubsystemStatusDisabledMessage =>
      'The runtime guard reports the subsystem as disabled. Check feature flags and restart the agent if needed.';

  @override
  String get agentActionsSchedulerOperationalIssueTitle => 'Scheduled triggers are not running';

  @override
  String get agentActionsSchedulerInstanceLockedMessage =>
      'Another Plug Agente process is already running the action scheduler for this data folder. Close the other instance or use a separate data directory. Manual runs and remote actions may still work in this window.';

  @override
  String get agentActionsSchedulerBootstrapFailedMessage =>
      'The action scheduler stopped after a startup failure. Restart the agent or review saved triggers. Manual runs may still work until you fix the schedule configuration.';

  @override
  String get agentActionsComObjectHandlersMissingTitle => 'COM actions are not ready';

  @override
  String get agentActionsComObjectHandlersMissingMessage =>
      'No COM ProgID/member handlers are registered in this agent. COM actions will fail until handlers are added to ComObjectInvocationRegistry or homologation stub env vars are set (AGENT_ACTION_COM_STUB_ENABLED). See agent.getHealth com_object_invocation_ready.';

  @override
  String get agentActionsDisabledTitle => 'Actions disabled';

  @override
  String get agentActionsDisabledMessage => 'Agent actions are disabled by feature flag.';

  @override
  String get agentActionsErrorTitle => 'Action operation failed';

  @override
  String get agentActionsSummaryActions => 'Actions';

  @override
  String get agentActionsSummaryQueued => 'Queued';

  @override
  String get agentActionsSummaryRunning => 'Running';

  @override
  String get agentActionsSummaryFailed => 'Failed';

  @override
  String get agentActionsSummaryMaintenance => 'Maintenance';

  @override
  String get agentActionsSummaryMaintenanceActive => 'On';

  @override
  String get agentActionsSummaryComHandlers => 'COM handlers';

  @override
  String get agentActionsSummaryComHandlersNone => 'None';

  @override
  String get agentActionsRetentionTitle => 'Data retention';

  @override
  String get agentActionsRetentionDescription =>
      'Periodic purge removes local rows older than the windows below. Saved values here take precedence over environment variables for this installation.';

  @override
  String get agentActionsRetentionExecutionHistory => 'Terminal execution history';

  @override
  String agentActionsRetentionExecutionHistoryValue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get agentActionsRetentionRemoteAudit => 'Remote agent.action audit';

  @override
  String agentActionsRetentionRemoteAuditValue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get agentActionsRetentionCapturedOutput => 'Captured stdout/stderr on terminal rows';

  @override
  String agentActionsRetentionCapturedOutputValue(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String get agentActionsRetentionEnvVariables =>
      'Environment variables (fallback): AGENT_ACTION_EXECUTION_RETENTION_DAYS, AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS, AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS';

  @override
  String get agentActionsRetentionSave => 'Save retention';

  @override
  String get agentActionsRetentionReset => 'Discard changes';

  @override
  String get agentActionsRetentionUseEnvDefaults => 'Use environment defaults';

  @override
  String get agentActionsRetentionClearedTitle => 'Retention restored';

  @override
  String get agentActionsRetentionClearedMessage =>
      'Custom values were removed. Cleanup windows now follow environment variables or agent defaults.';

  @override
  String get agentActionsRetentionSavedTitle => 'Retention saved';

  @override
  String get agentActionsRetentionSavedMessage => 'Cleanup windows were updated for this installation.';

  @override
  String get agentActionsRetentionInvalidValue => 'Enter valid whole numbers in every field.';

  @override
  String get agentActionsRetentionPersistedHint =>
      'Custom values are stored locally and override the environment fallback.';

  @override
  String get agentActionsEmptyActions => 'No actions registered.';

  @override
  String get agentActionsListFilterType => 'Action type';

  @override
  String get agentActionsListFilterSearch => 'Search actions';

  @override
  String get agentActionsListFilterEmpty => 'No actions match the current filters.';

  @override
  String get agentActionsEmptySelection => 'Select an action to inspect execution details.';

  @override
  String get agentActionsHistoryTitle => 'Execution history';

  @override
  String get agentActionsHistoryFilterStatus => 'Status';

  @override
  String get agentActionsHistoryFilterSource => 'Source';

  @override
  String get agentActionsHistoryFilterPeriod => 'Period';

  @override
  String get agentActionsHistoryFilterFailurePhase => 'Failure phase';

  @override
  String get agentActionsHistoryFilterAll => 'All';

  @override
  String get agentActionsHistoryPeriodAll => 'All';

  @override
  String get agentActionsHistoryPeriodLast24Hours => 'Last 24 hours';

  @override
  String get agentActionsHistoryPeriodLast3Days => 'Last 3 days';

  @override
  String get agentActionsRemoteAuditTitle => 'Remote agent.action audit';

  @override
  String get agentActionsRemoteAuditDescription =>
      'Recent Hub JSON-RPC and execution lifecycle rows for agent.action.* (append-only; retention and purge still apply).';

  @override
  String get agentActionsRemoteAuditFilterAll => 'All';

  @override
  String get agentActionsRemoteAuditFilterRpc => 'RPC';

  @override
  String get agentActionsRemoteAuditFilterLifecycle => 'Lifecycle';

  @override
  String get agentActionsRemoteAuditFilterEmpty => 'No rows match this filter.';

  @override
  String get agentActionsRemoteAuditOutcomeReceived => 'Received';

  @override
  String get agentActionsRemoteAuditOutcomeSuccess => 'Success';

  @override
  String get agentActionsRemoteAuditOutcomeRpcError => 'RPC error';

  @override
  String get agentActionsRemoteAuditOutcomeAuthorizationDenied => 'Authorization denied';

  @override
  String get agentActionsRemoteAuditOutcomeNotificationRejected => 'Notification rejected';

  @override
  String get agentActionsRemoteAuditOutcomeRateLimited => 'Rate limited';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleEnqueued => 'Enqueued';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleStarted => 'Started';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleCancelRequested => 'Cancel requested';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleFinished => 'Finished';

  @override
  String get agentActionsRemoteAuditEmpty => 'No remote audit rows recorded yet.';

  @override
  String get agentActionsRemoteAuditRefresh => 'Reload';

  @override
  String get agentActionsRemoteAuditCopyJson => 'Copy as JSON';

  @override
  String get agentActionsRemoteAuditCopiedToast => 'Audit copied to the clipboard.';

  @override
  String get agentActionsRemoteAuditShowInHistory => 'Show in history';

  @override
  String agentActionsRemoteAuditExecutionNotInHistory(Object executionId) {
    return 'Execution $executionId is not in the loaded history. It may be outside the retention window or list limit.';
  }

  @override
  String agentActionsRemoteAuditRuntimeInstanceMismatch(Object executionId, Object auditInstanceId) {
    return 'Execution $executionId belongs to another agent installation (audit instance $auditInstanceId). Local history only highlights when the runtime instance matches.';
  }

  @override
  String get agentActionsRemoteAuditFieldAction => 'Action';

  @override
  String get agentActionsRemoteAuditFieldExecution => 'Execution';

  @override
  String get agentActionsRemoteAuditFieldTrace => 'Trace';

  @override
  String get agentActionsRemoteAuditFieldRequestedBy => 'Requester';

  @override
  String get agentActionsRemoteAuditFieldIdempotencyKey => 'Idempotency';

  @override
  String get agentActionsRemoteAuditFieldReason => 'Reason';

  @override
  String get agentActionsRemoteAuditFieldClient => 'Client';

  @override
  String get agentActionsRemoteAuditFieldRuntimeInstance => 'Instance';

  @override
  String get agentActionsRemoteAuditFieldRuntimeSession => 'Session';

  @override
  String get agentActionsRemoteAuditReasonMissingClientToken => 'Client token missing';

  @override
  String get agentActionsRemoteAuditReasonPermissionDenied => 'Permission denied';

  @override
  String get agentActionsRemoteAuditReasonRemoteRateLimited => 'Remote rate limit';

  @override
  String get agentActionsRemoteAuditReasonRemoteDisabled => 'Remote actions disabled';

  @override
  String get agentActionsRemoteAuditReasonFeatureDisabled => 'Agent actions disabled';

  @override
  String get agentActionsRemoteAuditReasonMaintenanceMode => 'Maintenance mode';

  @override
  String get agentActionsRemoteAuditReasonNotificationNotAllowed => 'Notification not allowed';

  @override
  String get agentActionsRemoteAuditReasonRemoteContextNotSupported => 'Remote context not supported';

  @override
  String get agentActionsRemoteAuditReasonIdempotencyRequired => 'Idempotency key required';

  @override
  String get agentActionsRemoteAuditReasonIdempotencyMismatch => 'Idempotency fingerprint mismatch';

  @override
  String get agentActionsRemoteAuditReasonBatchNotAllowed => 'Method not allowed in batch';

  @override
  String get agentActionsRemoteAuditReasonExecutionNotFound => 'Execution not found';

  @override
  String get agentActionsRemoteAuditReasonAlreadyFinished => 'Already finished';

  @override
  String get agentActionsRemoteAuditReasonKillFailed => 'Kill failed';

  @override
  String get agentActionsEmptyHistory => 'No executions recorded for this action.';

  @override
  String get agentActionsTriggersTitle => 'Schedules and triggers';

  @override
  String get agentActionsTriggersEmpty => 'No triggers saved for this action.';

  @override
  String get agentActionsTriggersLoading => 'Loading triggers…';

  @override
  String get agentActionsTriggerEnabled => 'Enabled';

  @override
  String get agentActionsTriggerDisabled => 'Disabled';

  @override
  String get agentActionsTriggerUnnamed => 'Unnamed trigger';

  @override
  String get agentActionsTriggerNotScheduled => 'Not scheduled';

  @override
  String agentActionsTriggerNextRun(Object when) {
    return 'Next run: $when';
  }

  @override
  String agentActionsTriggerSummaryTimeZone(Object ianaId) {
    return 'Time zone: $ianaId';
  }

  @override
  String get agentActionsTriggerSummaryCatchUpEnabled => 'Catch-up for missed runs enabled';

  @override
  String get agentActionsTriggerTypeManual => 'Manual';

  @override
  String get agentActionsTriggerTypeRemote => 'Remote';

  @override
  String get agentActionsTriggerTypeOnce => 'Once';

  @override
  String get agentActionsTriggerTypeInterval => 'Interval';

  @override
  String get agentActionsTriggerTypeDaily => 'Daily';

  @override
  String get agentActionsTriggerTypeWeekly => 'Weekly';

  @override
  String get agentActionsTriggerTypeMonthly => 'Monthly';

  @override
  String get agentActionsTriggerTypeAppStart => 'App start';

  @override
  String get agentActionsTriggerTypeAppClose => 'App close';

  @override
  String get agentActionsTriggerDelete => 'Delete trigger';

  @override
  String get agentActionsTriggerDeleteConfirmTitle => 'Delete trigger';

  @override
  String agentActionsTriggerDeleteConfirmMessage(Object triggerLabel) {
    return 'Delete \"$triggerLabel\"? Scheduled runs stop for this trigger.';
  }

  @override
  String get agentActionsTriggerDeleteConfirm => 'Delete';

  @override
  String get agentActionsTriggerDeleteCancel => 'Cancel';

  @override
  String get agentActionsTriggerAdd => 'Add trigger';

  @override
  String get agentActionsTriggerEdit => 'Edit trigger';

  @override
  String get agentActionsTriggerSave => 'Save trigger';

  @override
  String get agentActionsTriggerCancel => 'Cancel';

  @override
  String get agentActionsTriggerEditorTitleNew => 'New trigger';

  @override
  String get agentActionsTriggerEditorTitleEdit => 'Edit trigger';

  @override
  String get agentActionsTriggerFieldName => 'Display name';

  @override
  String get agentActionsTriggerFieldType => 'Trigger type';

  @override
  String get agentActionsTriggerFieldTimezone => 'IANA time zone (optional)';

  @override
  String get agentActionsTriggerFieldTimezoneFilter => 'Filter IANA zones';

  @override
  String get agentActionsTriggerHintTimezoneFilter => 'e.g. America, Europe, UTC';

  @override
  String get agentActionsTriggerHintTimezonePick =>
      'Tap a row to fill the field above. Leave empty to use the device default.';

  @override
  String get agentActionsTriggerHintTimezoneSearchEmpty => 'Type in the filter to search IANA time zones.';

  @override
  String get agentActionsTriggerTimezoneNoMatches => 'No time zone matches the filter.';

  @override
  String agentActionsTriggerTimezoneMatchesTruncated(int count) {
    return 'Showing the first $count matches. Refine the filter.';
  }

  @override
  String get agentActionsTriggerFieldStartAt => 'Start date and time';

  @override
  String get agentActionsTriggerFieldStartAtOptional => 'Active from (optional)';

  @override
  String get agentActionsTriggerFieldEndAtOptional => 'Active until (optional)';

  @override
  String get agentActionsTriggerFieldIntervalMinutes => 'Interval (minutes)';

  @override
  String get agentActionsTriggerFieldTimeOfDay => 'Time of day';

  @override
  String get agentActionsTriggerHintTimeOfDay => 'HH:mm (24-hour)';

  @override
  String get agentActionsTriggerFieldWeekdays => 'Weekdays';

  @override
  String get agentActionsTriggerFieldDayOfMonth => 'Day of month (1-31)';

  @override
  String get agentActionsTriggerHintDateTime => 'Format: yyyy-MM-dd HH:mm (local)';

  @override
  String get agentActionsTriggerFieldIgnoreMissedRuns => 'Ignore missed runs during downtime';

  @override
  String get agentActionsTriggerHintIgnoreMissedRuns =>
      'Turn off to run schedules that were missed while the app was closed, when the trigger type supports catch-up.';

  @override
  String get agentActionsTriggerValidationTitle => 'Check the trigger fields';

  @override
  String get agentActionsTriggerValidationInvalidStartAt => 'Enter a valid start date and time.';

  @override
  String get agentActionsTriggerValidationInvalidIntervalMinutes => 'Enter a positive whole number of minutes.';

  @override
  String get agentActionsTriggerValidationInvalidTimeOfDay => 'Enter the time as HH:mm using a 24-hour clock.';

  @override
  String get agentActionsTriggerValidationWeekdaysRequired => 'Select at least one weekday.';

  @override
  String get agentActionsTriggerValidationInvalidDayOfMonth => 'Enter a day of month between 1 and 31.';

  @override
  String get agentActionsTriggerWeekdayMon => 'Mon';

  @override
  String get agentActionsTriggerWeekdayTue => 'Tue';

  @override
  String get agentActionsTriggerWeekdayWed => 'Wed';

  @override
  String get agentActionsTriggerWeekdayThu => 'Thu';

  @override
  String get agentActionsTriggerWeekdayFri => 'Fri';

  @override
  String get agentActionsTriggerWeekdaySat => 'Sat';

  @override
  String get agentActionsTriggerWeekdaySun => 'Sun';

  @override
  String get agentActionsRequestedAt => 'Requested at';

  @override
  String get agentActionsExitCode => 'Exit code';

  @override
  String get agentActionsSourceLocalUi => 'Local UI';

  @override
  String get agentActionsSourceScheduler => 'Scheduler';

  @override
  String get agentActionsSourceRemoteHub => 'Hub';

  @override
  String get agentActionsSourceAppLifecycle => 'App lifecycle';

  @override
  String get agentActionsDiagnosticsCopySupport => 'Copy support JSON';

  @override
  String get agentActionsDiagnosticsCopiedToast => 'Diagnostics copied to the clipboard.';

  @override
  String get agentActionsDiagnosticsTitle => 'Diagnostics';

  @override
  String get agentActionsDiagnosticsExecutionId => 'Execution';

  @override
  String get agentActionsDiagnosticsSource => 'Source';

  @override
  String get agentActionsDiagnosticsPid => 'PID';

  @override
  String get agentActionsDiagnosticsStartedAt => 'Started';

  @override
  String get agentActionsDiagnosticsFinishedAt => 'Finished';

  @override
  String get agentActionsDiagnosticsTimeoutAt => 'Timeout';

  @override
  String get agentActionsDiagnosticsDuration => 'Duration';

  @override
  String get agentActionsDiagnosticsExecutable => 'Executable';

  @override
  String get agentActionsDiagnosticsArgumentCount => 'Arguments';

  @override
  String get agentActionsDiagnosticsCommandPreview => 'Command preview';

  @override
  String get agentActionsDiagnosticsFailureCode => 'Failure code';

  @override
  String get agentActionsDiagnosticsFailurePhase => 'Failure phase';

  @override
  String get agentActionsFailurePhaseExecutionPreflight => 'Execution preflight';

  @override
  String get agentActionsFailurePhaseDefinitionValidation => 'Definition validation';

  @override
  String get agentActionsFailurePhaseStartProcess => 'Process start';

  @override
  String get agentActionsFailurePhaseStdinSetup => 'Stdin setup';

  @override
  String get agentActionsFailurePhaseProcessRuntime => 'Process runtime';

  @override
  String get agentActionsFailurePhaseProcessExit => 'Process exit';

  @override
  String get agentActionsFailurePhaseQueue => 'Queue';

  @override
  String get agentActionsFailurePhaseTimeout => 'Timeout';

  @override
  String get agentActionsFailurePhaseAuthorization => 'Authorization';

  @override
  String get agentActionsFailurePhaseValidation => 'Validation';

  @override
  String get agentActionsFailurePhaseLookup => 'Lookup';

  @override
  String get agentActionsFailurePhaseCancel => 'Cancellation';

  @override
  String get agentActionsFailurePhasePlatformCheck => 'Platform check';

  @override
  String get agentActionsFailurePhaseSmtpSend => 'SMTP send';

  @override
  String get agentActionsFailurePhaseExecutionSend => 'Send preparation';

  @override
  String get agentActionsFailurePhaseElevatedSubmit => 'Elevated submit';

  @override
  String get agentActionsFailurePhaseBootstrapReconciliation => 'Bootstrap reconciliation';

  @override
  String agentActionsExecutionFailurePhaseLabel(String phase) {
    return 'Failed during: $phase';
  }

  @override
  String get agentActionsDiagnosticsCorrectiveAction => 'Corrective action';

  @override
  String get agentActionsDiagnosticsCorrectivePath =>
      'Review the saved path, validate the file or directory again, and update the action before running it.';

  @override
  String get agentActionsDiagnosticsCorrectiveRunner =>
      'Check the configured executable, interpreter, or runner path and validate the action again.';

  @override
  String get agentActionsDiagnosticsCorrectiveExitCode =>
      'Review the exit code and the redacted output. Adjust accepted exit codes or fix the executed command.';

  @override
  String get agentActionsDiagnosticsCorrectiveQueue =>
      'Wait for the queue to drain or adjust the action concurrency and queue limits.';

  @override
  String get agentActionsDiagnosticsCorrectiveTimeout =>
      'Review the configured timeout and investigate why the process did not finish within the expected window.';

  @override
  String get agentActionsDiagnosticsCorrectiveKill =>
      'Verify whether the main process is still running and try canceling again after reviewing PID and permissions.';

  @override
  String get agentActionsDiagnosticsCorrectiveDefinitionValidation =>
      'Review required fields and validate the action definition again before running it.';

  @override
  String get agentActionsDiagnosticsCorrectivePreflight =>
      'Revalidate paths, permissions, context, and local prerequisites before starting the execution.';

  @override
  String get agentActionsDiagnosticsCorrectiveStartProcess =>
      'Check executable, arguments, and working directory before trying to start the process again.';

  @override
  String get agentActionsDiagnosticsCorrectiveRuntime =>
      'Inspect the redacted output and operational details to identify the failure that happened during execution.';

  @override
  String get agentActionsDiagnosticsStdout => 'stdout';

  @override
  String get agentActionsDiagnosticsStderr => 'stderr';

  @override
  String get agentActionsDiagnosticsTruncated => 'truncated';

  @override
  String get agentActionsDiagnosticsStoredInChunks => 'stored in segments';

  @override
  String get agentActionsExecutionOutputInChunks => 'large output in segments';

  @override
  String get agentActionsDiagnosticsOutputLoadFailed => 'Could not load captured output';

  @override
  String get agentActionsDiagnosticsLoadMoreStdout => 'Load more stdout';

  @override
  String get agentActionsDiagnosticsLoadMoreStderr => 'Load more stderr';

  @override
  String get agentActionsDiagnosticsDefinitionSnapshotHash => 'Definition snapshot hash';

  @override
  String get agentActionsDiagnosticsContextHash => 'Context hash';

  @override
  String get agentActionsDiagnosticsRedactionApplied => 'Redaction applied';

  @override
  String get agentActionsDiagnosticsValueYes => 'Yes';

  @override
  String get agentActionsDiagnosticsValueNo => 'No';

  @override
  String get agentActionsDiagnosticsQueueStartedAt => 'Queue started';

  @override
  String get agentActionsDiagnosticsIdempotencyKey => 'Idempotency key';

  @override
  String get agentActionsDiagnosticsRequestedBy => 'Requested by';

  @override
  String get agentActionsDiagnosticsTraceId => 'Trace id';

  @override
  String get agentActionsDiagnosticsRuntimeInstanceId => 'Runtime instance id';

  @override
  String get agentActionsDiagnosticsRuntimeSessionId => 'Runtime session id';

  @override
  String get agentActionsDiagnosticsTriggerId => 'Trigger';

  @override
  String get agentActionsDiagnosticsTriggerType => 'Trigger type';

  @override
  String get agentActionsDiagnosticsScheduledAt => 'Scheduled for';

  @override
  String get agentActionsDiagnosticsTriggeredAt => 'Triggered at';

  @override
  String get agentActionsTypeCommandLine => 'Command line';

  @override
  String get agentActionsTypePowerShell => 'PowerShell';

  @override
  String get agentActionsTypeExecutable => 'Executable';

  @override
  String get agentActionsTypeScript => 'Script';

  @override
  String get agentActionsTypeJar => 'JAR';

  @override
  String get agentActionsTypeEmail => 'Email';

  @override
  String get agentActionsTypeComObject => 'COM object';

  @override
  String get agentActionsTypeDeveloper => 'Developer';

  @override
  String get agentActionsStateActive => 'Active';

  @override
  String get agentActionsStatePaused => 'Paused';

  @override
  String get agentActionsStateDisabled => 'Disabled';

  @override
  String get agentActionsStateNeedsValidation => 'Needs validation';

  @override
  String get agentActionsStatusQueued => 'Queued';

  @override
  String get agentActionsStatusRunning => 'Running';

  @override
  String get agentActionsStatusSucceeded => 'Succeeded';

  @override
  String get agentActionsStatusFailed => 'Failed';

  @override
  String get agentActionsStatusSkipped => 'Skipped';

  @override
  String get agentActionsStatusCancelled => 'Cancelled';

  @override
  String get agentActionsStatusKilled => 'Killed';

  @override
  String get agentActionsStatusTimedOut => 'Timed out';

  @override
  String get agentActionsStatusInterrupted => 'Interrupted';

  @override
  String get agentActionsStatusUnknown => 'Unknown';

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
  String get btnClose => 'Close';

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
  String get msgRpcAgentActionsTemporarilyUnavailable =>
      'Agent actions are temporarily unavailable. Wait and try again.';

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
