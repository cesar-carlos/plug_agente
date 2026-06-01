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

  /// No description provided for @navAgentActions.
  ///
  /// In en, this message translates to:
  /// **'System Actions'**
  String get navAgentActions;

  /// No description provided for @agentActionsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get agentActionsRefresh;

  /// No description provided for @agentActionsRunSelected.
  ///
  /// In en, this message translates to:
  /// **'Run selected'**
  String get agentActionsRunSelected;

  /// No description provided for @agentActionsMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get agentActionsMoreActions;

  /// No description provided for @agentActionsTestSelected.
  ///
  /// In en, this message translates to:
  /// **'Test action'**
  String get agentActionsTestSelected;

  /// No description provided for @agentActionsCancelExecution.
  ///
  /// In en, this message translates to:
  /// **'Cancel execution'**
  String get agentActionsCancelExecution;

  /// No description provided for @agentActionsDeleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete action'**
  String get agentActionsDeleteSelected;

  /// No description provided for @agentActionsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete action'**
  String get agentActionsDeleteConfirmTitle;

  /// No description provided for @agentActionsDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{actionName}\"? Execution history is preserved, but this action can no longer be run.'**
  String agentActionsDeleteConfirmMessage(Object actionName);

  /// No description provided for @agentActionsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get agentActionsDeleteConfirm;

  /// No description provided for @agentActionsDeleteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsDeleteCancel;

  /// No description provided for @agentActionsEditorDiscardConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get agentActionsEditorDiscardConfirmTitle;

  /// No description provided for @agentActionsEditorDiscardConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes in this action. Closing now will discard them.'**
  String get agentActionsEditorDiscardConfirmMessage;

  /// No description provided for @agentActionsEditorDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get agentActionsEditorDiscardConfirm;

  /// No description provided for @agentActionsEditorKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get agentActionsEditorKeepEditing;

  /// No description provided for @agentActionsExportBundle.
  ///
  /// In en, this message translates to:
  /// **'Export actions…'**
  String get agentActionsExportBundle;

  /// No description provided for @agentActionsImportBundle.
  ///
  /// In en, this message translates to:
  /// **'Import actions…'**
  String get agentActionsImportBundle;

  /// No description provided for @agentActionsExportBundleDefaultFileName.
  ///
  /// In en, this message translates to:
  /// **'plug_agente_actions.json'**
  String get agentActionsExportBundleDefaultFileName;

  /// No description provided for @agentActionsExportBundleSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Actions exported'**
  String get agentActionsExportBundleSuccessTitle;

  /// No description provided for @agentActionsExportBundleSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'The sanitized action bundle was saved. Secret values were not included; configure placeholders on the target machine.'**
  String get agentActionsExportBundleSuccessMessage;

  /// No description provided for @agentActionsImportBundleSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Actions imported'**
  String get agentActionsImportBundleSuccessTitle;

  /// No description provided for @agentActionsImportBundleSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Imported {definitionCount, plural, =1{1 action} other{{definitionCount} actions}} and {triggerCount, plural, =1{1 trigger} other{{triggerCount} triggers}}. Definitions need validation before run.'**
  String agentActionsImportBundleSuccessMessage(int definitionCount, int triggerCount);

  /// No description provided for @agentActionsImportBundleSecretsMessage.
  ///
  /// In en, this message translates to:
  /// **'Configure these secret placeholders on this machine: {secretNames}.'**
  String agentActionsImportBundleSecretsMessage(Object secretNames);

  /// No description provided for @agentActionsConfirmImportBundleTitle.
  ///
  /// In en, this message translates to:
  /// **'Import actions'**
  String get agentActionsConfirmImportBundleTitle;

  /// No description provided for @agentActionsConfirmImportBundleMessage.
  ///
  /// In en, this message translates to:
  /// **'Import actions from a JSON bundle? Existing actions with the same id will be updated. Triggers are imported paused and remote execution requires reapproval.'**
  String get agentActionsConfirmImportBundleMessage;

  /// No description provided for @agentActionsConfirmImportBundleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get agentActionsConfirmImportBundleConfirm;

  /// No description provided for @agentActionsConfirmImportBundleCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsConfirmImportBundleCancel;

  /// No description provided for @agentActionsBundleTransferFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Action bundle transfer failed'**
  String get agentActionsBundleTransferFailedTitle;

  /// No description provided for @agentActionsBundlePickerError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker.'**
  String get agentActionsBundlePickerError;

  /// No description provided for @agentActionsGridColumnRisksTriggers.
  ///
  /// In en, this message translates to:
  /// **'Risks/Triggers'**
  String get agentActionsGridColumnRisksTriggers;

  /// No description provided for @agentActionsBundleExportWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not write the export file. Check the file path and permissions.'**
  String get agentActionsBundleExportWriteFailed;

  /// No description provided for @agentActionsBundleImportReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the import file. Check the file path and permissions.'**
  String get agentActionsBundleImportReadFailed;

  /// No description provided for @agentActionsTestSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Action test completed'**
  String get agentActionsTestSuccessTitle;

  /// No description provided for @agentActionsTestCanRunMessage.
  ///
  /// In en, this message translates to:
  /// **'The action configuration is valid and the action can run.'**
  String get agentActionsTestCanRunMessage;

  /// No description provided for @agentActionsTestValidButInactiveMessage.
  ///
  /// In en, this message translates to:
  /// **'The action configuration is valid, but the action is not active.'**
  String get agentActionsTestValidButInactiveMessage;

  /// No description provided for @agentActionsTestPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Redacted test preview'**
  String get agentActionsTestPreviewTitle;

  /// No description provided for @agentActionsTestPreviewCommandLabel.
  ///
  /// In en, this message translates to:
  /// **'Prepared command'**
  String get agentActionsTestPreviewCommandLabel;

  /// No description provided for @agentActionsTestPreviewUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable'**
  String get agentActionsTestPreviewUnavailableTitle;

  /// No description provided for @agentActionsTestPreviewDiagnosticEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get agentActionsTestPreviewDiagnosticEngine;

  /// No description provided for @agentActionsTestPreviewDiagnosticConnectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get agentActionsTestPreviewDiagnosticConnectionLabel;

  /// No description provided for @agentActionsTestPreviewDiagnosticCatalogCount.
  ///
  /// In en, this message translates to:
  /// **'Catalog connections'**
  String get agentActionsTestPreviewDiagnosticCatalogCount;

  /// No description provided for @agentActionsTestPreviewDiagnosticDefaultConfig.
  ///
  /// In en, this message translates to:
  /// **'Used default config'**
  String get agentActionsTestPreviewDiagnosticDefaultConfig;

  /// No description provided for @agentActionsTestPreviewDiagnosticYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get agentActionsTestPreviewDiagnosticYes;

  /// No description provided for @agentActionsTestPreviewDiagnosticNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get agentActionsTestPreviewDiagnosticNo;

  /// No description provided for @agentActionsFormCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New command line action'**
  String get agentActionsFormCreateTitle;

  /// No description provided for @agentActionsFormEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Command line action'**
  String get agentActionsFormEditTitle;

  /// No description provided for @agentActionsFormCreateDeveloperTitle.
  ///
  /// In en, this message translates to:
  /// **'New developer action'**
  String get agentActionsFormCreateDeveloperTitle;

  /// No description provided for @agentActionsFormEditDeveloperTitle.
  ///
  /// In en, this message translates to:
  /// **'Developer action'**
  String get agentActionsFormEditDeveloperTitle;

  /// No description provided for @agentActionsFormCreateExecutableTitle.
  ///
  /// In en, this message translates to:
  /// **'New executable action'**
  String get agentActionsFormCreateExecutableTitle;

  /// No description provided for @agentActionsFormEditExecutableTitle.
  ///
  /// In en, this message translates to:
  /// **'Executable action'**
  String get agentActionsFormEditExecutableTitle;

  /// No description provided for @agentActionsFormExecutablePath.
  ///
  /// In en, this message translates to:
  /// **'Executable path'**
  String get agentActionsFormExecutablePath;

  /// No description provided for @agentActionsFormArguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get agentActionsFormArguments;

  /// No description provided for @agentActionsFormArgumentsHint.
  ///
  /// In en, this message translates to:
  /// **'Enter one argument per line.'**
  String get agentActionsFormArgumentsHint;

  /// No description provided for @agentActionsFormBrowseExecutablePath.
  ///
  /// In en, this message translates to:
  /// **'Browse executable'**
  String get agentActionsFormBrowseExecutablePath;

  /// No description provided for @agentActionsFormCreateScriptTitle.
  ///
  /// In en, this message translates to:
  /// **'New script action'**
  String get agentActionsFormCreateScriptTitle;

  /// No description provided for @agentActionsFormEditScriptTitle.
  ///
  /// In en, this message translates to:
  /// **'Script action'**
  String get agentActionsFormEditScriptTitle;

  /// No description provided for @agentActionsFormScriptPath.
  ///
  /// In en, this message translates to:
  /// **'Script path'**
  String get agentActionsFormScriptPath;

  /// No description provided for @agentActionsFormInterpreterPath.
  ///
  /// In en, this message translates to:
  /// **'Interpreter path (optional)'**
  String get agentActionsFormInterpreterPath;

  /// No description provided for @agentActionsFormInterpreterPathHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the default interpreter for the script extension.'**
  String get agentActionsFormInterpreterPathHint;

  /// No description provided for @agentActionsFormBrowseScriptPath.
  ///
  /// In en, this message translates to:
  /// **'Browse script'**
  String get agentActionsFormBrowseScriptPath;

  /// No description provided for @agentActionsFormBrowseInterpreterPath.
  ///
  /// In en, this message translates to:
  /// **'Browse interpreter'**
  String get agentActionsFormBrowseInterpreterPath;

  /// No description provided for @agentActionsFormCreatePowerShellTitle.
  ///
  /// In en, this message translates to:
  /// **'New PowerShell action'**
  String get agentActionsFormCreatePowerShellTitle;

  /// No description provided for @agentActionsFormEditPowerShellTitle.
  ///
  /// In en, this message translates to:
  /// **'PowerShell action'**
  String get agentActionsFormEditPowerShellTitle;

  /// No description provided for @agentActionsFormPowerShellMode.
  ///
  /// In en, this message translates to:
  /// **'PowerShell mode'**
  String get agentActionsFormPowerShellMode;

  /// No description provided for @agentActionsFormPowerShellModeCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get agentActionsFormPowerShellModeCommand;

  /// No description provided for @agentActionsFormPowerShellModeScript.
  ///
  /// In en, this message translates to:
  /// **'Script .ps1'**
  String get agentActionsFormPowerShellModeScript;

  /// No description provided for @agentActionsFormPowerShellExecutable.
  ///
  /// In en, this message translates to:
  /// **'PowerShell executable'**
  String get agentActionsFormPowerShellExecutable;

  /// No description provided for @agentActionsFormPowerShellExecutableWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows PowerShell'**
  String get agentActionsFormPowerShellExecutableWindows;

  /// No description provided for @agentActionsFormPowerShellExecutablePwsh.
  ///
  /// In en, this message translates to:
  /// **'PowerShell 7'**
  String get agentActionsFormPowerShellExecutablePwsh;

  /// No description provided for @agentActionsFormPowerShellCommand.
  ///
  /// In en, this message translates to:
  /// **'PowerShell command'**
  String get agentActionsFormPowerShellCommand;

  /// No description provided for @agentActionsFormPowerShellScriptPath.
  ///
  /// In en, this message translates to:
  /// **'PowerShell script path'**
  String get agentActionsFormPowerShellScriptPath;

  /// No description provided for @agentActionsFormBrowsePowerShellScriptPath.
  ///
  /// In en, this message translates to:
  /// **'Browse PowerShell script'**
  String get agentActionsFormBrowsePowerShellScriptPath;

  /// No description provided for @agentActionsFormPowerShellScriptPathInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use a .ps1 file for PowerShell script mode.'**
  String get agentActionsFormPowerShellScriptPathInvalid;

  /// No description provided for @agentActionsFormPowerShellModeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected PowerShell mode is unavailable in the current runtime.'**
  String get agentActionsFormPowerShellModeUnavailable;

  /// No description provided for @agentActionsFormCreateJarTitle.
  ///
  /// In en, this message translates to:
  /// **'New JAR action'**
  String get agentActionsFormCreateJarTitle;

  /// No description provided for @agentActionsFormEditJarTitle.
  ///
  /// In en, this message translates to:
  /// **'JAR action'**
  String get agentActionsFormEditJarTitle;

  /// No description provided for @agentActionsFormJarPath.
  ///
  /// In en, this message translates to:
  /// **'JAR file path'**
  String get agentActionsFormJarPath;

  /// No description provided for @agentActionsFormJavaExecutablePath.
  ///
  /// In en, this message translates to:
  /// **'Java executable path (optional)'**
  String get agentActionsFormJavaExecutablePath;

  /// No description provided for @agentActionsFormJavaExecutablePathHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use java.exe from PATH.'**
  String get agentActionsFormJavaExecutablePathHint;

  /// No description provided for @agentActionsFormBrowseJarPath.
  ///
  /// In en, this message translates to:
  /// **'Browse JAR file'**
  String get agentActionsFormBrowseJarPath;

  /// No description provided for @agentActionsFormBrowseJavaExecutablePath.
  ///
  /// In en, this message translates to:
  /// **'Browse java.exe'**
  String get agentActionsFormBrowseJavaExecutablePath;

  /// No description provided for @agentActionsFormCreateEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'New email action'**
  String get agentActionsFormCreateEmailTitle;

  /// No description provided for @agentActionsFormEditEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email action'**
  String get agentActionsFormEditEmailTitle;

  /// No description provided for @agentActionsFormSmtpProfileId.
  ///
  /// In en, this message translates to:
  /// **'SMTP profile secret name'**
  String get agentActionsFormSmtpProfileId;

  /// No description provided for @agentActionsFormSmtpProfileIdHint.
  ///
  /// In en, this message translates to:
  /// **'Name of the secret that stores the SMTP JSON profile.'**
  String get agentActionsFormSmtpProfileIdHint;

  /// No description provided for @agentActionsFormEmailFrom.
  ///
  /// In en, this message translates to:
  /// **'From address'**
  String get agentActionsFormEmailFrom;

  /// No description provided for @agentActionsFormEmailTo.
  ///
  /// In en, this message translates to:
  /// **'To recipients'**
  String get agentActionsFormEmailTo;

  /// No description provided for @agentActionsFormEmailToHint.
  ///
  /// In en, this message translates to:
  /// **'One email address per line.'**
  String get agentActionsFormEmailToHint;

  /// No description provided for @agentActionsFormEmailCc.
  ///
  /// In en, this message translates to:
  /// **'Cc recipients (optional)'**
  String get agentActionsFormEmailCc;

  /// No description provided for @agentActionsFormEmailCcHint.
  ///
  /// In en, this message translates to:
  /// **'One email address per line.'**
  String get agentActionsFormEmailCcHint;

  /// No description provided for @agentActionsFormEmailBcc.
  ///
  /// In en, this message translates to:
  /// **'Bcc recipients (optional)'**
  String get agentActionsFormEmailBcc;

  /// No description provided for @agentActionsFormEmailBccHint.
  ///
  /// In en, this message translates to:
  /// **'One email address per line.'**
  String get agentActionsFormEmailBccHint;

  /// No description provided for @agentActionsFormEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject template'**
  String get agentActionsFormEmailSubject;

  /// No description provided for @agentActionsFormEmailSubjectHint.
  ///
  /// In en, this message translates to:
  /// **'Use context tokens resolved from the optional context JSON file.'**
  String get agentActionsFormEmailSubjectHint;

  /// No description provided for @agentActionsFormEmailBody.
  ///
  /// In en, this message translates to:
  /// **'Body template'**
  String get agentActionsFormEmailBody;

  /// No description provided for @agentActionsFormEmailBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Plain text body. Use context tokens resolved from the optional context JSON file.'**
  String get agentActionsFormEmailBodyHint;

  /// No description provided for @agentActionsFormEmailAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachment paths (optional)'**
  String get agentActionsFormEmailAttachments;

  /// No description provided for @agentActionsFormEmailAttachmentsHint.
  ///
  /// In en, this message translates to:
  /// **'One file path per line. Allowed types are validated by the action policy.'**
  String get agentActionsFormEmailAttachmentsHint;

  /// No description provided for @agentActionsFormCreateComObjectTitle.
  ///
  /// In en, this message translates to:
  /// **'New COM object action'**
  String get agentActionsFormCreateComObjectTitle;

  /// No description provided for @agentActionsFormEditComObjectTitle.
  ///
  /// In en, this message translates to:
  /// **'COM object action'**
  String get agentActionsFormEditComObjectTitle;

  /// No description provided for @agentActionsFormComProgId.
  ///
  /// In en, this message translates to:
  /// **'COM ProgID'**
  String get agentActionsFormComProgId;

  /// No description provided for @agentActionsFormComMemberName.
  ///
  /// In en, this message translates to:
  /// **'COM member'**
  String get agentActionsFormComMemberName;

  /// No description provided for @agentActionsFormComArguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments (JSON object)'**
  String get agentActionsFormComArguments;

  /// No description provided for @agentActionsFormComArgumentsHint.
  ///
  /// In en, this message translates to:
  /// **'Use a flat JSON object with string, number, or boolean values.'**
  String get agentActionsFormComArgumentsHint;

  /// No description provided for @agentActionsFormInvalidComArguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments must be a valid JSON object.'**
  String get agentActionsFormInvalidComArguments;

  /// No description provided for @agentActionsFormNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get agentActionsFormNew;

  /// No description provided for @agentActionsFormSave.
  ///
  /// In en, this message translates to:
  /// **'Save action'**
  String get agentActionsFormSave;

  /// No description provided for @agentActionsFormName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get agentActionsFormName;

  /// No description provided for @agentActionsFormDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get agentActionsFormDescription;

  /// No description provided for @agentActionsFormType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get agentActionsFormType;

  /// No description provided for @agentActionsFormCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get agentActionsFormCommand;

  /// No description provided for @agentActionsFormWorkingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Working directory'**
  String get agentActionsFormWorkingDirectory;

  /// No description provided for @agentActionsFormExecutorPath.
  ///
  /// In en, this message translates to:
  /// **'Executor.exe path'**
  String get agentActionsFormExecutorPath;

  /// No description provided for @agentActionsFormProjectPath.
  ///
  /// In en, this message translates to:
  /// **'.7Proj file path'**
  String get agentActionsFormProjectPath;

  /// No description provided for @agentActionsFormData7ConfigPath.
  ///
  /// In en, this message translates to:
  /// **'Data7.Config path'**
  String get agentActionsFormData7ConfigPath;

  /// No description provided for @agentActionsFormBrowseExecutorPath.
  ///
  /// In en, this message translates to:
  /// **'Browse Executor.exe'**
  String get agentActionsFormBrowseExecutorPath;

  /// No description provided for @agentActionsFormBrowseProjectPath.
  ///
  /// In en, this message translates to:
  /// **'Browse .7Proj file'**
  String get agentActionsFormBrowseProjectPath;

  /// No description provided for @agentActionsFormBrowseData7ConfigPath.
  ///
  /// In en, this message translates to:
  /// **'Browse Data7.Config'**
  String get agentActionsFormBrowseData7ConfigPath;

  /// No description provided for @agentActionsFormBrowseFileError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker for this action.'**
  String get agentActionsFormBrowseFileError;

  /// No description provided for @agentActionsFormUseDefaultExecutorPath.
  ///
  /// In en, this message translates to:
  /// **'Use default Executor'**
  String get agentActionsFormUseDefaultExecutorPath;

  /// No description provided for @agentActionsFormUseDefaultConfigBinPath.
  ///
  /// In en, this message translates to:
  /// **'Use default config (bin)'**
  String get agentActionsFormUseDefaultConfigBinPath;

  /// No description provided for @agentActionsFormUseDefaultConfigRootPath.
  ///
  /// In en, this message translates to:
  /// **'Use default config (root)'**
  String get agentActionsFormUseDefaultConfigRootPath;

  /// No description provided for @agentActionsFormExecutorPathHintExpectedFileName.
  ///
  /// In en, this message translates to:
  /// **'The executor path must end with Executor.exe.'**
  String get agentActionsFormExecutorPathHintExpectedFileName;

  /// No description provided for @agentActionsFormExecutorPathHintDefault.
  ///
  /// In en, this message translates to:
  /// **'The executor is pointing to the default Data7 path.'**
  String get agentActionsFormExecutorPathHintDefault;

  /// No description provided for @agentActionsFormExecutorPathHintMissing.
  ///
  /// In en, this message translates to:
  /// **'The selected Executor.exe was not found at this path.'**
  String get agentActionsFormExecutorPathHintMissing;

  /// No description provided for @agentActionsFormExecutorPathHintDirectory.
  ///
  /// In en, this message translates to:
  /// **'The executor path points to a directory, not an Executor.exe file.'**
  String get agentActionsFormExecutorPathHintDirectory;

  /// No description provided for @agentActionsFormProjectPathHintExpectedExtension.
  ///
  /// In en, this message translates to:
  /// **'The project must point to a .7Proj file.'**
  String get agentActionsFormProjectPathHintExpectedExtension;

  /// No description provided for @agentActionsFormProjectPathHintMissing.
  ///
  /// In en, this message translates to:
  /// **'The selected .7Proj file was not found at this path.'**
  String get agentActionsFormProjectPathHintMissing;

  /// No description provided for @agentActionsFormProjectPathHintDirectory.
  ///
  /// In en, this message translates to:
  /// **'The project path points to a directory, not a .7Proj file.'**
  String get agentActionsFormProjectPathHintDirectory;

  /// No description provided for @agentActionsFormData7ConfigPathHintExpectedFileName.
  ///
  /// In en, this message translates to:
  /// **'The config path must end with Data7.Config.'**
  String get agentActionsFormData7ConfigPathHintExpectedFileName;

  /// No description provided for @agentActionsFormData7ConfigPathHintDefaultBin.
  ///
  /// In en, this message translates to:
  /// **'The Data7.Config path is using the default C:\\Data7\\bin location.'**
  String get agentActionsFormData7ConfigPathHintDefaultBin;

  /// No description provided for @agentActionsFormData7ConfigPathHintDefaultRoot.
  ///
  /// In en, this message translates to:
  /// **'The Data7.Config path is using the default C:\\Data7 location.'**
  String get agentActionsFormData7ConfigPathHintDefaultRoot;

  /// No description provided for @agentActionsFormData7ConfigPathHintMissing.
  ///
  /// In en, this message translates to:
  /// **'The selected Data7.Config was not found at this path.'**
  String get agentActionsFormData7ConfigPathHintMissing;

  /// No description provided for @agentActionsFormData7ConfigPathHintDirectory.
  ///
  /// In en, this message translates to:
  /// **'The config path points to a directory, not a Data7.Config file.'**
  String get agentActionsFormData7ConfigPathHintDirectory;

  /// No description provided for @agentActionsFormPathHintInspectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not inspect this local path right now. Review permissions, links, or disk availability.'**
  String get agentActionsFormPathHintInspectionFailed;

  /// No description provided for @agentActionsFormReloadConnections.
  ///
  /// In en, this message translates to:
  /// **'Reload connections'**
  String get agentActionsFormReloadConnections;

  /// No description provided for @agentActionsFormDefaultConfigResolved.
  ///
  /// In en, this message translates to:
  /// **'Using the Data7.Config found in the default location.'**
  String get agentActionsFormDefaultConfigResolved;

  /// No description provided for @agentActionsFormResolvedConfigPath.
  ///
  /// In en, this message translates to:
  /// **'Resolved config: {path}'**
  String agentActionsFormResolvedConfigPath(Object path);

  /// No description provided for @agentActionsFormLoadedConfigPath.
  ///
  /// In en, this message translates to:
  /// **'Connections loaded from: {path}'**
  String agentActionsFormLoadedConfigPath(Object path);

  /// No description provided for @agentActionsFormConnectionId.
  ///
  /// In en, this message translates to:
  /// **'Connection ID'**
  String get agentActionsFormConnectionId;

  /// No description provided for @agentActionsFormConnectionSelector.
  ///
  /// In en, this message translates to:
  /// **'Loaded connection'**
  String get agentActionsFormConnectionSelector;

  /// No description provided for @agentActionsFormConnectionSelectorPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a loaded connection'**
  String get agentActionsFormConnectionSelectorPlaceholder;

  /// No description provided for @agentActionsFormConnectionSearch.
  ///
  /// In en, this message translates to:
  /// **'Filter loaded connections'**
  String get agentActionsFormConnectionSearch;

  /// No description provided for @agentActionsFormConnectionFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No loaded connection matches this filter.'**
  String get agentActionsFormConnectionFilterEmpty;

  /// No description provided for @agentActionsFormConnectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Safe connection label'**
  String get agentActionsFormConnectionLabel;

  /// No description provided for @agentActionsFormConnectionMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved connection not found'**
  String get agentActionsFormConnectionMissingTitle;

  /// No description provided for @agentActionsFormConnectionMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'The saved connection no longer exists in the loaded Data7.Config. Reload the connections, select another valid connection, and save the action again.'**
  String get agentActionsFormConnectionMissingMessage;

  /// No description provided for @agentActionsFormConnectionUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection ID is outside the loaded catalog'**
  String get agentActionsFormConnectionUnknownTitle;

  /// No description provided for @agentActionsFormConnectionUnknownMessage.
  ///
  /// In en, this message translates to:
  /// **'The entered ID does not belong to the catalog loaded right now. Select a valid connection from the list or reload the connections before saving.'**
  String get agentActionsFormConnectionUnknownMessage;

  /// No description provided for @agentActionsFormConnectionChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection changed since the last validation'**
  String get agentActionsFormConnectionChangedTitle;

  /// No description provided for @agentActionsFormConnectionChangedMessage.
  ///
  /// In en, this message translates to:
  /// **'The loaded connection changed since the saved snapshot. Review the configuration and save the action again before running it.'**
  String get agentActionsFormConnectionChangedMessage;

  /// No description provided for @agentActionsFormUnsupportedType.
  ///
  /// In en, this message translates to:
  /// **'The visual editor for this action type is not available on this screen yet.'**
  String get agentActionsFormUnsupportedType;

  /// No description provided for @agentActionsFormState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get agentActionsFormState;

  /// No description provided for @agentActionsHelpTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Action type'**
  String get agentActionsHelpTypeTitle;

  /// No description provided for @agentActionsHelpTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Defines the runner and internal contract used to save and run this action. After the action is created, the type becomes read-only to avoid accidental runner changes.'**
  String get agentActionsHelpTypeMessage;

  /// No description provided for @agentActionsHelpStateTitle.
  ///
  /// In en, this message translates to:
  /// **'Action state'**
  String get agentActionsHelpStateTitle;

  /// No description provided for @agentActionsHelpStateMessage.
  ///
  /// In en, this message translates to:
  /// **'Controls whether the action can run. Actions that need validation remain visible, but should not run automatically until reviewed.'**
  String get agentActionsHelpStateMessage;

  /// No description provided for @agentActionsHelpCommandTitle.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get agentActionsHelpCommandTitle;

  /// No description provided for @agentActionsHelpCommandMessage.
  ///
  /// In en, this message translates to:
  /// **'Line sent directly to the command-line runner. Include the executable and arguments as they would be called on Windows; secret placeholders stay in text for secure runtime resolution.'**
  String get agentActionsHelpCommandMessage;

  /// No description provided for @agentActionsHelpPowerShellModeTitle.
  ///
  /// In en, this message translates to:
  /// **'PowerShell mode'**
  String get agentActionsHelpPowerShellModeTitle;

  /// No description provided for @agentActionsHelpPowerShellModeMessage.
  ///
  /// In en, this message translates to:
  /// **'Command saves a generated PowerShell wrapper as a command line action. Script .ps1 saves as a script action and reuses the script runner.'**
  String get agentActionsHelpPowerShellModeMessage;

  /// No description provided for @agentActionsHelpPowerShellExecutableTitle.
  ///
  /// In en, this message translates to:
  /// **'PowerShell executable'**
  String get agentActionsHelpPowerShellExecutableTitle;

  /// No description provided for @agentActionsHelpPowerShellExecutableMessage.
  ///
  /// In en, this message translates to:
  /// **'Choose powershell.exe for Windows PowerShell or pwsh.exe for PowerShell 7. The executable must be available on PATH or in the process environment.'**
  String get agentActionsHelpPowerShellExecutableMessage;

  /// No description provided for @agentActionsHelpPowerShellCommandTitle.
  ///
  /// In en, this message translates to:
  /// **'PowerShell command'**
  String get agentActionsHelpPowerShellCommandTitle;

  /// No description provided for @agentActionsHelpPowerShellCommandMessage.
  ///
  /// In en, this message translates to:
  /// **'Content passed to PowerShell through -Command. The editor builds the persisted wrapper and preserves secret placeholders for the current scanner.'**
  String get agentActionsHelpPowerShellCommandMessage;

  /// No description provided for @agentActionsHelpPowerShellScriptTitle.
  ///
  /// In en, this message translates to:
  /// **'PowerShell script'**
  String get agentActionsHelpPowerShellScriptTitle;

  /// No description provided for @agentActionsHelpPowerShellScriptMessage.
  ///
  /// In en, this message translates to:
  /// **'Path to a local .ps1 file. In PowerShell 7 mode, pwsh.exe is automatically stored as the script interpreter.'**
  String get agentActionsHelpPowerShellScriptMessage;

  /// No description provided for @agentActionsHelpPathTitle.
  ///
  /// In en, this message translates to:
  /// **'Main path'**
  String get agentActionsHelpPathTitle;

  /// No description provided for @agentActionsHelpPathMessage.
  ///
  /// In en, this message translates to:
  /// **'Main local path used by the runner, such as an executable, script, or input file. Prefer absolute paths; later changes may block execution according to the path change policy.'**
  String get agentActionsHelpPathMessage;

  /// No description provided for @agentActionsHelpArgumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get agentActionsHelpArgumentsTitle;

  /// No description provided for @agentActionsHelpArgumentsMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter one argument per line. Each line becomes one argument list item, so do not combine multiple options on one line unless the target program expects that format.'**
  String get agentActionsHelpArgumentsMessage;

  /// No description provided for @agentActionsHelpWorkingDirectoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Working directory'**
  String get agentActionsHelpWorkingDirectoryTitle;

  /// No description provided for @agentActionsHelpWorkingDirectoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Initial process directory. Leave empty to use the runner default or enter an absolute path allowed by the path policy.'**
  String get agentActionsHelpWorkingDirectoryMessage;

  /// No description provided for @agentActionsHelpInterpreterTitle.
  ///
  /// In en, this message translates to:
  /// **'Interpreter'**
  String get agentActionsHelpInterpreterTitle;

  /// No description provided for @agentActionsHelpInterpreterMessage.
  ///
  /// In en, this message translates to:
  /// **'Executable used to open scripts. When empty, the runner chooses the default interpreter for the extension; fill it to force a specific version such as pwsh.exe or python.exe.'**
  String get agentActionsHelpInterpreterMessage;

  /// No description provided for @agentActionsHelpJarTitle.
  ///
  /// In en, this message translates to:
  /// **'JAR file'**
  String get agentActionsHelpJarTitle;

  /// No description provided for @agentActionsHelpJarMessage.
  ///
  /// In en, this message translates to:
  /// **'The .jar file that Java will execute. The path is stored in the definition and participates in the path change policy.'**
  String get agentActionsHelpJarMessage;

  /// No description provided for @agentActionsHelpEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email field'**
  String get agentActionsHelpEmailTitle;

  /// No description provided for @agentActionsHelpEmailMessage.
  ///
  /// In en, this message translates to:
  /// **'Configuration used by the email runner. Recipient and attachment fields accept one item per line; the SMTP profile must exist in local configuration.'**
  String get agentActionsHelpEmailMessage;

  /// No description provided for @agentActionsHelpComTitle.
  ///
  /// In en, this message translates to:
  /// **'COM object'**
  String get agentActionsHelpComTitle;

  /// No description provided for @agentActionsHelpComMessage.
  ///
  /// In en, this message translates to:
  /// **'Identifies the COM object ProgID, the method or property called, and the arguments sent. Use only COM automations installed and tested on the local Windows machine.'**
  String get agentActionsHelpComMessage;

  /// No description provided for @agentActionsHelpDeveloperTitle.
  ///
  /// In en, this message translates to:
  /// **'Developer Data7'**
  String get agentActionsHelpDeveloperTitle;

  /// No description provided for @agentActionsHelpDeveloperMessage.
  ///
  /// In en, this message translates to:
  /// **'Configures the Executor.exe, .7Proj project, Data7.Config, and connection used to run the Developer action.'**
  String get agentActionsHelpDeveloperMessage;

  /// No description provided for @agentActionsHelpMaxAttemptsTitle.
  ///
  /// In en, this message translates to:
  /// **'Maximum attempts'**
  String get agentActionsHelpMaxAttemptsTitle;

  /// No description provided for @agentActionsHelpMaxAttemptsMessage.
  ///
  /// In en, this message translates to:
  /// **'Maximum attempts for local runs and triggers. Remote runs stay at one attempt unless remote retry is enabled.'**
  String get agentActionsHelpMaxAttemptsMessage;

  /// No description provided for @agentActionsHelpTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Maximum runtime'**
  String get agentActionsHelpTimeoutTitle;

  /// No description provided for @agentActionsHelpTimeoutMessage.
  ///
  /// In en, this message translates to:
  /// **'Local execution timeout in minutes. When reached, execution fails as timed out and the policy below decides whether the main process should be killed.'**
  String get agentActionsHelpTimeoutMessage;

  /// No description provided for @agentActionsHelpKillOnTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Kill on timeout'**
  String get agentActionsHelpKillOnTimeoutTitle;

  /// No description provided for @agentActionsHelpKillOnTimeoutMessage.
  ///
  /// In en, this message translates to:
  /// **'When enabled, the runner tries to kill the main process if execution exceeds the configured maximum runtime.'**
  String get agentActionsHelpKillOnTimeoutMessage;

  /// No description provided for @agentActionsHelpRemoteRetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote retry'**
  String get agentActionsHelpRemoteRetryTitle;

  /// No description provided for @agentActionsHelpRemoteRetryMessage.
  ///
  /// In en, this message translates to:
  /// **'Allows Hub-started executions to use the retry policy. Enable only when repeating this action is safe.'**
  String get agentActionsHelpRemoteRetryMessage;

  /// No description provided for @agentActionsHelpRunElevatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Elevated execution'**
  String get agentActionsHelpRunElevatedTitle;

  /// No description provided for @agentActionsHelpRunElevatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Runs through the elevated helper when available. Requires local helper installation and scheduled task setup.'**
  String get agentActionsHelpRunElevatedMessage;

  /// No description provided for @agentActionsHelpContextInjectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Context injection'**
  String get agentActionsHelpContextInjectionTitle;

  /// No description provided for @agentActionsHelpContextInjectionMessage.
  ///
  /// In en, this message translates to:
  /// **'Defines how runtime parameters enter the execution: argument, file, environment variables, or stdin.'**
  String get agentActionsHelpContextInjectionMessage;

  /// No description provided for @agentActionsHelpPathChangePolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Path change policy'**
  String get agentActionsHelpPathChangePolicyTitle;

  /// No description provided for @agentActionsHelpPathChangePolicyMessage.
  ///
  /// In en, this message translates to:
  /// **'Controls what happens when paths or content snapshots change after validation: fail, warn, or allow.'**
  String get agentActionsHelpPathChangePolicyMessage;

  /// No description provided for @agentActionsHelpRuntimeSchemaTitle.
  ///
  /// In en, this message translates to:
  /// **'Runtime schema'**
  String get agentActionsHelpRuntimeSchemaTitle;

  /// No description provided for @agentActionsHelpRuntimeSchemaMessage.
  ///
  /// In en, this message translates to:
  /// **'JSON Schema object used to validate runtimeParameters before execution. Use it when the Hub or triggers send parameters; leave empty to accept any object.'**
  String get agentActionsHelpRuntimeSchemaMessage;

  /// No description provided for @agentActionsHelpAllowedProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Allowed profiles'**
  String get agentActionsHelpAllowedProfilesTitle;

  /// No description provided for @agentActionsHelpAllowedProfilesMessage.
  ///
  /// In en, this message translates to:
  /// **'Restricts the action to the listed operational profiles. Empty means any agent profile is allowed.'**
  String get agentActionsHelpAllowedProfilesMessage;

  /// No description provided for @agentActionsHelpAllowedEnvironmentVariablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Allowed variable names'**
  String get agentActionsHelpAllowedEnvironmentVariablesTitle;

  /// No description provided for @agentActionsHelpAllowedEnvironmentVariablesMessage.
  ///
  /// In en, this message translates to:
  /// **'Lists variable names that may be injected into the process. Use it to block unexpected names from runtime parameters or later edits.'**
  String get agentActionsHelpAllowedEnvironmentVariablesMessage;

  /// No description provided for @agentActionsHelpEnvironmentVariablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Environment variables'**
  String get agentActionsHelpEnvironmentVariablesTitle;

  /// No description provided for @agentActionsHelpEnvironmentVariablesMessage.
  ///
  /// In en, this message translates to:
  /// **'Variables added to the child process as NAME=value, one per line. Secret placeholders remain resolved at runtime.'**
  String get agentActionsHelpEnvironmentVariablesMessage;

  /// No description provided for @agentActionsHelpQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Concurrency and queue'**
  String get agentActionsHelpQueueTitle;

  /// No description provided for @agentActionsHelpQueueMessage.
  ///
  /// In en, this message translates to:
  /// **'Defines how many runs of this action may execute simultaneously, how many wait in queue, and whether new requests fail, wait, or replace a full queue.'**
  String get agentActionsHelpQueueMessage;

  /// No description provided for @agentActionsHelpPathAllowlistTitle.
  ///
  /// In en, this message translates to:
  /// **'Directory allowlist'**
  String get agentActionsHelpPathAllowlistTitle;

  /// No description provided for @agentActionsHelpPathAllowlistMessage.
  ///
  /// In en, this message translates to:
  /// **'Restricts allowed working directories and context files. Use absolute paths, one per line; empty adds no extra local allowlist. In production profile, command-line, executable, and script actions require working-directory allowlists (failure reason: production_path_allowlist_required).'**
  String get agentActionsHelpPathAllowlistMessage;

  /// No description provided for @agentActionsHelpProcessWindowTitle.
  ///
  /// In en, this message translates to:
  /// **'Process window'**
  String get agentActionsHelpProcessWindowTitle;

  /// No description provided for @agentActionsHelpProcessWindowMessage.
  ///
  /// In en, this message translates to:
  /// **'Controls the locally started process window: normal, hidden, or minimized, according to Windows support.'**
  String get agentActionsHelpProcessWindowMessage;

  /// No description provided for @agentActionsHelpCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Output capture'**
  String get agentActionsHelpCaptureTitle;

  /// No description provided for @agentActionsHelpCaptureMessage.
  ///
  /// In en, this message translates to:
  /// **'Controls whether stdout and stderr are stored in history. Redaction tries to mask secrets before persistence, but sensitive output should still be avoided.'**
  String get agentActionsHelpCaptureMessage;

  /// No description provided for @agentActionsHelpEncodingTitle.
  ///
  /// In en, this message translates to:
  /// **'Output encoding'**
  String get agentActionsHelpEncodingTitle;

  /// No description provided for @agentActionsHelpEncodingMessage.
  ///
  /// In en, this message translates to:
  /// **'Defines how captured stdout and stderr are decoded, using UTF-8 or the Windows system console.'**
  String get agentActionsHelpEncodingMessage;

  /// No description provided for @agentActionsHelpAcceptedExitCodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit codes'**
  String get agentActionsHelpAcceptedExitCodesTitle;

  /// No description provided for @agentActionsHelpAcceptedExitCodesMessage.
  ///
  /// In en, this message translates to:
  /// **'Codes that count as success. The default is 0; additional values must be comma-separated.'**
  String get agentActionsHelpAcceptedExitCodesMessage;

  /// No description provided for @agentActionsHelpOnAppExitTitle.
  ///
  /// In en, this message translates to:
  /// **'When agent closes'**
  String get agentActionsHelpOnAppExitTitle;

  /// No description provided for @agentActionsHelpOnAppExitMessage.
  ///
  /// In en, this message translates to:
  /// **'Defines what to do with still-running processes when Plug Agent closes: try to stop them, leave them running, or block according to runner support.'**
  String get agentActionsHelpOnAppExitMessage;

  /// No description provided for @agentActionsHelpRemoteExecutionTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote execution'**
  String get agentActionsHelpRemoteExecutionTitle;

  /// No description provided for @agentActionsHelpRemoteExecutionMessage.
  ///
  /// In en, this message translates to:
  /// **'Allows the Hub to execute this saved action over Socket.IO JSON-RPC. Requires local approval and should be enabled only for reviewed actions.'**
  String get agentActionsHelpRemoteExecutionMessage;

  /// No description provided for @agentActionsHelpRemoteAdHocTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote ad-hoc'**
  String get agentActionsHelpRemoteAdHocTitle;

  /// No description provided for @agentActionsHelpRemoteAdHocMessage.
  ///
  /// In en, this message translates to:
  /// **'Allows free-form commands sent by the Hub when the global feature is enabled. Keep it disabled except in controlled environments because it greatly increases risk exposure.'**
  String get agentActionsHelpRemoteAdHocMessage;

  /// No description provided for @agentActionsHelpNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get agentActionsHelpNotificationsTitle;

  /// No description provided for @agentActionsHelpNotificationsMessage.
  ///
  /// In en, this message translates to:
  /// **'Controls desktop notifications shown when local runs finish with success, failure, or timeout.'**
  String get agentActionsHelpNotificationsMessage;

  /// No description provided for @agentActionsFormNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Desktop notifications'**
  String get agentActionsFormNotificationsTitle;

  /// No description provided for @agentActionsFormNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Show a Windows notification when a local run reaches a terminal state.'**
  String get agentActionsFormNotificationsDescription;

  /// No description provided for @agentActionsFormNotifyOnSuccess.
  ///
  /// In en, this message translates to:
  /// **'Notify on success'**
  String get agentActionsFormNotifyOnSuccess;

  /// No description provided for @agentActionsFormNotifyOnFailure.
  ///
  /// In en, this message translates to:
  /// **'Notify on failure'**
  String get agentActionsFormNotifyOnFailure;

  /// No description provided for @agentActionsFormNotifyOnTimeout.
  ///
  /// In en, this message translates to:
  /// **'Notify on timeout'**
  String get agentActionsFormNotifyOnTimeout;

  /// No description provided for @agentActionNotificationSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Execution finished successfully.'**
  String get agentActionNotificationSuccessBody;

  /// No description provided for @agentActionNotificationTimeoutBody.
  ///
  /// In en, this message translates to:
  /// **'Execution exceeded the configured maximum runtime.'**
  String get agentActionNotificationTimeoutBody;

  /// No description provided for @agentActionNotificationFailureFallbackBody.
  ///
  /// In en, this message translates to:
  /// **'Execution finished with a failure.'**
  String get agentActionNotificationFailureFallbackBody;

  /// No description provided for @agentActionsFormExecutionPoliciesTitle.
  ///
  /// In en, this message translates to:
  /// **'Execution policies'**
  String get agentActionsFormExecutionPoliciesTitle;

  /// No description provided for @agentActionsFormExecutionPoliciesDescription.
  ///
  /// In en, this message translates to:
  /// **'Timeout and retry apply to local runs and scheduled triggers. Remote Hub runs stay at one attempt unless remote retry is enabled.'**
  String get agentActionsFormExecutionPoliciesDescription;

  /// No description provided for @agentActionsFormPathChangePolicy.
  ///
  /// In en, this message translates to:
  /// **'Path change policy'**
  String get agentActionsFormPathChangePolicy;

  /// No description provided for @agentActionsFormPathChangePolicyFail.
  ///
  /// In en, this message translates to:
  /// **'Fail if path or file content changed'**
  String get agentActionsFormPathChangePolicyFail;

  /// No description provided for @agentActionsFormPathChangePolicyWarn.
  ///
  /// In en, this message translates to:
  /// **'Warn if path or file content changed'**
  String get agentActionsFormPathChangePolicyWarn;

  /// No description provided for @agentActionsFormPathChangePolicyAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow path and content changes'**
  String get agentActionsFormPathChangePolicyAllow;

  /// No description provided for @agentActionsFormContextInjectionMode.
  ///
  /// In en, this message translates to:
  /// **'Context injection mode'**
  String get agentActionsFormContextInjectionMode;

  /// No description provided for @agentActionsFormContextInjectionArgument.
  ///
  /// In en, this message translates to:
  /// **'Argument (default)'**
  String get agentActionsFormContextInjectionArgument;

  /// No description provided for @agentActionsFormContextInjectionFile.
  ///
  /// In en, this message translates to:
  /// **'Context file (required at run)'**
  String get agentActionsFormContextInjectionFile;

  /// No description provided for @agentActionsFormContextInjectionEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Environment variables'**
  String get agentActionsFormContextInjectionEnvironment;

  /// No description provided for @agentActionsFormContextInjectionStdin.
  ///
  /// In en, this message translates to:
  /// **'Standard input'**
  String get agentActionsFormContextInjectionStdin;

  /// No description provided for @agentActionsFormRuntimeParameterSchema.
  ///
  /// In en, this message translates to:
  /// **'Runtime parameters JSON schema (optional)'**
  String get agentActionsFormRuntimeParameterSchema;

  /// No description provided for @agentActionsFormRuntimeParameterSchemaHint.
  ///
  /// In en, this message translates to:
  /// **'JSON Schema object validated against runtimeParameters on each run. Leave empty to skip.'**
  String get agentActionsFormRuntimeParameterSchemaHint;

  /// No description provided for @agentActionsTestPreviewPathSnapshotWarnings.
  ///
  /// In en, this message translates to:
  /// **'Path snapshot warnings'**
  String get agentActionsTestPreviewPathSnapshotWarnings;

  /// No description provided for @agentActionsFormMaxRuntimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'Maximum runtime (minutes)'**
  String get agentActionsFormMaxRuntimeMinutes;

  /// No description provided for @agentActionsFormKillOnTimeout.
  ///
  /// In en, this message translates to:
  /// **'Kill main process on timeout'**
  String get agentActionsFormKillOnTimeout;

  /// No description provided for @agentActionsFormMaxAttempts.
  ///
  /// In en, this message translates to:
  /// **'Maximum attempts'**
  String get agentActionsFormMaxAttempts;

  /// No description provided for @agentActionsFormAllowRemoteRetry.
  ///
  /// In en, this message translates to:
  /// **'Allow retry on remote Hub runs'**
  String get agentActionsFormAllowRemoteRetry;

  /// No description provided for @agentActionsFormRuntimePoliciesTitle.
  ///
  /// In en, this message translates to:
  /// **'Runtime constraints'**
  String get agentActionsFormRuntimePoliciesTitle;

  /// No description provided for @agentActionsFormRuntimePoliciesDescription.
  ///
  /// In en, this message translates to:
  /// **'Operational profile gate, child-process environment, accepted exit codes, and behavior when the Plug agent closes. Empty allowed profiles means any profile.'**
  String get agentActionsFormRuntimePoliciesDescription;

  /// No description provided for @agentActionsFormAllowedProfiles.
  ///
  /// In en, this message translates to:
  /// **'Allowed operational profiles'**
  String get agentActionsFormAllowedProfiles;

  /// No description provided for @agentActionsFormAllowedProfilesHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated (e.g. prod, homolog). Leave empty for any profile.'**
  String get agentActionsFormAllowedProfilesHint;

  /// No description provided for @agentActionsFormAllowedEnvironmentVariableNames.
  ///
  /// In en, this message translates to:
  /// **'Allowed environment variable names'**
  String get agentActionsFormAllowedEnvironmentVariableNames;

  /// No description provided for @agentActionsFormAllowedEnvironmentVariableNamesHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated (e.g. PLUG_API_URL, PLUG_TOKEN). Leave empty to allow any name used below or at runtime.'**
  String get agentActionsFormAllowedEnvironmentVariableNamesHint;

  /// No description provided for @agentActionsFormEnvironmentVariables.
  ///
  /// In en, this message translates to:
  /// **'Process environment variables'**
  String get agentActionsFormEnvironmentVariables;

  /// No description provided for @agentActionsFormEnvironmentVariablesHint.
  ///
  /// In en, this message translates to:
  /// **'One NAME=value per line. Reference action secrets with the placeholder convention documented in the secrets section. Applied when the action starts a process; environment injection mode adds runtime parameters from the run request.'**
  String get agentActionsFormEnvironmentVariablesHint;

  /// No description provided for @agentActionsFormEnvironmentVariablesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Environment variables must use one NAME=value per line with a valid variable name.'**
  String get agentActionsFormEnvironmentVariablesInvalid;

  /// No description provided for @agentActionsFormCurrentOperationalProfile.
  ///
  /// In en, this message translates to:
  /// **'Current agent profile: {profile}'**
  String agentActionsFormCurrentOperationalProfile(String profile);

  /// No description provided for @agentActionsFormCurrentOperationalProfileUnset.
  ///
  /// In en, this message translates to:
  /// **'Current agent profile is not set (AGENT_OPERATIONAL_PROFILE).'**
  String get agentActionsFormCurrentOperationalProfileUnset;

  /// No description provided for @agentActionsFormAcceptedExitCodes.
  ///
  /// In en, this message translates to:
  /// **'Accepted exit codes'**
  String get agentActionsFormAcceptedExitCodes;

  /// No description provided for @agentActionsFormAcceptedExitCodesHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated integers (default 0).'**
  String get agentActionsFormAcceptedExitCodesHint;

  /// No description provided for @agentActionsFormInvalidExitCodes.
  ///
  /// In en, this message translates to:
  /// **'Enter comma-separated integers for exit codes (e.g. 0, 1).'**
  String get agentActionsFormInvalidExitCodes;

  /// No description provided for @agentActionsFormProcessWindowMode.
  ///
  /// In en, this message translates to:
  /// **'Process window'**
  String get agentActionsFormProcessWindowMode;

  /// No description provided for @agentActionsFormProcessWindowModeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal console'**
  String get agentActionsFormProcessWindowModeNormal;

  /// No description provided for @agentActionsFormProcessWindowModeHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden (best effort)'**
  String get agentActionsFormProcessWindowModeHidden;

  /// No description provided for @agentActionsFormProcessWindowModeMinimized.
  ///
  /// In en, this message translates to:
  /// **'Minimized (normal start)'**
  String get agentActionsFormProcessWindowModeMinimized;

  /// No description provided for @agentActionsFormCapturePolicyDescription.
  ///
  /// In en, this message translates to:
  /// **'Control whether process output is stored and redacted before persistence.'**
  String get agentActionsFormCapturePolicyDescription;

  /// No description provided for @agentActionsFormCaptureStdout.
  ///
  /// In en, this message translates to:
  /// **'Capture stdout'**
  String get agentActionsFormCaptureStdout;

  /// No description provided for @agentActionsFormCaptureStderr.
  ///
  /// In en, this message translates to:
  /// **'Capture stderr'**
  String get agentActionsFormCaptureStderr;

  /// No description provided for @agentActionsFormRedactBeforePersisting.
  ///
  /// In en, this message translates to:
  /// **'Redact output before saving'**
  String get agentActionsFormRedactBeforePersisting;

  /// No description provided for @agentActionsFormQueuePolicyDescription.
  ///
  /// In en, this message translates to:
  /// **'Limits concurrent runs and queue behavior for this action definition.'**
  String get agentActionsFormQueuePolicyDescription;

  /// No description provided for @agentActionsFormMaxConcurrent.
  ///
  /// In en, this message translates to:
  /// **'Max concurrent runs'**
  String get agentActionsFormMaxConcurrent;

  /// No description provided for @agentActionsFormMaxQueued.
  ///
  /// In en, this message translates to:
  /// **'Max queued runs'**
  String get agentActionsFormMaxQueued;

  /// No description provided for @agentActionsFormInvalidQueueLimits.
  ///
  /// In en, this message translates to:
  /// **'Enter positive integers for max concurrent and max queued runs.'**
  String get agentActionsFormInvalidQueueLimits;

  /// No description provided for @agentActionsFormConcurrencyBehavior.
  ///
  /// In en, this message translates to:
  /// **'When limit is reached'**
  String get agentActionsFormConcurrencyBehavior;

  /// No description provided for @agentActionsFormConcurrencyAllowParallel.
  ///
  /// In en, this message translates to:
  /// **'Allow parallel (no limit)'**
  String get agentActionsFormConcurrencyAllowParallel;

  /// No description provided for @agentActionsFormConcurrencyEnqueue.
  ///
  /// In en, this message translates to:
  /// **'Enqueue and wait'**
  String get agentActionsFormConcurrencyEnqueue;

  /// No description provided for @agentActionsFormConcurrencyReject.
  ///
  /// In en, this message translates to:
  /// **'Reject new runs'**
  String get agentActionsFormConcurrencyReject;

  /// No description provided for @agentActionsFormConcurrencyIgnore.
  ///
  /// In en, this message translates to:
  /// **'Run anyway (ignore limit)'**
  String get agentActionsFormConcurrencyIgnore;

  /// No description provided for @agentActionsFormPathAllowlistDescription.
  ///
  /// In en, this message translates to:
  /// **'Optional directory allowlists. Leave empty to allow any path validated at runtime.'**
  String get agentActionsFormPathAllowlistDescription;

  /// No description provided for @agentActionsFormAllowedWorkingDirectories.
  ///
  /// In en, this message translates to:
  /// **'Allowed working directories'**
  String get agentActionsFormAllowedWorkingDirectories;

  /// No description provided for @agentActionsFormAllowedContextDirectories.
  ///
  /// In en, this message translates to:
  /// **'Allowed context directories'**
  String get agentActionsFormAllowedContextDirectories;

  /// No description provided for @agentActionsFormPathAllowlistHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated absolute paths (e.g. C:\\\\Data7\\\\bin).'**
  String get agentActionsFormPathAllowlistHint;

  /// No description provided for @agentActionsFormOutputEncodingDescription.
  ///
  /// In en, this message translates to:
  /// **'How captured stdout and stderr are decoded during execution.'**
  String get agentActionsFormOutputEncodingDescription;

  /// No description provided for @agentActionsFormStdoutEncoding.
  ///
  /// In en, this message translates to:
  /// **'Stdout encoding'**
  String get agentActionsFormStdoutEncoding;

  /// No description provided for @agentActionsFormStderrEncoding.
  ///
  /// In en, this message translates to:
  /// **'Stderr encoding'**
  String get agentActionsFormStderrEncoding;

  /// No description provided for @agentActionsFormOutputEncodingUtf8.
  ///
  /// In en, this message translates to:
  /// **'UTF-8'**
  String get agentActionsFormOutputEncodingUtf8;

  /// No description provided for @agentActionsFormOutputEncodingSystemConsole.
  ///
  /// In en, this message translates to:
  /// **'System console (Windows)'**
  String get agentActionsFormOutputEncodingSystemConsole;

  /// No description provided for @agentActionsFormOnAppExit.
  ///
  /// In en, this message translates to:
  /// **'When the agent closes'**
  String get agentActionsFormOnAppExit;

  /// No description provided for @agentActionsFormOnAppExitKill.
  ///
  /// In en, this message translates to:
  /// **'Kill main process'**
  String get agentActionsFormOnAppExitKill;

  /// No description provided for @agentActionsFormOnAppExitWaitThenKill.
  ///
  /// In en, this message translates to:
  /// **'Wait, then kill main process'**
  String get agentActionsFormOnAppExitWaitThenKill;

  /// No description provided for @agentActionsFormOnAppExitLeaveRunning.
  ///
  /// In en, this message translates to:
  /// **'Leave process running'**
  String get agentActionsFormOnAppExitLeaveRunning;

  /// No description provided for @agentActionsFormRemotePoliciesTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote execution'**
  String get agentActionsFormRemotePoliciesTitle;

  /// No description provided for @agentActionsFormRemotePoliciesDescription.
  ///
  /// In en, this message translates to:
  /// **'Allow the Hub to run this saved action over Socket.IO JSON-RPC. Requires explicit local approval.'**
  String get agentActionsFormRemotePoliciesDescription;

  /// No description provided for @agentActionsFormRemoteExecutionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Allow remote Hub execution'**
  String get agentActionsFormRemoteExecutionEnabled;

  /// No description provided for @agentActionsFormRemoteAdHocEnabled.
  ///
  /// In en, this message translates to:
  /// **'Allow remote ad-hoc commands'**
  String get agentActionsFormRemoteAdHocEnabled;

  /// No description provided for @agentActionsFormRemoteApprovedHint.
  ///
  /// In en, this message translates to:
  /// **'Remote execution is approved for this definition.'**
  String get agentActionsFormRemoteApprovedHint;

  /// No description provided for @agentActionsFormRemoteApprovalRequired.
  ///
  /// In en, this message translates to:
  /// **'Confirm remote execution before saving.'**
  String get agentActionsFormRemoteApprovalRequired;

  /// No description provided for @agentActionsFormRemoteReapprovalRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote re-approval required'**
  String get agentActionsFormRemoteReapprovalRequiredTitle;

  /// No description provided for @agentActionsFormRemoteReapprovalRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Risk-bearing fields changed since the last remote approval. Confirm remote execution again before saving.'**
  String get agentActionsFormRemoteReapprovalRequiredMessage;

  /// No description provided for @agentActionsConfirmRemoteReapprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Re-approve remote execution?'**
  String get agentActionsConfirmRemoteReapprovalTitle;

  /// No description provided for @agentActionsConfirmRemoteReapprovalMessage.
  ///
  /// In en, this message translates to:
  /// **'Command, paths, or runtime policies changed. The Hub cannot run this action remotely until you confirm again.'**
  String get agentActionsConfirmRemoteReapprovalMessage;

  /// No description provided for @agentActionsConfirmRemoteReapprovalConfirm.
  ///
  /// In en, this message translates to:
  /// **'Re-approve'**
  String get agentActionsConfirmRemoteReapprovalConfirm;

  /// No description provided for @agentActionsConfirmRemoteReapprovalCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsConfirmRemoteReapprovalCancel;

  /// No description provided for @agentActionsFormRemoteFeatureDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote agent actions are off'**
  String get agentActionsFormRemoteFeatureDisabledTitle;

  /// No description provided for @agentActionsFormRemoteFeatureDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Enable the remote agent actions feature flag before the Hub can call agent.action.* for this agent.'**
  String get agentActionsFormRemoteFeatureDisabledMessage;

  /// No description provided for @agentActionsFormRemoteAdHocFeatureDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote ad-hoc disabled'**
  String get agentActionsFormRemoteAdHocFeatureDisabledTitle;

  /// No description provided for @agentActionsFormRemoteAdHocFeatureDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Enable the remote ad-hoc feature flag to allow free-form hub commands on this agent.'**
  String get agentActionsFormRemoteAdHocFeatureDisabledMessage;

  /// No description provided for @agentActionsRiskRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get agentActionsRiskRemote;

  /// No description provided for @agentActionsRiskRemoteAdHoc.
  ///
  /// In en, this message translates to:
  /// **'Remote ad-hoc'**
  String get agentActionsRiskRemoteAdHoc;

  /// No description provided for @agentActionsRiskRemoteReapproval.
  ///
  /// In en, this message translates to:
  /// **'Re-approval required'**
  String get agentActionsRiskRemoteReapproval;

  /// No description provided for @agentActionsRiskAppCloseTrigger.
  ///
  /// In en, this message translates to:
  /// **'App close trigger'**
  String get agentActionsRiskAppCloseTrigger;

  /// No description provided for @agentActionsRiskSensitiveOutput.
  ///
  /// In en, this message translates to:
  /// **'Unredacted output'**
  String get agentActionsRiskSensitiveOutput;

  /// No description provided for @agentActionsRiskLeaveProcessRunning.
  ///
  /// In en, this message translates to:
  /// **'Leaves process running'**
  String get agentActionsRiskLeaveProcessRunning;

  /// No description provided for @agentActionsRiskUnsupportedType.
  ///
  /// In en, this message translates to:
  /// **'Unsupported editor'**
  String get agentActionsRiskUnsupportedType;

  /// No description provided for @agentActionsRiskNeedsValidation.
  ///
  /// In en, this message translates to:
  /// **'Needs validation'**
  String get agentActionsRiskNeedsValidation;

  /// No description provided for @agentActionsRiskSecretPlaceholders.
  ///
  /// In en, this message translates to:
  /// **'Uses secrets'**
  String get agentActionsRiskSecretPlaceholders;

  /// No description provided for @agentActionsNeedsValidationTitle.
  ///
  /// In en, this message translates to:
  /// **'Validation required'**
  String get agentActionsNeedsValidationTitle;

  /// No description provided for @agentActionsNeedsValidationMessage.
  ///
  /// In en, this message translates to:
  /// **'Test this action locally before running or enabling remote execution.'**
  String get agentActionsNeedsValidationMessage;

  /// No description provided for @agentActionsPreflightRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Preflight required for activation'**
  String get agentActionsPreflightRequiredTitle;

  /// No description provided for @agentActionsPreflightRequiredForActive.
  ///
  /// In en, this message translates to:
  /// **'Run \"Test action\" successfully before setting this action to Active.'**
  String get agentActionsPreflightRequiredForActive;

  /// No description provided for @agentActionsPreflightExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Preflight re-test required'**
  String get agentActionsPreflightExpiredTitle;

  /// No description provided for @agentActionsPreflightExpiredForActive.
  ///
  /// In en, this message translates to:
  /// **'The last successful preflight has expired. Run \"Test action\" again before setting this action to Active.'**
  String get agentActionsPreflightExpiredForActive;

  /// No description provided for @agentActionsPreflightValidTitle.
  ///
  /// In en, this message translates to:
  /// **'Preflight valid'**
  String get agentActionsPreflightValidTitle;

  /// No description provided for @agentActionsPreflightExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Preflight remains valid until {expiresAt}. Run \"Test action\" again before this time to keep activation enabled.'**
  String agentActionsPreflightExpiresAt(String expiresAt);

  /// No description provided for @agentActionsPreflightReadyForActivation.
  ///
  /// In en, this message translates to:
  /// **'Preflight passed. Set the state to Active and save to enable execution.'**
  String get agentActionsPreflightReadyForActivation;

  /// No description provided for @agentActionsPreflightSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Preflight validity'**
  String get agentActionsPreflightSettingsTitle;

  /// No description provided for @agentActionsPreflightSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'How long a successful \"Test action\" remains valid for activating an action. Saved values override the AGENT_ACTION_PREFLIGHT_VALIDITY_DAYS environment variable for this installation.'**
  String get agentActionsPreflightSettingsDescription;

  /// No description provided for @agentActionsPreflightSettingsValidityDays.
  ///
  /// In en, this message translates to:
  /// **'Validity window (days)'**
  String get agentActionsPreflightSettingsValidityDays;

  /// No description provided for @agentActionsPreflightSettingsEnvHint.
  ///
  /// In en, this message translates to:
  /// **'Allowed range: 1–365 days. After changing this value, existing preflight timestamps are still evaluated against the new window on the next save or UI refresh.'**
  String get agentActionsPreflightSettingsEnvHint;

  /// No description provided for @agentActionsPreflightSettingsSave.
  ///
  /// In en, this message translates to:
  /// **'Save preflight window'**
  String get agentActionsPreflightSettingsSave;

  /// No description provided for @agentActionsPreflightSettingsDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get agentActionsPreflightSettingsDiscard;

  /// No description provided for @agentActionsPreflightSettingsUseEnvDefaults.
  ///
  /// In en, this message translates to:
  /// **'Use environment defaults'**
  String get agentActionsPreflightSettingsUseEnvDefaults;

  /// No description provided for @agentActionsPreflightSettingsInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'Invalid value'**
  String get agentActionsPreflightSettingsInvalidTitle;

  /// No description provided for @agentActionsPreflightSettingsInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid whole number of days (1–365).'**
  String get agentActionsPreflightSettingsInvalidValue;

  /// No description provided for @agentActionsPreflightSettingsSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Preflight window saved'**
  String get agentActionsPreflightSettingsSavedTitle;

  /// No description provided for @agentActionsPreflightSettingsSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'The validity window was updated for this installation.'**
  String get agentActionsPreflightSettingsSavedMessage;

  /// No description provided for @agentActionsPreflightSettingsClearedTitle.
  ///
  /// In en, this message translates to:
  /// **'Preflight window restored'**
  String get agentActionsPreflightSettingsClearedTitle;

  /// No description provided for @agentActionsPreflightSettingsClearedMessage.
  ///
  /// In en, this message translates to:
  /// **'The custom window was removed. The agent now follows AGENT_ACTION_PREFLIGHT_VALIDITY_DAYS or the default.'**
  String get agentActionsPreflightSettingsClearedMessage;

  /// No description provided for @agentActionsDangerousCommandWarnModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Dangerous command warn mode (homologation)'**
  String get agentActionsDangerousCommandWarnModeTitle;

  /// No description provided for @agentActionsDangerousCommandWarnModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Warn mode is ON: risky command-line patterns show a confirmation dialog instead of blocking at validation. Do not use in production.'**
  String get agentActionsDangerousCommandWarnModeEnabled;

  /// No description provided for @agentActionsDangerousCommandWarnModeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Warn mode is OFF: risky command-line patterns are blocked unless the command is changed. Enable only in homologation via feature flag or environment.'**
  String get agentActionsDangerousCommandWarnModeDisabled;

  /// No description provided for @agentActionsProductionPathAllowlistRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Production path allowlist required'**
  String get agentActionsProductionPathAllowlistRequiredTitle;

  /// No description provided for @agentActionsProductionPathAllowlistRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'The operational profile is production. Command-line, executable, and script actions must define allowed working directories before save or run (production_path_allowlist_required).'**
  String get agentActionsProductionPathAllowlistRequiredMessage;

  /// No description provided for @agentActionsSecretPlaceholdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Secret placeholders referenced'**
  String get agentActionsSecretPlaceholdersTitle;

  /// No description provided for @agentActionsSecretPlaceholdersMessage.
  ///
  /// In en, this message translates to:
  /// **'This action references secrets: {secretNames}. Configure them in secure storage before running.'**
  String agentActionsSecretPlaceholdersMessage(String secretNames);

  /// No description provided for @agentActionsMissingSecretsTitle.
  ///
  /// In en, this message translates to:
  /// **'Missing secrets'**
  String get agentActionsMissingSecretsTitle;

  /// No description provided for @agentActionsMissingSecretsMessage.
  ///
  /// In en, this message translates to:
  /// **'These secrets are not available locally: {secretNames}.'**
  String agentActionsMissingSecretsMessage(String secretNames);

  /// No description provided for @agentActionsSecretsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Action secrets'**
  String get agentActionsSecretsSectionTitle;

  /// No description provided for @agentActionsSecretsSectionMessage.
  ///
  /// In en, this message translates to:
  /// **'Configure values for each secret placeholder referenced by this action. Values are stored only in secure local storage.'**
  String get agentActionsSecretsSectionMessage;

  /// No description provided for @agentActionsSecretStatusConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get agentActionsSecretStatusConfigured;

  /// No description provided for @agentActionsSecretStatusMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get agentActionsSecretStatusMissing;

  /// No description provided for @agentActionsSecretConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get agentActionsSecretConfigure;

  /// No description provided for @agentActionsSecretUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get agentActionsSecretUpdate;

  /// No description provided for @agentActionsSecretRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get agentActionsSecretRemove;

  /// No description provided for @agentActionsSecretConfigureTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure secret {secretName}'**
  String agentActionsSecretConfigureTitle(String secretName);

  /// No description provided for @agentActionsSecretConfigureMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter the secret value. It will not appear in action definitions, logs, or execution history.'**
  String get agentActionsSecretConfigureMessage;

  /// No description provided for @agentActionsSecretConfigureValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Secret value'**
  String get agentActionsSecretConfigureValueLabel;

  /// No description provided for @agentActionsSecretConfigureValueHint.
  ///
  /// In en, this message translates to:
  /// **'Enter value'**
  String get agentActionsSecretConfigureValueHint;

  /// No description provided for @agentActionsSecretConfigureSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get agentActionsSecretConfigureSave;

  /// No description provided for @agentActionsSecretConfigureCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsSecretConfigureCancel;

  /// No description provided for @agentActionsSecretConfigureErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not save secret'**
  String get agentActionsSecretConfigureErrorTitle;

  /// No description provided for @agentActionsSecretDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove secret?'**
  String get agentActionsSecretDeleteTitle;

  /// No description provided for @agentActionsSecretDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove the locally stored value for \"{secretName}\"? The action will fail until the secret is configured again.'**
  String agentActionsSecretDeleteMessage(String secretName);

  /// No description provided for @agentActionsSecretDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get agentActionsSecretDeleteConfirm;

  /// No description provided for @agentActionsSecretDeleteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsSecretDeleteCancel;

  /// No description provided for @agentActionsSecretOperationErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Secret operation failed'**
  String get agentActionsSecretOperationErrorTitle;

  /// No description provided for @agentActionsHistoryFilterSearch.
  ///
  /// In en, this message translates to:
  /// **'Search execution'**
  String get agentActionsHistoryFilterSearch;

  /// No description provided for @agentActionsRiskRunnerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Runner unavailable'**
  String get agentActionsRiskRunnerUnavailable;

  /// No description provided for @agentActionsRiskElevated.
  ///
  /// In en, this message translates to:
  /// **'Elevated execution'**
  String get agentActionsRiskElevated;

  /// No description provided for @agentActionsActionTypeUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Runner unavailable for this action type'**
  String get agentActionsActionTypeUnavailableTitle;

  /// No description provided for @agentActionsActionTypeUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'The agent subsystem is degraded and cannot run {actionType} actions until the runner or capability is restored.'**
  String agentActionsActionTypeUnavailableMessage(String actionType);

  /// No description provided for @agentActionsQueueActiveIndicator.
  ///
  /// In en, this message translates to:
  /// **'{pending} pending · {running} running in queue'**
  String agentActionsQueueActiveIndicator(int pending, int running);

  /// No description provided for @agentActionsConfirmRemoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable remote execution?'**
  String get agentActionsConfirmRemoteTitle;

  /// No description provided for @agentActionsConfirmRemoteMessage.
  ///
  /// In en, this message translates to:
  /// **'The Hub will be able to run this saved action when scopes, token policy and feature flags allow it.'**
  String get agentActionsConfirmRemoteMessage;

  /// No description provided for @agentActionsConfirmRemoteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Enable remote'**
  String get agentActionsConfirmRemoteConfirm;

  /// No description provided for @agentActionsConfirmRemoteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsConfirmRemoteCancel;

  /// No description provided for @agentActionsConfirmRemoteAdHocTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable remote ad-hoc commands?'**
  String get agentActionsConfirmRemoteAdHocTitle;

  /// No description provided for @agentActionsConfirmRemoteAdHocMessage.
  ///
  /// In en, this message translates to:
  /// **'Ad-hoc remote commands are high risk and should stay disabled unless you explicitly need them.'**
  String get agentActionsConfirmRemoteAdHocMessage;

  /// No description provided for @agentActionsConfirmRemoteAdHocConfirm.
  ///
  /// In en, this message translates to:
  /// **'Enable ad-hoc'**
  String get agentActionsConfirmRemoteAdHocConfirm;

  /// No description provided for @agentActionsConfirmRemoteAdHocCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsConfirmRemoteAdHocCancel;

  /// No description provided for @agentActionsConfirmAppCloseTriggerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add app-close trigger?'**
  String get agentActionsConfirmAppCloseTriggerTitle;

  /// No description provided for @agentActionsConfirmAppCloseTriggerMessage.
  ///
  /// In en, this message translates to:
  /// **'This trigger runs when the Plug agent closes and may start or stop processes while the app shuts down.'**
  String get agentActionsConfirmAppCloseTriggerMessage;

  /// No description provided for @agentActionsConfirmAppCloseTriggerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Use app close'**
  String get agentActionsConfirmAppCloseTriggerConfirm;

  /// No description provided for @agentActionsConfirmAppCloseTriggerCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsConfirmAppCloseTriggerCancel;

  /// No description provided for @agentActionsConfirmElevatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable elevated execution?'**
  String get agentActionsConfirmElevatedTitle;

  /// No description provided for @agentActionsConfirmElevatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Runs use the elevated helper and administrator privileges on this machine. Install and prepare the helper before enabling.'**
  String get agentActionsConfirmElevatedMessage;

  /// No description provided for @agentActionsConfirmElevatedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Enable elevated'**
  String get agentActionsConfirmElevatedConfirm;

  /// No description provided for @agentActionsConfirmElevatedCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsConfirmElevatedCancel;

  /// No description provided for @agentActionsConfirmDangerousCommandTitle.
  ///
  /// In en, this message translates to:
  /// **'Run high-risk command?'**
  String get agentActionsConfirmDangerousCommandTitle;

  /// No description provided for @agentActionsConfirmDangerousCommandMessage.
  ///
  /// In en, this message translates to:
  /// **'The command matches pattern \"{patternId}\" ({patternDescription}). Review carefully before running in production.'**
  String agentActionsConfirmDangerousCommandMessage(String patternId, String patternDescription);

  /// No description provided for @agentActionsConfirmDangerousCommandConfirm.
  ///
  /// In en, this message translates to:
  /// **'Run anyway'**
  String get agentActionsConfirmDangerousCommandConfirm;

  /// No description provided for @agentActionsConfirmDangerousCommandCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsConfirmDangerousCommandCancel;

  /// No description provided for @agentActionsDangerousCommandBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Command blocked'**
  String get agentActionsDangerousCommandBlockedTitle;

  /// No description provided for @agentActionsDangerousCommandBlockedMessage.
  ///
  /// In en, this message translates to:
  /// **'The command matches a high-risk pattern and was blocked for safety. Review the command or request operational approval.'**
  String get agentActionsDangerousCommandBlockedMessage;

  /// No description provided for @agentActionsDangerousCommandWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'High-risk command detected'**
  String get agentActionsDangerousCommandWarnTitle;

  /// No description provided for @agentActionsDangerousCommandWarnMessage.
  ///
  /// In en, this message translates to:
  /// **'The command matches pattern \"{patternId}\" ({patternDescription}). Manual run requires confirmation.'**
  String agentActionsDangerousCommandWarnMessage(String patternId, String patternDescription);

  /// No description provided for @agentActionsValidationTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the action fields'**
  String get agentActionsValidationTitle;

  /// No description provided for @agentActionsMaintenanceMode.
  ///
  /// In en, this message translates to:
  /// **'Maintenance mode'**
  String get agentActionsMaintenanceMode;

  /// No description provided for @agentActionsMaintenanceModeInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance mode is on'**
  String get agentActionsMaintenanceModeInfoTitle;

  /// No description provided for @agentActionsMaintenanceModeInfoMessage.
  ///
  /// In en, this message translates to:
  /// **'Scheduled runs, app start/close triggers, and remote runs are paused. You can still run actions from this screen and edit definitions.'**
  String get agentActionsMaintenanceModeInfoMessage;

  /// No description provided for @agentActionsMaintenanceStrictMode.
  ///
  /// In en, this message translates to:
  /// **'Block manual execution too'**
  String get agentActionsMaintenanceStrictMode;

  /// No description provided for @agentActionsElevatedRunnerNotReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Elevated runner not prepared'**
  String get agentActionsElevatedRunnerNotReadyTitle;

  /// No description provided for @agentActionsElevatedRunnerNotReadyMessage.
  ///
  /// In en, this message translates to:
  /// **'To use elevated execution, register the helper scheduled task with high privilege. Windows may prompt for UAC once.'**
  String get agentActionsElevatedRunnerNotReadyMessage;

  /// No description provided for @agentActionsElevatedRunnerDegradedTitle.
  ///
  /// In en, this message translates to:
  /// **'Elevated runner unavailable'**
  String get agentActionsElevatedRunnerDegradedTitle;

  /// No description provided for @agentActionsElevatedRunnerDegradedMessage.
  ///
  /// In en, this message translates to:
  /// **'The elevated helper failed recently. Prepare it again before running actions with high privilege.'**
  String get agentActionsElevatedRunnerDegradedMessage;

  /// No description provided for @agentActionsElevatedRunnerPrepare.
  ///
  /// In en, this message translates to:
  /// **'Prepare elevated runner'**
  String get agentActionsElevatedRunnerPrepare;

  /// No description provided for @agentActionsElevatedRunnerPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing elevated runner...'**
  String get agentActionsElevatedRunnerPreparing;

  /// No description provided for @agentActionsFormRunElevated.
  ///
  /// In en, this message translates to:
  /// **'Run with elevated privilege (Windows helper)'**
  String get agentActionsFormRunElevated;

  /// No description provided for @agentActionsFormRunElevatedHint.
  ///
  /// In en, this message translates to:
  /// **'Requires the helper executable and a prepared scheduled task on this agent.'**
  String get agentActionsFormRunElevatedHint;

  /// No description provided for @agentActionsSubsystemStatusStartingTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent actions are starting'**
  String get agentActionsSubsystemStatusStartingTitle;

  /// No description provided for @agentActionsSubsystemStatusStartingMessage.
  ///
  /// In en, this message translates to:
  /// **'The subsystem is still initializing. Local run and test stay disabled until it is ready.'**
  String get agentActionsSubsystemStatusStartingMessage;

  /// No description provided for @agentActionsSubsystemStatusDrainingTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent actions are shutting down'**
  String get agentActionsSubsystemStatusDrainingTitle;

  /// No description provided for @agentActionsSubsystemStatusDrainingMessage.
  ///
  /// In en, this message translates to:
  /// **'New runs are blocked while the Plug agent closes. App-close triggers may still run.'**
  String get agentActionsSubsystemStatusDrainingMessage;

  /// No description provided for @agentActionsSubsystemStatusDegradedTitle.
  ///
  /// In en, this message translates to:
  /// **'Some action types are unavailable'**
  String get agentActionsSubsystemStatusDegradedTitle;

  /// No description provided for @agentActionsSubsystemStatusDegradedMessage.
  ///
  /// In en, this message translates to:
  /// **'Unavailable types: {types}. Other actions may still run from this screen.'**
  String agentActionsSubsystemStatusDegradedMessage(String types);

  /// No description provided for @agentActionsSubsystemStatusDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent actions subsystem disabled'**
  String get agentActionsSubsystemStatusDisabledTitle;

  /// No description provided for @agentActionsSubsystemStatusDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'The runtime guard reports the subsystem as disabled. Check feature flags and restart the agent if needed.'**
  String get agentActionsSubsystemStatusDisabledMessage;

  /// No description provided for @agentActionsSchedulerOperationalIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled triggers are not running'**
  String get agentActionsSchedulerOperationalIssueTitle;

  /// No description provided for @agentActionsSchedulerInstanceLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Another Plug Agente process is already running the action scheduler for this data folder. Close the other instance or use a separate data directory. Manual runs and remote actions may still work in this window.'**
  String get agentActionsSchedulerInstanceLockedMessage;

  /// No description provided for @agentActionsSchedulerStorageAccessDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'The action scheduler could not access the lock file in this data folder. Review read/write permissions or run the agent with appropriate privileges.'**
  String get agentActionsSchedulerStorageAccessDeniedMessage;

  /// No description provided for @agentActionsSchedulerBootstrapFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The action scheduler stopped after a startup failure. Restart the agent or review saved triggers. Manual runs may still work until you fix the schedule configuration.'**
  String get agentActionsSchedulerBootstrapFailedMessage;

  /// No description provided for @agentActionsComObjectHandlersMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'COM actions are not ready'**
  String get agentActionsComObjectHandlersMissingTitle;

  /// No description provided for @agentActionsComObjectHandlersMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'No COM ProgID/member handlers are registered in this agent. COM actions will fail until handlers are added to ComObjectInvocationRegistry or homologation stub env vars are set (AGENT_ACTION_COM_STUB_ENABLED). See agent.getHealth com_object_invocation_ready.'**
  String get agentActionsComObjectHandlersMissingMessage;

  /// No description provided for @agentActionsDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Actions disabled'**
  String get agentActionsDisabledTitle;

  /// No description provided for @agentActionsDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Agent actions are disabled by feature flag.'**
  String get agentActionsDisabledMessage;

  /// No description provided for @agentActionsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Action operation failed'**
  String get agentActionsErrorTitle;

  /// No description provided for @agentActionsSummaryActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get agentActionsSummaryActions;

  /// No description provided for @agentActionsSummaryQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get agentActionsSummaryQueued;

  /// No description provided for @agentActionsSummaryRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get agentActionsSummaryRunning;

  /// No description provided for @agentActionsSummaryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get agentActionsSummaryFailed;

  /// No description provided for @agentActionsSummaryMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get agentActionsSummaryMaintenance;

  /// No description provided for @agentActionsSummaryMaintenanceActive.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get agentActionsSummaryMaintenanceActive;

  /// No description provided for @agentActionsSummaryComHandlers.
  ///
  /// In en, this message translates to:
  /// **'COM handlers'**
  String get agentActionsSummaryComHandlers;

  /// No description provided for @agentActionsSummaryComHandlersNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get agentActionsSummaryComHandlersNone;

  /// No description provided for @agentActionsRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Data retention'**
  String get agentActionsRetentionTitle;

  /// No description provided for @agentActionsRetentionDescription.
  ///
  /// In en, this message translates to:
  /// **'Periodic purge removes local rows older than the windows below. Saved values here take precedence over environment variables for this installation.'**
  String get agentActionsRetentionDescription;

  /// No description provided for @agentActionsRetentionExecutionHistory.
  ///
  /// In en, this message translates to:
  /// **'Terminal execution history'**
  String get agentActionsRetentionExecutionHistory;

  /// No description provided for @agentActionsRetentionExecutionHistoryValue.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one {1 day} other {{days} days}}'**
  String agentActionsRetentionExecutionHistoryValue(int days);

  /// No description provided for @agentActionsRetentionRemoteAudit.
  ///
  /// In en, this message translates to:
  /// **'Remote agent.action audit'**
  String get agentActionsRetentionRemoteAudit;

  /// No description provided for @agentActionsRetentionRemoteAuditValue.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one {1 day} other {{days} days}}'**
  String agentActionsRetentionRemoteAuditValue(int days);

  /// No description provided for @agentActionsRetentionCapturedOutput.
  ///
  /// In en, this message translates to:
  /// **'Captured stdout/stderr on terminal rows'**
  String get agentActionsRetentionCapturedOutput;

  /// No description provided for @agentActionsRetentionCapturedOutputValue.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, one {1 hour} other {{hours} hours}}'**
  String agentActionsRetentionCapturedOutputValue(int hours);

  /// No description provided for @agentActionsRetentionEnvVariables.
  ///
  /// In en, this message translates to:
  /// **'Environment variables (fallback): AGENT_ACTION_EXECUTION_RETENTION_DAYS, AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS, AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS'**
  String get agentActionsRetentionEnvVariables;

  /// No description provided for @agentActionsRetentionSave.
  ///
  /// In en, this message translates to:
  /// **'Save retention'**
  String get agentActionsRetentionSave;

  /// No description provided for @agentActionsRetentionReset.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get agentActionsRetentionReset;

  /// No description provided for @agentActionsRetentionUseEnvDefaults.
  ///
  /// In en, this message translates to:
  /// **'Use environment defaults'**
  String get agentActionsRetentionUseEnvDefaults;

  /// No description provided for @agentActionsRetentionClearedTitle.
  ///
  /// In en, this message translates to:
  /// **'Retention restored'**
  String get agentActionsRetentionClearedTitle;

  /// No description provided for @agentActionsRetentionClearedMessage.
  ///
  /// In en, this message translates to:
  /// **'Custom values were removed. Cleanup windows now follow environment variables or agent defaults.'**
  String get agentActionsRetentionClearedMessage;

  /// No description provided for @agentActionsRetentionSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Retention saved'**
  String get agentActionsRetentionSavedTitle;

  /// No description provided for @agentActionsRetentionSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'Cleanup windows were updated for this installation.'**
  String get agentActionsRetentionSavedMessage;

  /// No description provided for @agentActionsRetentionInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'Enter valid whole numbers in every field.'**
  String get agentActionsRetentionInvalidValue;

  /// No description provided for @agentActionsRetentionPersistedHint.
  ///
  /// In en, this message translates to:
  /// **'Custom values are stored locally and override the environment fallback.'**
  String get agentActionsRetentionPersistedHint;

  /// No description provided for @agentActionsEmptyActions.
  ///
  /// In en, this message translates to:
  /// **'No actions registered.'**
  String get agentActionsEmptyActions;

  /// No description provided for @agentActionsListFilterType.
  ///
  /// In en, this message translates to:
  /// **'Action type'**
  String get agentActionsListFilterType;

  /// No description provided for @agentActionsListFilterSearch.
  ///
  /// In en, this message translates to:
  /// **'Search actions'**
  String get agentActionsListFilterSearch;

  /// No description provided for @agentActionsListFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No actions match the current filters.'**
  String get agentActionsListFilterEmpty;

  /// No description provided for @agentActionsEmptySelection.
  ///
  /// In en, this message translates to:
  /// **'Select an action to inspect execution details.'**
  String get agentActionsEmptySelection;

  /// No description provided for @agentActionsHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Execution history'**
  String get agentActionsHistoryTitle;

  /// No description provided for @agentActionsHistoryFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get agentActionsHistoryFilterStatus;

  /// No description provided for @agentActionsHistoryFilterSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get agentActionsHistoryFilterSource;

  /// No description provided for @agentActionsHistoryFilterPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get agentActionsHistoryFilterPeriod;

  /// No description provided for @agentActionsHistoryFilterFailurePhase.
  ///
  /// In en, this message translates to:
  /// **'Failure phase'**
  String get agentActionsHistoryFilterFailurePhase;

  /// No description provided for @agentActionsHistoryFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get agentActionsHistoryFilterAll;

  /// No description provided for @agentActionsHistoryPeriodAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get agentActionsHistoryPeriodAll;

  /// No description provided for @agentActionsHistoryPeriodLast24Hours.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get agentActionsHistoryPeriodLast24Hours;

  /// No description provided for @agentActionsHistoryPeriodLast3Days.
  ///
  /// In en, this message translates to:
  /// **'Last 3 days'**
  String get agentActionsHistoryPeriodLast3Days;

  /// No description provided for @agentActionsRemoteAuditTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote agent.action audit'**
  String get agentActionsRemoteAuditTitle;

  /// No description provided for @agentActionsRemoteAuditDescription.
  ///
  /// In en, this message translates to:
  /// **'Recent Hub JSON-RPC and execution lifecycle rows for agent.action.* (append-only; retention and purge still apply).'**
  String get agentActionsRemoteAuditDescription;

  /// No description provided for @agentActionsRemoteAuditFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get agentActionsRemoteAuditFilterAll;

  /// No description provided for @agentActionsRemoteAuditFilterRpc.
  ///
  /// In en, this message translates to:
  /// **'RPC'**
  String get agentActionsRemoteAuditFilterRpc;

  /// No description provided for @agentActionsRemoteAuditFilterLifecycle.
  ///
  /// In en, this message translates to:
  /// **'Lifecycle'**
  String get agentActionsRemoteAuditFilterLifecycle;

  /// No description provided for @agentActionsRemoteAuditFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rows match this filter.'**
  String get agentActionsRemoteAuditFilterEmpty;

  /// No description provided for @agentActionsRemoteAuditOutcomeReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get agentActionsRemoteAuditOutcomeReceived;

  /// No description provided for @agentActionsRemoteAuditOutcomeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get agentActionsRemoteAuditOutcomeSuccess;

  /// No description provided for @agentActionsRemoteAuditOutcomeRpcError.
  ///
  /// In en, this message translates to:
  /// **'RPC error'**
  String get agentActionsRemoteAuditOutcomeRpcError;

  /// No description provided for @agentActionsRemoteAuditOutcomeAuthorizationDenied.
  ///
  /// In en, this message translates to:
  /// **'Authorization denied'**
  String get agentActionsRemoteAuditOutcomeAuthorizationDenied;

  /// No description provided for @agentActionsRemoteAuditOutcomeNotificationRejected.
  ///
  /// In en, this message translates to:
  /// **'Notification rejected'**
  String get agentActionsRemoteAuditOutcomeNotificationRejected;

  /// No description provided for @agentActionsRemoteAuditOutcomeRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Rate limited'**
  String get agentActionsRemoteAuditOutcomeRateLimited;

  /// No description provided for @agentActionsRemoteAuditOutcomeLifecycleEnqueued.
  ///
  /// In en, this message translates to:
  /// **'Enqueued'**
  String get agentActionsRemoteAuditOutcomeLifecycleEnqueued;

  /// No description provided for @agentActionsRemoteAuditOutcomeLifecycleStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get agentActionsRemoteAuditOutcomeLifecycleStarted;

  /// No description provided for @agentActionsRemoteAuditOutcomeLifecycleCancelRequested.
  ///
  /// In en, this message translates to:
  /// **'Cancel requested'**
  String get agentActionsRemoteAuditOutcomeLifecycleCancelRequested;

  /// No description provided for @agentActionsRemoteAuditOutcomeLifecycleFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get agentActionsRemoteAuditOutcomeLifecycleFinished;

  /// No description provided for @agentActionsRemoteAuditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No remote audit rows recorded yet.'**
  String get agentActionsRemoteAuditEmpty;

  /// No description provided for @agentActionsRemoteAuditRefresh.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get agentActionsRemoteAuditRefresh;

  /// No description provided for @agentActionsRemoteAuditCopyJson.
  ///
  /// In en, this message translates to:
  /// **'Copy as JSON'**
  String get agentActionsRemoteAuditCopyJson;

  /// No description provided for @agentActionsRemoteAuditCopiedToast.
  ///
  /// In en, this message translates to:
  /// **'Audit copied to the clipboard.'**
  String get agentActionsRemoteAuditCopiedToast;

  /// No description provided for @agentActionsRemoteAuditShowInHistory.
  ///
  /// In en, this message translates to:
  /// **'Show in history'**
  String get agentActionsRemoteAuditShowInHistory;

  /// No description provided for @agentActionsRemoteAuditExecutionNotInHistory.
  ///
  /// In en, this message translates to:
  /// **'Execution {executionId} is not in the loaded history. It may be outside the retention window or list limit.'**
  String agentActionsRemoteAuditExecutionNotInHistory(Object executionId);

  /// No description provided for @agentActionsRemoteAuditRuntimeInstanceMismatch.
  ///
  /// In en, this message translates to:
  /// **'Execution {executionId} belongs to another agent installation (audit instance {auditInstanceId}). Local history only highlights when the runtime instance matches.'**
  String agentActionsRemoteAuditRuntimeInstanceMismatch(Object executionId, Object auditInstanceId);

  /// No description provided for @agentActionsRemoteAuditFieldAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get agentActionsRemoteAuditFieldAction;

  /// No description provided for @agentActionsRemoteAuditFieldExecution.
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get agentActionsRemoteAuditFieldExecution;

  /// No description provided for @agentActionsRemoteAuditFieldTrace.
  ///
  /// In en, this message translates to:
  /// **'Trace'**
  String get agentActionsRemoteAuditFieldTrace;

  /// No description provided for @agentActionsRemoteAuditFieldRequestedBy.
  ///
  /// In en, this message translates to:
  /// **'Requester'**
  String get agentActionsRemoteAuditFieldRequestedBy;

  /// No description provided for @agentActionsRemoteAuditFieldIdempotencyKey.
  ///
  /// In en, this message translates to:
  /// **'Idempotency'**
  String get agentActionsRemoteAuditFieldIdempotencyKey;

  /// No description provided for @agentActionsRemoteAuditFieldReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get agentActionsRemoteAuditFieldReason;

  /// No description provided for @agentActionsRemoteAuditFieldClient.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get agentActionsRemoteAuditFieldClient;

  /// No description provided for @agentActionsRemoteAuditFieldRuntimeInstance.
  ///
  /// In en, this message translates to:
  /// **'Instance'**
  String get agentActionsRemoteAuditFieldRuntimeInstance;

  /// No description provided for @agentActionsRemoteAuditFieldRuntimeSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get agentActionsRemoteAuditFieldRuntimeSession;

  /// No description provided for @agentActionsRemoteAuditReasonMissingClientToken.
  ///
  /// In en, this message translates to:
  /// **'Client token missing'**
  String get agentActionsRemoteAuditReasonMissingClientToken;

  /// No description provided for @agentActionsRemoteAuditReasonPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get agentActionsRemoteAuditReasonPermissionDenied;

  /// No description provided for @agentActionsRemoteAuditReasonRemoteRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Remote rate limit'**
  String get agentActionsRemoteAuditReasonRemoteRateLimited;

  /// No description provided for @agentActionsRemoteAuditReasonRemoteDisabled.
  ///
  /// In en, this message translates to:
  /// **'Remote actions disabled'**
  String get agentActionsRemoteAuditReasonRemoteDisabled;

  /// No description provided for @agentActionsRemoteAuditReasonFeatureDisabled.
  ///
  /// In en, this message translates to:
  /// **'Agent actions disabled'**
  String get agentActionsRemoteAuditReasonFeatureDisabled;

  /// No description provided for @agentActionsRemoteAuditReasonMaintenanceMode.
  ///
  /// In en, this message translates to:
  /// **'Maintenance mode'**
  String get agentActionsRemoteAuditReasonMaintenanceMode;

  /// No description provided for @agentActionsRemoteAuditReasonNotificationNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Notification not allowed'**
  String get agentActionsRemoteAuditReasonNotificationNotAllowed;

  /// No description provided for @agentActionsRemoteAuditReasonRemoteContextNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Remote context not supported'**
  String get agentActionsRemoteAuditReasonRemoteContextNotSupported;

  /// No description provided for @agentActionsRemoteAuditReasonIdempotencyRequired.
  ///
  /// In en, this message translates to:
  /// **'Idempotency key required'**
  String get agentActionsRemoteAuditReasonIdempotencyRequired;

  /// No description provided for @agentActionsRemoteAuditReasonIdempotencyMismatch.
  ///
  /// In en, this message translates to:
  /// **'Idempotency fingerprint mismatch'**
  String get agentActionsRemoteAuditReasonIdempotencyMismatch;

  /// No description provided for @agentActionsRemoteAuditReasonBatchNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Method not allowed in batch'**
  String get agentActionsRemoteAuditReasonBatchNotAllowed;

  /// No description provided for @agentActionsRemoteAuditReasonExecutionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Execution not found'**
  String get agentActionsRemoteAuditReasonExecutionNotFound;

  /// No description provided for @agentActionsRemoteAuditReasonAlreadyFinished.
  ///
  /// In en, this message translates to:
  /// **'Already finished'**
  String get agentActionsRemoteAuditReasonAlreadyFinished;

  /// No description provided for @agentActionsRemoteAuditReasonKillFailed.
  ///
  /// In en, this message translates to:
  /// **'Kill failed'**
  String get agentActionsRemoteAuditReasonKillFailed;

  /// No description provided for @agentActionsEmptyHistory.
  ///
  /// In en, this message translates to:
  /// **'No executions recorded for this action.'**
  String get agentActionsEmptyHistory;

  /// No description provided for @agentActionsTriggersTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedules and triggers'**
  String get agentActionsTriggersTitle;

  /// No description provided for @agentActionsTriggersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No triggers saved for this action.'**
  String get agentActionsTriggersEmpty;

  /// No description provided for @agentActionsTriggersLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading triggers…'**
  String get agentActionsTriggersLoading;

  /// No description provided for @agentActionsTriggerEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get agentActionsTriggerEnabled;

  /// No description provided for @agentActionsTriggerDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get agentActionsTriggerDisabled;

  /// No description provided for @agentActionsTriggerUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed trigger'**
  String get agentActionsTriggerUnnamed;

  /// No description provided for @agentActionsTriggerNotScheduled.
  ///
  /// In en, this message translates to:
  /// **'Not scheduled'**
  String get agentActionsTriggerNotScheduled;

  /// No description provided for @agentActionsTriggerNextRun.
  ///
  /// In en, this message translates to:
  /// **'Next run: {when}'**
  String agentActionsTriggerNextRun(Object when);

  /// No description provided for @agentActionsTriggerSummaryTimeZone.
  ///
  /// In en, this message translates to:
  /// **'Time zone: {ianaId}'**
  String agentActionsTriggerSummaryTimeZone(Object ianaId);

  /// No description provided for @agentActionsTriggerSummaryCatchUpEnabled.
  ///
  /// In en, this message translates to:
  /// **'Catch-up for missed runs enabled'**
  String get agentActionsTriggerSummaryCatchUpEnabled;

  /// No description provided for @agentActionsTriggerTypeManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get agentActionsTriggerTypeManual;

  /// No description provided for @agentActionsTriggerTypeRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get agentActionsTriggerTypeRemote;

  /// No description provided for @agentActionsTriggerTypeOnce.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get agentActionsTriggerTypeOnce;

  /// No description provided for @agentActionsTriggerTypeInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get agentActionsTriggerTypeInterval;

  /// No description provided for @agentActionsTriggerTypeDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get agentActionsTriggerTypeDaily;

  /// No description provided for @agentActionsTriggerTypeWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get agentActionsTriggerTypeWeekly;

  /// No description provided for @agentActionsTriggerTypeMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get agentActionsTriggerTypeMonthly;

  /// No description provided for @agentActionsTriggerTypeAppStart.
  ///
  /// In en, this message translates to:
  /// **'App start'**
  String get agentActionsTriggerTypeAppStart;

  /// No description provided for @agentActionsTriggerTypeAppClose.
  ///
  /// In en, this message translates to:
  /// **'App close'**
  String get agentActionsTriggerTypeAppClose;

  /// No description provided for @agentActionsTriggerDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete trigger'**
  String get agentActionsTriggerDelete;

  /// No description provided for @agentActionsTriggerDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete trigger'**
  String get agentActionsTriggerDeleteConfirmTitle;

  /// No description provided for @agentActionsTriggerDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{triggerLabel}\"? Scheduled runs stop for this trigger.'**
  String agentActionsTriggerDeleteConfirmMessage(Object triggerLabel);

  /// No description provided for @agentActionsTriggerDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get agentActionsTriggerDeleteConfirm;

  /// No description provided for @agentActionsTriggerDeleteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsTriggerDeleteCancel;

  /// No description provided for @agentActionsTriggerAdd.
  ///
  /// In en, this message translates to:
  /// **'Add trigger'**
  String get agentActionsTriggerAdd;

  /// No description provided for @agentActionsTriggerEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit trigger'**
  String get agentActionsTriggerEdit;

  /// No description provided for @agentActionsTriggerSave.
  ///
  /// In en, this message translates to:
  /// **'Save trigger'**
  String get agentActionsTriggerSave;

  /// No description provided for @agentActionsTriggerCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentActionsTriggerCancel;

  /// No description provided for @agentActionsTriggerEditorTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New trigger'**
  String get agentActionsTriggerEditorTitleNew;

  /// No description provided for @agentActionsTriggerEditorTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit trigger'**
  String get agentActionsTriggerEditorTitleEdit;

  /// No description provided for @agentActionsTriggerFieldName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get agentActionsTriggerFieldName;

  /// No description provided for @agentActionsTriggerFieldType.
  ///
  /// In en, this message translates to:
  /// **'Trigger type'**
  String get agentActionsTriggerFieldType;

  /// No description provided for @agentActionsTriggerFieldTimezone.
  ///
  /// In en, this message translates to:
  /// **'IANA time zone (optional)'**
  String get agentActionsTriggerFieldTimezone;

  /// No description provided for @agentActionsTriggerFieldTimezoneFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter IANA zones'**
  String get agentActionsTriggerFieldTimezoneFilter;

  /// No description provided for @agentActionsTriggerHintTimezoneFilter.
  ///
  /// In en, this message translates to:
  /// **'e.g. America, Europe, UTC'**
  String get agentActionsTriggerHintTimezoneFilter;

  /// No description provided for @agentActionsTriggerHintTimezonePick.
  ///
  /// In en, this message translates to:
  /// **'Tap a row to fill the field above. Leave empty to use the device default.'**
  String get agentActionsTriggerHintTimezonePick;

  /// No description provided for @agentActionsTriggerHintTimezoneSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'Type in the filter to search IANA time zones.'**
  String get agentActionsTriggerHintTimezoneSearchEmpty;

  /// No description provided for @agentActionsTriggerTimezoneNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No time zone matches the filter.'**
  String get agentActionsTriggerTimezoneNoMatches;

  /// No description provided for @agentActionsTriggerTimezoneMatchesTruncated.
  ///
  /// In en, this message translates to:
  /// **'Showing the first {count} matches. Refine the filter.'**
  String agentActionsTriggerTimezoneMatchesTruncated(int count);

  /// No description provided for @agentActionsTriggerFieldStartAt.
  ///
  /// In en, this message translates to:
  /// **'Start date and time'**
  String get agentActionsTriggerFieldStartAt;

  /// No description provided for @agentActionsTriggerFieldStartAtOptional.
  ///
  /// In en, this message translates to:
  /// **'Active from (optional)'**
  String get agentActionsTriggerFieldStartAtOptional;

  /// No description provided for @agentActionsTriggerFieldEndAtOptional.
  ///
  /// In en, this message translates to:
  /// **'Active until (optional)'**
  String get agentActionsTriggerFieldEndAtOptional;

  /// No description provided for @agentActionsTriggerFieldIntervalMinutes.
  ///
  /// In en, this message translates to:
  /// **'Interval (minutes)'**
  String get agentActionsTriggerFieldIntervalMinutes;

  /// No description provided for @agentActionsTriggerFieldTimeOfDay.
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get agentActionsTriggerFieldTimeOfDay;

  /// No description provided for @agentActionsTriggerHintTimeOfDay.
  ///
  /// In en, this message translates to:
  /// **'HH:mm (24-hour)'**
  String get agentActionsTriggerHintTimeOfDay;

  /// No description provided for @agentActionsTriggerFieldWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get agentActionsTriggerFieldWeekdays;

  /// No description provided for @agentActionsTriggerFieldDayOfMonth.
  ///
  /// In en, this message translates to:
  /// **'Day of month (1-31)'**
  String get agentActionsTriggerFieldDayOfMonth;

  /// No description provided for @agentActionsTriggerHintDateTime.
  ///
  /// In en, this message translates to:
  /// **'Format: yyyy-MM-dd HH:mm (local)'**
  String get agentActionsTriggerHintDateTime;

  /// No description provided for @agentActionsTriggerFieldIgnoreMissedRuns.
  ///
  /// In en, this message translates to:
  /// **'Ignore missed runs during downtime'**
  String get agentActionsTriggerFieldIgnoreMissedRuns;

  /// No description provided for @agentActionsTriggerHintIgnoreMissedRuns.
  ///
  /// In en, this message translates to:
  /// **'Turn off to run schedules that were missed while the app was closed, when the trigger type supports catch-up.'**
  String get agentActionsTriggerHintIgnoreMissedRuns;

  /// No description provided for @agentActionsTriggerValidationTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the trigger fields'**
  String get agentActionsTriggerValidationTitle;

  /// No description provided for @agentActionsTriggerValidationInvalidStartAt.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid start date and time.'**
  String get agentActionsTriggerValidationInvalidStartAt;

  /// No description provided for @agentActionsTriggerValidationInvalidIntervalMinutes.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive whole number of minutes.'**
  String get agentActionsTriggerValidationInvalidIntervalMinutes;

  /// No description provided for @agentActionsTriggerValidationInvalidTimeOfDay.
  ///
  /// In en, this message translates to:
  /// **'Enter the time as HH:mm using a 24-hour clock.'**
  String get agentActionsTriggerValidationInvalidTimeOfDay;

  /// No description provided for @agentActionsTriggerValidationWeekdaysRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one weekday.'**
  String get agentActionsTriggerValidationWeekdaysRequired;

  /// No description provided for @agentActionsTriggerValidationInvalidDayOfMonth.
  ///
  /// In en, this message translates to:
  /// **'Enter a day of month between 1 and 31.'**
  String get agentActionsTriggerValidationInvalidDayOfMonth;

  /// No description provided for @agentActionsTriggerWeekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get agentActionsTriggerWeekdayMon;

  /// No description provided for @agentActionsTriggerWeekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get agentActionsTriggerWeekdayTue;

  /// No description provided for @agentActionsTriggerWeekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get agentActionsTriggerWeekdayWed;

  /// No description provided for @agentActionsTriggerWeekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get agentActionsTriggerWeekdayThu;

  /// No description provided for @agentActionsTriggerWeekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get agentActionsTriggerWeekdayFri;

  /// No description provided for @agentActionsTriggerWeekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get agentActionsTriggerWeekdaySat;

  /// No description provided for @agentActionsTriggerWeekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get agentActionsTriggerWeekdaySun;

  /// No description provided for @agentActionsRequestedAt.
  ///
  /// In en, this message translates to:
  /// **'Requested at'**
  String get agentActionsRequestedAt;

  /// No description provided for @agentActionsExitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit code'**
  String get agentActionsExitCode;

  /// No description provided for @agentActionsSourceLocalUi.
  ///
  /// In en, this message translates to:
  /// **'Local UI'**
  String get agentActionsSourceLocalUi;

  /// No description provided for @agentActionsSourceScheduler.
  ///
  /// In en, this message translates to:
  /// **'Scheduler'**
  String get agentActionsSourceScheduler;

  /// No description provided for @agentActionsSourceRemoteHub.
  ///
  /// In en, this message translates to:
  /// **'Hub'**
  String get agentActionsSourceRemoteHub;

  /// No description provided for @agentActionsSourceAppLifecycle.
  ///
  /// In en, this message translates to:
  /// **'App lifecycle'**
  String get agentActionsSourceAppLifecycle;

  /// No description provided for @agentActionsDiagnosticsCopySupport.
  ///
  /// In en, this message translates to:
  /// **'Copy support JSON'**
  String get agentActionsDiagnosticsCopySupport;

  /// No description provided for @agentActionsDiagnosticsCopiedToast.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied to the clipboard.'**
  String get agentActionsDiagnosticsCopiedToast;

  /// No description provided for @agentActionsDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get agentActionsDiagnosticsTitle;

  /// No description provided for @agentActionsDiagnosticsExecutionId.
  ///
  /// In en, this message translates to:
  /// **'Execution'**
  String get agentActionsDiagnosticsExecutionId;

  /// No description provided for @agentActionsDiagnosticsSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get agentActionsDiagnosticsSource;

  /// No description provided for @agentActionsDiagnosticsPid.
  ///
  /// In en, this message translates to:
  /// **'PID'**
  String get agentActionsDiagnosticsPid;

  /// No description provided for @agentActionsDiagnosticsStartedAt.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get agentActionsDiagnosticsStartedAt;

  /// No description provided for @agentActionsDiagnosticsFinishedAt.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get agentActionsDiagnosticsFinishedAt;

  /// No description provided for @agentActionsDiagnosticsTimeoutAt.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get agentActionsDiagnosticsTimeoutAt;

  /// No description provided for @agentActionsDiagnosticsDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get agentActionsDiagnosticsDuration;

  /// No description provided for @agentActionsDiagnosticsExecutable.
  ///
  /// In en, this message translates to:
  /// **'Executable'**
  String get agentActionsDiagnosticsExecutable;

  /// No description provided for @agentActionsDiagnosticsArgumentCount.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get agentActionsDiagnosticsArgumentCount;

  /// No description provided for @agentActionsDiagnosticsCommandPreview.
  ///
  /// In en, this message translates to:
  /// **'Command preview'**
  String get agentActionsDiagnosticsCommandPreview;

  /// No description provided for @agentActionsDiagnosticsFailureCode.
  ///
  /// In en, this message translates to:
  /// **'Failure code'**
  String get agentActionsDiagnosticsFailureCode;

  /// No description provided for @agentActionsDiagnosticsFailurePhase.
  ///
  /// In en, this message translates to:
  /// **'Failure phase'**
  String get agentActionsDiagnosticsFailurePhase;

  /// No description provided for @agentActionsFailurePhaseExecutionPreflight.
  ///
  /// In en, this message translates to:
  /// **'Execution preflight'**
  String get agentActionsFailurePhaseExecutionPreflight;

  /// No description provided for @agentActionsFailurePhaseDefinitionValidation.
  ///
  /// In en, this message translates to:
  /// **'Definition validation'**
  String get agentActionsFailurePhaseDefinitionValidation;

  /// No description provided for @agentActionsFailurePhaseStartProcess.
  ///
  /// In en, this message translates to:
  /// **'Process start'**
  String get agentActionsFailurePhaseStartProcess;

  /// No description provided for @agentActionsFailurePhaseStdinSetup.
  ///
  /// In en, this message translates to:
  /// **'Stdin setup'**
  String get agentActionsFailurePhaseStdinSetup;

  /// No description provided for @agentActionsFailurePhaseProcessRuntime.
  ///
  /// In en, this message translates to:
  /// **'Process runtime'**
  String get agentActionsFailurePhaseProcessRuntime;

  /// No description provided for @agentActionsFailurePhaseProcessExit.
  ///
  /// In en, this message translates to:
  /// **'Process exit'**
  String get agentActionsFailurePhaseProcessExit;

  /// No description provided for @agentActionsFailurePhaseQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get agentActionsFailurePhaseQueue;

  /// No description provided for @agentActionsFailurePhaseTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get agentActionsFailurePhaseTimeout;

  /// No description provided for @agentActionsFailurePhaseAuthorization.
  ///
  /// In en, this message translates to:
  /// **'Authorization'**
  String get agentActionsFailurePhaseAuthorization;

  /// No description provided for @agentActionsFailurePhaseValidation.
  ///
  /// In en, this message translates to:
  /// **'Validation'**
  String get agentActionsFailurePhaseValidation;

  /// No description provided for @agentActionsFailurePhaseLookup.
  ///
  /// In en, this message translates to:
  /// **'Lookup'**
  String get agentActionsFailurePhaseLookup;

  /// No description provided for @agentActionsFailurePhaseCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancellation'**
  String get agentActionsFailurePhaseCancel;

  /// No description provided for @agentActionsFailurePhasePlatformCheck.
  ///
  /// In en, this message translates to:
  /// **'Platform check'**
  String get agentActionsFailurePhasePlatformCheck;

  /// No description provided for @agentActionsFailurePhaseSmtpSend.
  ///
  /// In en, this message translates to:
  /// **'SMTP send'**
  String get agentActionsFailurePhaseSmtpSend;

  /// No description provided for @agentActionsFailurePhaseExecutionSend.
  ///
  /// In en, this message translates to:
  /// **'Send preparation'**
  String get agentActionsFailurePhaseExecutionSend;

  /// No description provided for @agentActionsFailurePhaseElevatedSubmit.
  ///
  /// In en, this message translates to:
  /// **'Elevated submit'**
  String get agentActionsFailurePhaseElevatedSubmit;

  /// No description provided for @agentActionsFailurePhaseBootstrapReconciliation.
  ///
  /// In en, this message translates to:
  /// **'Bootstrap reconciliation'**
  String get agentActionsFailurePhaseBootstrapReconciliation;

  /// No description provided for @agentActionsExecutionFailurePhaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Failed during: {phase}'**
  String agentActionsExecutionFailurePhaseLabel(String phase);

  /// No description provided for @agentActionsDiagnosticsCorrectiveAction.
  ///
  /// In en, this message translates to:
  /// **'Corrective action'**
  String get agentActionsDiagnosticsCorrectiveAction;

  /// No description provided for @agentActionsDiagnosticsCorrectivePath.
  ///
  /// In en, this message translates to:
  /// **'Review the saved path, validate the file or directory again, and update the action before running it.'**
  String get agentActionsDiagnosticsCorrectivePath;

  /// No description provided for @agentActionsDiagnosticsCorrectiveRunner.
  ///
  /// In en, this message translates to:
  /// **'Check the configured executable, interpreter, or runner path and validate the action again.'**
  String get agentActionsDiagnosticsCorrectiveRunner;

  /// No description provided for @agentActionsDiagnosticsCorrectiveExitCode.
  ///
  /// In en, this message translates to:
  /// **'Review the exit code and the redacted output. Adjust accepted exit codes or fix the executed command.'**
  String get agentActionsDiagnosticsCorrectiveExitCode;

  /// No description provided for @agentActionsDiagnosticsCorrectiveQueue.
  ///
  /// In en, this message translates to:
  /// **'Wait for the queue to drain or adjust the action concurrency and queue limits.'**
  String get agentActionsDiagnosticsCorrectiveQueue;

  /// No description provided for @agentActionsDiagnosticsCorrectiveTimeout.
  ///
  /// In en, this message translates to:
  /// **'Review the configured timeout and investigate why the process did not finish within the expected window.'**
  String get agentActionsDiagnosticsCorrectiveTimeout;

  /// No description provided for @agentActionsDiagnosticsCorrectiveKill.
  ///
  /// In en, this message translates to:
  /// **'Verify whether the main process is still running and try canceling again after reviewing PID and permissions.'**
  String get agentActionsDiagnosticsCorrectiveKill;

  /// No description provided for @agentActionsDiagnosticsCorrectiveDefinitionValidation.
  ///
  /// In en, this message translates to:
  /// **'Review required fields and validate the action definition again before running it.'**
  String get agentActionsDiagnosticsCorrectiveDefinitionValidation;

  /// No description provided for @agentActionsDiagnosticsCorrectivePreflight.
  ///
  /// In en, this message translates to:
  /// **'Revalidate paths, permissions, context, and local prerequisites before starting the execution.'**
  String get agentActionsDiagnosticsCorrectivePreflight;

  /// No description provided for @agentActionsDiagnosticsCorrectiveStartProcess.
  ///
  /// In en, this message translates to:
  /// **'Check executable, arguments, and working directory before trying to start the process again.'**
  String get agentActionsDiagnosticsCorrectiveStartProcess;

  /// No description provided for @agentActionsDiagnosticsCorrectiveRuntime.
  ///
  /// In en, this message translates to:
  /// **'Inspect the redacted output and operational details to identify the failure that happened during execution.'**
  String get agentActionsDiagnosticsCorrectiveRuntime;

  /// No description provided for @agentActionsDiagnosticsStdout.
  ///
  /// In en, this message translates to:
  /// **'stdout'**
  String get agentActionsDiagnosticsStdout;

  /// No description provided for @agentActionsDiagnosticsStderr.
  ///
  /// In en, this message translates to:
  /// **'stderr'**
  String get agentActionsDiagnosticsStderr;

  /// No description provided for @agentActionsDiagnosticsTruncated.
  ///
  /// In en, this message translates to:
  /// **'truncated'**
  String get agentActionsDiagnosticsTruncated;

  /// No description provided for @agentActionsDiagnosticsStoredInChunks.
  ///
  /// In en, this message translates to:
  /// **'stored in segments'**
  String get agentActionsDiagnosticsStoredInChunks;

  /// No description provided for @agentActionsExecutionOutputInChunks.
  ///
  /// In en, this message translates to:
  /// **'large output in segments'**
  String get agentActionsExecutionOutputInChunks;

  /// No description provided for @agentActionsDiagnosticsOutputLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load captured output'**
  String get agentActionsDiagnosticsOutputLoadFailed;

  /// No description provided for @agentActionsDiagnosticsLoadMoreStdout.
  ///
  /// In en, this message translates to:
  /// **'Load more stdout'**
  String get agentActionsDiagnosticsLoadMoreStdout;

  /// No description provided for @agentActionsDiagnosticsLoadMoreStderr.
  ///
  /// In en, this message translates to:
  /// **'Load more stderr'**
  String get agentActionsDiagnosticsLoadMoreStderr;

  /// No description provided for @agentActionsDiagnosticsDefinitionSnapshotHash.
  ///
  /// In en, this message translates to:
  /// **'Definition snapshot hash'**
  String get agentActionsDiagnosticsDefinitionSnapshotHash;

  /// No description provided for @agentActionsDiagnosticsContextHash.
  ///
  /// In en, this message translates to:
  /// **'Context hash'**
  String get agentActionsDiagnosticsContextHash;

  /// No description provided for @agentActionsDiagnosticsRedactionApplied.
  ///
  /// In en, this message translates to:
  /// **'Redaction applied'**
  String get agentActionsDiagnosticsRedactionApplied;

  /// No description provided for @agentActionsDiagnosticsValueYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get agentActionsDiagnosticsValueYes;

  /// No description provided for @agentActionsDiagnosticsValueNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get agentActionsDiagnosticsValueNo;

  /// No description provided for @agentActionsDiagnosticsQueueStartedAt.
  ///
  /// In en, this message translates to:
  /// **'Queue started'**
  String get agentActionsDiagnosticsQueueStartedAt;

  /// No description provided for @agentActionsDiagnosticsIdempotencyKey.
  ///
  /// In en, this message translates to:
  /// **'Idempotency key'**
  String get agentActionsDiagnosticsIdempotencyKey;

  /// No description provided for @agentActionsDiagnosticsRequestedBy.
  ///
  /// In en, this message translates to:
  /// **'Requested by'**
  String get agentActionsDiagnosticsRequestedBy;

  /// No description provided for @agentActionsDiagnosticsTraceId.
  ///
  /// In en, this message translates to:
  /// **'Trace id'**
  String get agentActionsDiagnosticsTraceId;

  /// No description provided for @agentActionsDiagnosticsRuntimeInstanceId.
  ///
  /// In en, this message translates to:
  /// **'Runtime instance id'**
  String get agentActionsDiagnosticsRuntimeInstanceId;

  /// No description provided for @agentActionsDiagnosticsRuntimeSessionId.
  ///
  /// In en, this message translates to:
  /// **'Runtime session id'**
  String get agentActionsDiagnosticsRuntimeSessionId;

  /// No description provided for @agentActionsDiagnosticsTriggerId.
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get agentActionsDiagnosticsTriggerId;

  /// No description provided for @agentActionsDiagnosticsTriggerType.
  ///
  /// In en, this message translates to:
  /// **'Trigger type'**
  String get agentActionsDiagnosticsTriggerType;

  /// No description provided for @agentActionsDiagnosticsScheduledAt.
  ///
  /// In en, this message translates to:
  /// **'Scheduled for'**
  String get agentActionsDiagnosticsScheduledAt;

  /// No description provided for @agentActionsDiagnosticsTriggeredAt.
  ///
  /// In en, this message translates to:
  /// **'Triggered at'**
  String get agentActionsDiagnosticsTriggeredAt;

  /// No description provided for @agentActionsTypeCommandLine.
  ///
  /// In en, this message translates to:
  /// **'Command line'**
  String get agentActionsTypeCommandLine;

  /// No description provided for @agentActionsTypePowerShell.
  ///
  /// In en, this message translates to:
  /// **'PowerShell'**
  String get agentActionsTypePowerShell;

  /// No description provided for @agentActionsTypeExecutable.
  ///
  /// In en, this message translates to:
  /// **'Executable'**
  String get agentActionsTypeExecutable;

  /// No description provided for @agentActionsTypeScript.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get agentActionsTypeScript;

  /// No description provided for @agentActionsTypeJar.
  ///
  /// In en, this message translates to:
  /// **'JAR'**
  String get agentActionsTypeJar;

  /// No description provided for @agentActionsTypeEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get agentActionsTypeEmail;

  /// No description provided for @agentActionsTypeComObject.
  ///
  /// In en, this message translates to:
  /// **'COM object'**
  String get agentActionsTypeComObject;

  /// No description provided for @agentActionsTypeDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get agentActionsTypeDeveloper;

  /// No description provided for @agentActionsStateActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get agentActionsStateActive;

  /// No description provided for @agentActionsStatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get agentActionsStatePaused;

  /// No description provided for @agentActionsStateDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get agentActionsStateDisabled;

  /// No description provided for @agentActionsStateNeedsValidation.
  ///
  /// In en, this message translates to:
  /// **'Needs validation'**
  String get agentActionsStateNeedsValidation;

  /// No description provided for @agentActionsStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get agentActionsStatusQueued;

  /// No description provided for @agentActionsStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get agentActionsStatusRunning;

  /// No description provided for @agentActionsStatusSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get agentActionsStatusSucceeded;

  /// No description provided for @agentActionsStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get agentActionsStatusFailed;

  /// No description provided for @agentActionsStatusSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get agentActionsStatusSkipped;

  /// No description provided for @agentActionsStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get agentActionsStatusCancelled;

  /// No description provided for @agentActionsStatusKilled.
  ///
  /// In en, this message translates to:
  /// **'Killed'**
  String get agentActionsStatusKilled;

  /// No description provided for @agentActionsStatusTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get agentActionsStatusTimedOut;

  /// No description provided for @agentActionsStatusInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get agentActionsStatusInterrupted;

  /// No description provided for @agentActionsStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get agentActionsStatusUnknown;

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

  /// No description provided for @settingsPersistError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the setting. Please try again.'**
  String get settingsPersistError;

  /// No description provided for @errorUnexpected.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get errorUnexpected;

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

  /// No description provided for @btnClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get btnClose;

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

  /// No description provided for @agentProfileHubVersionConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile changed on the server'**
  String get agentProfileHubVersionConflictTitle;

  /// No description provided for @agentProfileHubVersionConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'The profile was saved on this computer, but the server has a newer version.\n\nDetail: {errorDetail}'**
  String agentProfileHubVersionConflictMessage(String errorDetail);

  /// No description provided for @agentProfileHubVersionConflictDetail.
  ///
  /// In en, this message translates to:
  /// **'{errorDetail}'**
  String agentProfileHubVersionConflictDetail(String errorDetail);

  /// No description provided for @agentProfileActionReloadFromServer.
  ///
  /// In en, this message translates to:
  /// **'Reload from server'**
  String get agentProfileActionReloadFromServer;

  /// No description provided for @agentProfileActionRetrySync.
  ///
  /// In en, this message translates to:
  /// **'Retry sync'**
  String get agentProfileActionRetrySync;

  /// No description provided for @agentProfileHubCatalogPersistFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Synced with warning'**
  String get agentProfileHubCatalogPersistFailedTitle;

  /// No description provided for @agentProfileHubCatalogPersistFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'The profile was sent to the server, but the local version could not be saved for the next update.\n\nDetail: {errorDetail}'**
  String agentProfileHubCatalogPersistFailedMessage(String errorDetail);

  /// No description provided for @agentProfileReloadFromHubSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile reloaded from the server.'**
  String get agentProfileReloadFromHubSuccess;

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

  /// No description provided for @wsLogAuthMissingPermission.
  ///
  /// In en, this message translates to:
  /// **'missing permission'**
  String get wsLogAuthMissingPermission;

  /// No description provided for @wsLogAuthTokenNotFound.
  ///
  /// In en, this message translates to:
  /// **'token not found'**
  String get wsLogAuthTokenNotFound;

  /// No description provided for @wsLogAuthTokenRevoked.
  ///
  /// In en, this message translates to:
  /// **'token revoked'**
  String get wsLogAuthTokenRevoked;

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

  /// No description provided for @configTabPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get configTabPreferences;

  /// No description provided for @configTabUpdatesAbout.
  ///
  /// In en, this message translates to:
  /// **'Updates & about'**
  String get configTabUpdatesAbout;

  /// No description provided for @configTabBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get configTabBackup;

  /// No description provided for @configTabWebSocket.
  ///
  /// In en, this message translates to:
  /// **'WebSocket'**
  String get configTabWebSocket;

  /// Settings tab: local backup section title.
  ///
  /// In en, this message translates to:
  /// **'Local backup'**
  String get configBackupSectionTitle;

  /// Explains what the ZIP contains and secure-storage limits.
  ///
  /// In en, this message translates to:
  /// **'Export or restore the local agent database (configuration) and the global settings file. The archive may contain hub credentials stored in the database. Secrets stored only in Windows secure storage are not included—you may need to sign in again after a restore.'**
  String get configBackupIntro;

  /// Warns about duplicate agent IDs when restoring on multiple machines.
  ///
  /// In en, this message translates to:
  /// **'Restoring the same backup on two machines can register the same agent twice. The app checks the hub when possible; if that check fails, you must confirm that you accept the risk.'**
  String get configBackupDuplicateNote;

  /// Warns about two instances sharing one data directory (see AppStrings.singleInstanceMessage for the native single-instance dialog in PT).
  ///
  /// In en, this message translates to:
  /// **'Do not run two copies of the app against the same global data folder.'**
  String get configBackupSingleInstanceNote;

  /// Footnote on the backup tab; fileName is the diagnostics file basename.
  ///
  /// In en, this message translates to:
  /// **'If restore fails after the app closes, details are saved as {fileName} in the app data folder.'**
  String configBackupRestoreDiagnosticsHint(String fileName);

  /// No description provided for @configBackupRestoreFailedNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'The last restore failed'**
  String get configBackupRestoreFailedNoticeTitle;

  /// No description provided for @configBackupRestoreFailedNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'The technical details below were saved when the app closed during the last restore attempt.'**
  String get configBackupRestoreFailedNoticeBody;

  /// No description provided for @configBackupRestoreFailedDetailsHeader.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get configBackupRestoreFailedDetailsHeader;

  /// No description provided for @configBackupRestoreFailedNoticeDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get configBackupRestoreFailedNoticeDismiss;

  /// Primary action to save a backup ZIP.
  ///
  /// In en, this message translates to:
  /// **'Export backup…'**
  String get configBackupButtonExport;

  /// Primary action to pick a backup ZIP to restore.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup…'**
  String get configBackupButtonRestore;

  /// Accessibility/loading label during export.
  ///
  /// In en, this message translates to:
  /// **'Exporting backup…'**
  String get configBackupExporting;

  /// Accessibility/loading label while staging restore.
  ///
  /// In en, this message translates to:
  /// **'Preparing restore…'**
  String get configBackupRestoring;

  /// Dialog title after successful export.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get configBackupExportSuccessTitle;

  /// Dialog body after successful export.
  ///
  /// In en, this message translates to:
  /// **'The backup file was created successfully.'**
  String get configBackupExportSuccessMessage;

  /// Destructive restore confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get configBackupRestoreDialogTitle;

  /// Explains that restore replaces DB/settings and uses .bak.
  ///
  /// In en, this message translates to:
  /// **'This replaces the local database and settings. The application will close—start it again afterward. Current files are copied to .bak before replacement.'**
  String get configBackupRestoreDialogBody;

  /// Shown when hub lists this agent as connected.
  ///
  /// In en, this message translates to:
  /// **'This agent ID appears connected on the hub. Restoring may duplicate an active session unless the other machine is offline.'**
  String get configBackupRestoreDuplicateWarning;

  /// Shown when hub could not be queried.
  ///
  /// In en, this message translates to:
  /// **'Could not verify whether this agent is already connected (network or expired session). Confirm that no other machine is using this same backup.'**
  String get configBackupRestoreVerifyWarning;

  /// Shown when backup installationId differs from current.
  ///
  /// In en, this message translates to:
  /// **'This backup was created on another installation (different installation ID).'**
  String get configBackupRestoreInstallationMismatch;

  /// Risk acknowledgement when duplicate session likely.
  ///
  /// In en, this message translates to:
  /// **'I confirm the other session is offline or I accept the risk of a duplicate agent.'**
  String get configBackupCheckboxAcknowledgeDuplicate;

  /// Risk acknowledgement when hub check failed.
  ///
  /// In en, this message translates to:
  /// **'I understand the hub could not be verified and I accept the risk.'**
  String get configBackupCheckboxAcknowledgeUncertain;

  /// Confirm restore and exit the app.
  ///
  /// In en, this message translates to:
  /// **'Restore and exit'**
  String get configBackupRestoreConfirm;

  /// Cancel backup/restore flow.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get configBackupCancel;

  /// Validation error: ZIP incomplete.
  ///
  /// In en, this message translates to:
  /// **'The archive is missing manifest or database files.'**
  String get configBackupErrMissingManifestOrDb;

  /// Validation error: manifest JSON invalid.
  ///
  /// In en, this message translates to:
  /// **'The backup manifest is invalid.'**
  String get configBackupErrInvalidManifest;

  /// Validation error: unsupported manifest formatVersion.
  ///
  /// In en, this message translates to:
  /// **'This backup format is not supported.'**
  String get configBackupErrUnsupportedFormat;

  /// Could not read PRAGMA user_version from staged DB.
  ///
  /// In en, this message translates to:
  /// **'Could not read the schema version from the backup database.'**
  String get configBackupErrDbVersion;

  /// Backup schema is newer than this app.
  ///
  /// In en, this message translates to:
  /// **'This backup was created with a newer app version. Update the app before restoring.'**
  String get configBackupErrNewerBackup;

  /// ZIP path unsafe or bad entry.
  ///
  /// In en, this message translates to:
  /// **'The archive contains an invalid file entry.'**
  String get configBackupErrInvalidEntry;

  /// Local agent_config.db missing during export.
  ///
  /// In en, this message translates to:
  /// **'Local database file was not found.'**
  String get configBackupErrExportDbNotFound;

  /// ZIP encoder failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to build the backup archive.'**
  String get configBackupErrExportZip;

  /// Could not write destination ZIP path.
  ///
  /// In en, this message translates to:
  /// **'Could not write the backup file.'**
  String get configBackupErrExportWrite;

  /// Unexpected export failure.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error while exporting backup.'**
  String get configBackupErrExportGeneric;

  /// Could not decode selected ZIP.
  ///
  /// In en, this message translates to:
  /// **'Could not read the backup file.'**
  String get configBackupErrReadZip;

  /// Unexpected staging failure.
  ///
  /// In en, this message translates to:
  /// **'Failed to read the backup archive.'**
  String get configBackupErrStageGeneric;

  /// Staged DB path missing at apply time.
  ///
  /// In en, this message translates to:
  /// **'Staged database file is missing.'**
  String get configBackupErrApplyMissingDb;

  /// File copy failed during apply.
  ///
  /// In en, this message translates to:
  /// **'Could not apply backup files.'**
  String get configBackupErrApplyWrite;

  /// Error dialog title for restore failures before exit.
  ///
  /// In en, this message translates to:
  /// **'Restore failed'**
  String get configBackupRestoreFailedTitle;

  /// Error dialog title for export failures.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get configBackupExportFailedTitle;

  /// Tells user the app will exit after restore.
  ///
  /// In en, this message translates to:
  /// **'The application will close. Start it again to use the restored data.'**
  String get configBackupRestoreRestartNotice;

  /// Info when backup user_version is below current app schema.
  ///
  /// In en, this message translates to:
  /// **'This backup uses an older database schema. The app will migrate it on the next start.'**
  String get configBackupRestoreOlderSchemaNote;

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

  /// No description provided for @configCheckUpdatesNow.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get configCheckUpdatesNow;

  /// No description provided for @configLastUpdatePrefix.
  ///
  /// In en, this message translates to:
  /// **'Last check: '**
  String get configLastUpdatePrefix;

  /// No description provided for @configLastBackgroundUpdatePrefix.
  ///
  /// In en, this message translates to:
  /// **'Last background check: '**
  String get configLastBackgroundUpdatePrefix;

  /// No description provided for @configLastAutomaticUpdatePrefix.
  ///
  /// In en, this message translates to:
  /// **'Last automatic check: '**
  String get configLastAutomaticUpdatePrefix;

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

  /// No description provided for @configUpdateNotificationsToggle.
  ///
  /// In en, this message translates to:
  /// **'Notify about updates'**
  String get configUpdateNotificationsToggle;

  /// No description provided for @configUpdateNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Shows in-app notices and checks for updates in the background when automatic installation is off. With automatic installation off and this option on, the app may still check for updates without installing. Manual check remains available.'**
  String get configUpdateNotificationsDescription;

  /// No description provided for @configUpdateNotificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Update notifications enabled.'**
  String get configUpdateNotificationsEnabled;

  /// No description provided for @configUpdateNotificationsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Update notifications disabled.'**
  String get configUpdateNotificationsDisabled;

  /// No description provided for @configManualCheckSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual check'**
  String get configManualCheckSectionTitle;

  /// No description provided for @configUseManualOnlyUpdatesLink.
  ///
  /// In en, this message translates to:
  /// **'Use manual check only'**
  String get configUseManualOnlyUpdatesLink;

  /// No description provided for @configManualOnlyUpdatesApplied.
  ///
  /// In en, this message translates to:
  /// **'Manual check mode enabled.'**
  String get configManualOnlyUpdatesApplied;

  /// No description provided for @configUpdatePendingReadyNotice.
  ///
  /// In en, this message translates to:
  /// **'An update is ready to install. Re-enable notifications or use Check for updates to see details.'**
  String get configUpdatePendingReadyNotice;

  /// No description provided for @configUpdatePendingAwaitingConsentNotice.
  ///
  /// In en, this message translates to:
  /// **'An update is available and needs your confirmation. Re-enable notifications or use Check for updates.'**
  String get configUpdatePendingAwaitingConsentNotice;

  /// No description provided for @configAutomaticSilentUpdatesDisableNotificationsHint.
  ///
  /// In en, this message translates to:
  /// **'Automatic installation was turned off. To avoid background update checks, also disable update notifications.'**
  String get configAutomaticSilentUpdatesDisableNotificationsHint;

  /// No description provided for @configUpdateTechnicalPreferencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Update preferences'**
  String get configUpdateTechnicalPreferencesTitle;

  /// No description provided for @configUpdateTechnicalNotificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Update notifications'**
  String get configUpdateTechnicalNotificationsEnabled;

  /// No description provided for @configUpdateTechnicalAutomaticSilentEnabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic silent installation'**
  String get configUpdateTechnicalAutomaticSilentEnabled;

  /// No description provided for @configAutomaticSilentUpdatesToggle.
  ///
  /// In en, this message translates to:
  /// **'Install updates automatically'**
  String get configAutomaticSilentUpdatesToggle;

  /// No description provided for @configAutomaticSilentUpdatesDescription.
  ///
  /// In en, this message translates to:
  /// **'Downloads, validates, and starts the installer silently. Windows may still request UAC.'**
  String get configAutomaticSilentUpdatesDescription;

  /// No description provided for @configAutomaticSilentUpdatesEnabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic update installation enabled.'**
  String get configAutomaticSilentUpdatesEnabled;

  /// No description provided for @configAutomaticSilentUpdatesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic update installation disabled.'**
  String get configAutomaticSilentUpdatesDisabled;

  /// No description provided for @configAutomaticSilentUpdatesCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Try automatic update now'**
  String get configAutomaticSilentUpdatesCheckNow;

  /// No description provided for @configAutoUpdateFeedOfficial.
  ///
  /// In en, this message translates to:
  /// **'Feed: official'**
  String get configAutoUpdateFeedOfficial;

  /// No description provided for @configAutoUpdateFeedCustom.
  ///
  /// In en, this message translates to:
  /// **'Feed: custom'**
  String get configAutoUpdateFeedCustom;

  /// No description provided for @configAutoUpdateNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Auto-update is unavailable because the configured feed is invalid. Remove AUTO_UPDATE_FEED_URL to use the official feed, or set it to a Sparkle feed (.xml).'**
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

  /// No description provided for @configUpdateTechnicalBackgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Background technical details'**
  String get configUpdateTechnicalBackgroundTitle;

  /// No description provided for @configUpdateTechnicalAutomaticTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic update technical details'**
  String get configUpdateTechnicalAutomaticTitle;

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

  /// No description provided for @configUpdateTechnicalProbeRequestUrl.
  ///
  /// In en, this message translates to:
  /// **'Probe URL'**
  String get configUpdateTechnicalProbeRequestUrl;

  /// No description provided for @configUpdateTechnicalProbeSucceeded.
  ///
  /// In en, this message translates to:
  /// **'HTTP probe succeeded'**
  String get configUpdateTechnicalProbeSucceeded;

  /// No description provided for @configUpdateTechnicalProbeMatchesSparkle.
  ///
  /// In en, this message translates to:
  /// **'Probe matches WinSparkle'**
  String get configUpdateTechnicalProbeMatchesSparkle;

  /// No description provided for @configUpdateTechnicalCompletionSource.
  ///
  /// In en, this message translates to:
  /// **'Check result'**
  String get configUpdateTechnicalCompletionSource;

  /// No description provided for @configUpdateTechnicalTriggerDurationMs.
  ///
  /// In en, this message translates to:
  /// **'Trigger duration (ms)'**
  String get configUpdateTechnicalTriggerDurationMs;

  /// No description provided for @configUpdateTechnicalTotalDurationMs.
  ///
  /// In en, this message translates to:
  /// **'Total duration (ms)'**
  String get configUpdateTechnicalTotalDurationMs;

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

  /// No description provided for @configUpdateTechnicalAssetName.
  ///
  /// In en, this message translates to:
  /// **'Asset name'**
  String get configUpdateTechnicalAssetName;

  /// No description provided for @configUpdateTechnicalAssetUrl.
  ///
  /// In en, this message translates to:
  /// **'Asset URL'**
  String get configUpdateTechnicalAssetUrl;

  /// No description provided for @configUpdateTechnicalAssetSize.
  ///
  /// In en, this message translates to:
  /// **'Asset size'**
  String get configUpdateTechnicalAssetSize;

  /// No description provided for @configUpdateTechnicalSha256.
  ///
  /// In en, this message translates to:
  /// **'Expected SHA-256'**
  String get configUpdateTechnicalSha256;

  /// No description provided for @configUpdateTechnicalActualSha256.
  ///
  /// In en, this message translates to:
  /// **'Actual SHA-256'**
  String get configUpdateTechnicalActualSha256;

  /// No description provided for @configUpdateTechnicalHashValidationStatus.
  ///
  /// In en, this message translates to:
  /// **'Hash validation'**
  String get configUpdateTechnicalHashValidationStatus;

  /// No description provided for @configUpdateTechnicalRolloutChannel.
  ///
  /// In en, this message translates to:
  /// **'Update channel'**
  String get configUpdateTechnicalRolloutChannel;

  /// No description provided for @configUpdateTechnicalRolloutPercentage.
  ///
  /// In en, this message translates to:
  /// **'Rollout percentage'**
  String get configUpdateTechnicalRolloutPercentage;

  /// No description provided for @configUpdateTechnicalRolloutBucket.
  ///
  /// In en, this message translates to:
  /// **'Rollout bucket'**
  String get configUpdateTechnicalRolloutBucket;

  /// No description provided for @configUpdateTechnicalRolloutEligible.
  ///
  /// In en, this message translates to:
  /// **'Rollout eligible'**
  String get configUpdateTechnicalRolloutEligible;

  /// No description provided for @configUpdateTechnicalPendingVersion.
  ///
  /// In en, this message translates to:
  /// **'Pending version'**
  String get configUpdateTechnicalPendingVersion;

  /// No description provided for @configUpdateTechnicalInstallerPath.
  ///
  /// In en, this message translates to:
  /// **'Installer path'**
  String get configUpdateTechnicalInstallerPath;

  /// No description provided for @configUpdateTechnicalInstallerLogPath.
  ///
  /// In en, this message translates to:
  /// **'Installer log'**
  String get configUpdateTechnicalInstallerLogPath;

  /// No description provided for @configUpdateTechnicalInstallDirectory.
  ///
  /// In en, this message translates to:
  /// **'Install directory'**
  String get configUpdateTechnicalInstallDirectory;

  /// No description provided for @configUpdateTechnicalUpdateDirectorySecurity.
  ///
  /// In en, this message translates to:
  /// **'Update directory security'**
  String get configUpdateTechnicalUpdateDirectorySecurity;

  /// No description provided for @configUpdateTechnicalInstallDirectoryWritable.
  ///
  /// In en, this message translates to:
  /// **'Install directory writable'**
  String get configUpdateTechnicalInstallDirectoryWritable;

  /// No description provided for @configUpdateTechnicalSilentStrategy.
  ///
  /// In en, this message translates to:
  /// **'Silent update strategy'**
  String get configUpdateTechnicalSilentStrategy;

  /// No description provided for @configUpdateTechnicalLauncherPath.
  ///
  /// In en, this message translates to:
  /// **'Launcher path'**
  String get configUpdateTechnicalLauncherPath;

  /// No description provided for @configUpdateTechnicalLauncherStatusPath.
  ///
  /// In en, this message translates to:
  /// **'Launcher status'**
  String get configUpdateTechnicalLauncherStatusPath;

  /// No description provided for @configUpdateTechnicalLauncherState.
  ///
  /// In en, this message translates to:
  /// **'Launcher state'**
  String get configUpdateTechnicalLauncherState;

  /// No description provided for @configUpdateTechnicalAppPid.
  ///
  /// In en, this message translates to:
  /// **'App PID'**
  String get configUpdateTechnicalAppPid;

  /// No description provided for @configUpdateTechnicalSignatureStatus.
  ///
  /// In en, this message translates to:
  /// **'Signature status'**
  String get configUpdateTechnicalSignatureStatus;

  /// No description provided for @configUpdateTechnicalSignatureRequired.
  ///
  /// In en, this message translates to:
  /// **'Signature required'**
  String get configUpdateTechnicalSignatureRequired;

  /// No description provided for @configUpdateTechnicalCheckId.
  ///
  /// In en, this message translates to:
  /// **'Check ID'**
  String get configUpdateTechnicalCheckId;

  /// No description provided for @configAutoUpdateClosingTitle.
  ///
  /// In en, this message translates to:
  /// **'Update ready'**
  String get configAutoUpdateClosingTitle;

  /// No description provided for @configAutoUpdateClosingBody.
  ///
  /// In en, this message translates to:
  /// **'Plug Agente will close in {seconds}s to install the update.'**
  String configAutoUpdateClosingBody(int seconds);

  /// No description provided for @configAutoUpdateReleaseNotesHeader.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get configAutoUpdateReleaseNotesHeader;

  /// No description provided for @configAutoUpdateReleaseNotesLink.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get configAutoUpdateReleaseNotesLink;

  /// No description provided for @autoUpdateReadyBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Update ready to install'**
  String get autoUpdateReadyBannerTitle;

  /// No description provided for @autoUpdateReadyBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Version {version} has been downloaded. The agent stays online; install it whenever you want to finish the update.'**
  String autoUpdateReadyBannerBody(String version);

  /// No description provided for @autoUpdateReadyBannerInstallNow.
  ///
  /// In en, this message translates to:
  /// **'Install now'**
  String get autoUpdateReadyBannerInstallNow;

  /// No description provided for @autoUpdateReadyBannerDefer.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get autoUpdateReadyBannerDefer;

  /// No description provided for @autoUpdateReadyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Install update now?'**
  String get autoUpdateReadyDialogTitle;

  /// No description provided for @autoUpdateReadyDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Plug Agente will close to install version {version}. The agent will be briefly offline until it reopens. Continue?'**
  String autoUpdateReadyDialogBody(String version);

  /// No description provided for @autoUpdateReadyDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Install and restart'**
  String get autoUpdateReadyDialogConfirm;

  /// No description provided for @autoUpdateReadyDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get autoUpdateReadyDialogCancel;

  /// No description provided for @autoUpdateApplyFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not start the installer. Try again or check the update diagnostics.'**
  String get autoUpdateApplyFailureMessage;

  /// No description provided for @autoUpdateConsentBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available — requires admin'**
  String get autoUpdateConsentBannerTitle;

  /// No description provided for @autoUpdateConsentBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available. Installing it triggers a Windows UAC prompt for administrator approval, so the automatic update did not run unattended.'**
  String autoUpdateConsentBannerBody(String version);

  /// No description provided for @autoUpdateConsentBannerInstall.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get autoUpdateConsentBannerInstall;

  /// No description provided for @autoUpdateConsentDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Install update now?'**
  String get autoUpdateConsentDialogTitle;

  /// No description provided for @autoUpdateConsentDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Plug Agente will download version {version} and then close to install it. Windows will ask for administrator approval (UAC) during installation. Continue?'**
  String autoUpdateConsentDialogBody(String version);

  /// No description provided for @autoUpdateConsentDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get autoUpdateConsentDialogConfirm;

  /// No description provided for @configUpdateTechnicalHelperSha256.
  ///
  /// In en, this message translates to:
  /// **'Helper SHA-256'**
  String get configUpdateTechnicalHelperSha256;

  /// No description provided for @configUpdateTechnicalHelperSignatureStatus.
  ///
  /// In en, this message translates to:
  /// **'Helper signature'**
  String get configUpdateTechnicalHelperSignatureStatus;

  /// No description provided for @configUpdateTechnicalFeedSignatureStatus.
  ///
  /// In en, this message translates to:
  /// **'Feed signature'**
  String get configUpdateTechnicalFeedSignatureStatus;

  /// No description provided for @configUpdateTechnicalFeedSignatureRequired.
  ///
  /// In en, this message translates to:
  /// **'Feed signature required'**
  String get configUpdateTechnicalFeedSignatureRequired;

  /// No description provided for @configUpdateTechnicalWaitForAppExitDurationMs.
  ///
  /// In en, this message translates to:
  /// **'Wait for app exit (ms)'**
  String get configUpdateTechnicalWaitForAppExitDurationMs;

  /// No description provided for @configUpdateTechnicalNonAdminExitCode.
  ///
  /// In en, this message translates to:
  /// **'Non-admin exit code'**
  String get configUpdateTechnicalNonAdminExitCode;

  /// No description provided for @configUpdateTechnicalNonAdminDurationMs.
  ///
  /// In en, this message translates to:
  /// **'Non-admin duration (ms)'**
  String get configUpdateTechnicalNonAdminDurationMs;

  /// No description provided for @configUpdateTechnicalElevatedExitCode.
  ///
  /// In en, this message translates to:
  /// **'Elevated exit code'**
  String get configUpdateTechnicalElevatedExitCode;

  /// No description provided for @configUpdateTechnicalElevatedDurationMs.
  ///
  /// In en, this message translates to:
  /// **'Elevated duration (ms)'**
  String get configUpdateTechnicalElevatedDurationMs;

  /// No description provided for @configUpdateTechnicalElevatedRetryStarted.
  ///
  /// In en, this message translates to:
  /// **'Elevated retry started'**
  String get configUpdateTechnicalElevatedRetryStarted;

  /// No description provided for @configUpdateTechnicalElevatedCancelled.
  ///
  /// In en, this message translates to:
  /// **'Elevated prompt cancelled'**
  String get configUpdateTechnicalElevatedCancelled;

  /// No description provided for @configUpdateTechnicalAutomaticFailureCount.
  ///
  /// In en, this message translates to:
  /// **'Automatic failure count'**
  String get configUpdateTechnicalAutomaticFailureCount;

  /// No description provided for @configUpdateTechnicalAutomaticCooldownUntil.
  ///
  /// In en, this message translates to:
  /// **'Automatic cooldown until'**
  String get configUpdateTechnicalAutomaticCooldownUntil;

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

  /// No description provided for @configUpdateCompletionSourceUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get configUpdateCompletionSourceUpdateAvailable;

  /// No description provided for @configUpdateCompletionSourceUpdateNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'No update available'**
  String get configUpdateCompletionSourceUpdateNotAvailable;

  /// No description provided for @configUpdateCompletionSourceUpdaterError.
  ///
  /// In en, this message translates to:
  /// **'Updater returned an error'**
  String get configUpdateCompletionSourceUpdaterError;

  /// No description provided for @configUpdateCompletionSourceTriggerTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout while triggering the updater'**
  String get configUpdateCompletionSourceTriggerTimeout;

  /// No description provided for @configUpdateCompletionSourceCompletionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout while waiting for updater completion'**
  String get configUpdateCompletionSourceCompletionTimeout;

  /// No description provided for @configUpdateCompletionSourceTriggerFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed to start the update check'**
  String get configUpdateCompletionSourceTriggerFailure;

  /// No description provided for @configUpdateCompletionSourceNotInitialized.
  ///
  /// In en, this message translates to:
  /// **'Auto-update not initialized'**
  String get configUpdateCompletionSourceNotInitialized;

  /// No description provided for @configUpdateCompletionSourceCircuitOpen.
  ///
  /// In en, this message translates to:
  /// **'Checks paused after repeated timeouts'**
  String get configUpdateCompletionSourceCircuitOpen;

  /// No description provided for @configUpdateCompletionSourceAutomaticDisabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic installation disabled'**
  String get configUpdateCompletionSourceAutomaticDisabled;

  /// No description provided for @configUpdateCompletionSourceAutomaticPendingCompleted.
  ///
  /// In en, this message translates to:
  /// **'Pending automatic update completed'**
  String get configUpdateCompletionSourceAutomaticPendingCompleted;

  /// No description provided for @configUpdateCompletionSourceAutomaticPendingFailed.
  ///
  /// In en, this message translates to:
  /// **'Pending automatic update did not complete'**
  String get configUpdateCompletionSourceAutomaticPendingFailed;

  /// No description provided for @configUpdateCompletionSourceAutomaticUpdateNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'No automatic update available'**
  String get configUpdateCompletionSourceAutomaticUpdateNotAvailable;

  /// No description provided for @configUpdateCompletionSourceAutomaticValidationFailure.
  ///
  /// In en, this message translates to:
  /// **'Automatic update validation failed'**
  String get configUpdateCompletionSourceAutomaticValidationFailure;

  /// No description provided for @configUpdateCompletionSourceAutomaticDownloadFailure.
  ///
  /// In en, this message translates to:
  /// **'Automatic update download failed'**
  String get configUpdateCompletionSourceAutomaticDownloadFailure;

  /// No description provided for @configUpdateCompletionSourceAutomaticInstallReady.
  ///
  /// In en, this message translates to:
  /// **'Update downloaded and ready to install'**
  String get configUpdateCompletionSourceAutomaticInstallReady;

  /// No description provided for @configUpdateCompletionSourceAutomaticAwaitingUserConsent.
  ///
  /// In en, this message translates to:
  /// **'Update available — waiting for admin confirmation'**
  String get configUpdateCompletionSourceAutomaticAwaitingUserConsent;

  /// No description provided for @autoUpdateApplyOutcomeCooldown.
  ///
  /// In en, this message translates to:
  /// **'Updates are paused after repeated failures. Try again later.'**
  String get autoUpdateApplyOutcomeCooldown;

  /// No description provided for @autoUpdateApplyOutcomeSilentDisabled.
  ///
  /// In en, this message translates to:
  /// **'Automatic updates are disabled. Re-enable them in Settings to install this update.'**
  String get autoUpdateApplyOutcomeSilentDisabled;

  /// No description provided for @autoUpdateApplyOutcomeCancelled.
  ///
  /// In en, this message translates to:
  /// **'The update was cancelled before the installer was ready.'**
  String get autoUpdateApplyOutcomeCancelled;

  /// No description provided for @autoUpdateApplyOutcomeQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Updates are paused during quiet hours. Try again outside the configured window.'**
  String get autoUpdateApplyOutcomeQuietHours;

  /// No description provided for @autoUpdateApplyOutcomeNoNewVersion.
  ///
  /// In en, this message translates to:
  /// **'No new version is available right now.'**
  String get autoUpdateApplyOutcomeNoNewVersion;

  /// No description provided for @autoUpdateApplyOutcomeAlreadyInProgress.
  ///
  /// In en, this message translates to:
  /// **'Another update check is still running. Try again in a moment.'**
  String get autoUpdateApplyOutcomeAlreadyInProgress;

  /// No description provided for @autoUpdateApplyOutcomePendingInProgress.
  ///
  /// In en, this message translates to:
  /// **'A previous update is still being applied.'**
  String get autoUpdateApplyOutcomePendingInProgress;

  /// No description provided for @autoUpdateApplyOutcomeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the installer. Open the update diagnostics for details.'**
  String get autoUpdateApplyOutcomeUnknown;

  /// No description provided for @autoUpdateApplyPhaseDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get autoUpdateApplyPhaseDownloading;

  /// No description provided for @autoUpdateApplyPhaseStaging.
  ///
  /// In en, this message translates to:
  /// **'Preparing installer…'**
  String get autoUpdateApplyPhaseStaging;

  /// No description provided for @autoUpdateApplyPhaseLaunching.
  ///
  /// In en, this message translates to:
  /// **'Launching update helper…'**
  String get autoUpdateApplyPhaseLaunching;

  /// No description provided for @configUpdateCompletionSourceAutomaticInstallStarted.
  ///
  /// In en, this message translates to:
  /// **'Automatic installer started'**
  String get configUpdateCompletionSourceAutomaticInstallStarted;

  /// No description provided for @configUpdateCompletionSourceAutomaticInstallFailure.
  ///
  /// In en, this message translates to:
  /// **'Automatic installer failed to start'**
  String get configUpdateCompletionSourceAutomaticInstallFailure;

  /// No description provided for @configUpdateCompletionSourceAutomaticCooldown.
  ///
  /// In en, this message translates to:
  /// **'Automatic updates paused'**
  String get configUpdateCompletionSourceAutomaticCooldown;

  /// No description provided for @configUpdateCompletionSourceAutomaticRolloutSkipped.
  ///
  /// In en, this message translates to:
  /// **'Automatic update skipped by rollout'**
  String get configUpdateCompletionSourceAutomaticRolloutSkipped;

  /// No description provided for @configUpdateCompletionSourceAutomaticCancelled.
  ///
  /// In en, this message translates to:
  /// **'Automatic update cancelled'**
  String get configUpdateCompletionSourceAutomaticCancelled;

  /// No description provided for @configUpdateCompletionSourceAutomaticQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Skipped by quiet hours'**
  String get configUpdateCompletionSourceAutomaticQuietHours;

  /// No description provided for @configCopyUpdateDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy update diagnostics'**
  String get configCopyUpdateDiagnostics;

  /// No description provided for @configUpdateDiagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Update diagnostics copied.'**
  String get configUpdateDiagnosticsCopied;

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

  /// No description provided for @gsToggleStartMinimizedNextLaunchHint.
  ///
  /// In en, this message translates to:
  /// **'Applies on the next Windows startup.'**
  String get gsToggleStartMinimizedNextLaunchHint;

  /// No description provided for @gsToggleStartMinimizedRequiresTray.
  ///
  /// In en, this message translates to:
  /// **'Requires tray support in this environment.'**
  String get gsToggleStartMinimizedRequiresTray;

  /// No description provided for @gsToggleStartMinimizedRequiresStartup.
  ///
  /// In en, this message translates to:
  /// **'Requires \"Start with Windows\" enabled.'**
  String get gsToggleStartMinimizedRequiresStartup;

  /// No description provided for @gsToggleStartWithWindowsAdminHint.
  ///
  /// In en, this message translates to:
  /// **'May request administrator privileges.'**
  String get gsToggleStartWithWindowsAdminHint;

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

  /// No description provided for @gsButtonRepairStartup.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get gsButtonRepairStartup;

  /// No description provided for @gsStartupLaunchConfigurationReady.
  ///
  /// In en, this message translates to:
  /// **'Startup entry is ready.'**
  String get gsStartupLaunchConfigurationReady;

  /// No description provided for @gsStartupLaunchConfigurationRepaired.
  ///
  /// In en, this message translates to:
  /// **'Startup entry repaired.'**
  String get gsStartupLaunchConfigurationRepaired;

  /// No description provided for @gsStartupLaunchConfigurationRepairFailed.
  ///
  /// In en, this message translates to:
  /// **'Startup entry needs repair'**
  String get gsStartupLaunchConfigurationRepairFailed;

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

  /// No description provided for @gsErrorSettingsPersistenceFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save local preference'**
  String get gsErrorSettingsPersistenceFailed;

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

  /// No description provided for @msgRpcAgentActionsTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Agent actions are temporarily unavailable. Wait and try again.'**
  String get msgRpcAgentActionsTemporarilyUnavailable;

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

  /// No description provided for @wsSectionPayloadSigning.
  ///
  /// In en, this message translates to:
  /// **'PayloadFrame signing'**
  String get wsSectionPayloadSigning;

  /// No description provided for @wsPayloadSigningStatusOk.
  ///
  /// In en, this message translates to:
  /// **'Payload signing ready'**
  String get wsPayloadSigningStatusOk;

  /// No description provided for @wsPayloadSigningStatusWarning.
  ///
  /// In en, this message translates to:
  /// **'Payload signing needs attention'**
  String get wsPayloadSigningStatusWarning;

  /// No description provided for @wsPayloadSigningStatusError.
  ///
  /// In en, this message translates to:
  /// **'Payload signing configuration is incomplete'**
  String get wsPayloadSigningStatusError;

  /// No description provided for @wsPayloadSigningMetaSigner.
  ///
  /// In en, this message translates to:
  /// **'Signer'**
  String get wsPayloadSigningMetaSigner;

  /// No description provided for @wsPayloadSigningMetaActiveKey.
  ///
  /// In en, this message translates to:
  /// **'Active key'**
  String get wsPayloadSigningMetaActiveKey;

  /// No description provided for @wsPayloadSigningMetaKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get wsPayloadSigningMetaKeys;

  /// No description provided for @wsPayloadSigningMetaSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get wsPayloadSigningMetaSource;

  /// No description provided for @wsPayloadSigningMetaRotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get wsPayloadSigningMetaRotation;

  /// No description provided for @wsPayloadSigningSignerConfigured.
  ///
  /// In en, this message translates to:
  /// **'configured'**
  String get wsPayloadSigningSignerConfigured;

  /// No description provided for @wsPayloadSigningSignerMissing.
  ///
  /// In en, this message translates to:
  /// **'missing'**
  String get wsPayloadSigningSignerMissing;

  /// No description provided for @wsPayloadSigningActiveKeyNone.
  ///
  /// In en, this message translates to:
  /// **'not selected'**
  String get wsPayloadSigningActiveKeyNone;

  /// No description provided for @wsPayloadSigningRotationReady.
  ///
  /// In en, this message translates to:
  /// **'ready'**
  String get wsPayloadSigningRotationReady;

  /// No description provided for @wsPayloadSigningRotationSingleKey.
  ///
  /// In en, this message translates to:
  /// **'single key'**
  String get wsPayloadSigningRotationSingleKey;

  /// No description provided for @wsPayloadSigningSourceNone.
  ///
  /// In en, this message translates to:
  /// **'not configured'**
  String get wsPayloadSigningSourceNone;

  /// No description provided for @wsPayloadSigningSourceEnvironment.
  ///
  /// In en, this message translates to:
  /// **'environment'**
  String get wsPayloadSigningSourceEnvironment;

  /// No description provided for @wsPayloadSigningSourceSecureStorage.
  ///
  /// In en, this message translates to:
  /// **'secure storage'**
  String get wsPayloadSigningSourceSecureStorage;

  /// No description provided for @wsPayloadSigningSourceEnvironmentAndSecureStorage.
  ///
  /// In en, this message translates to:
  /// **'environment + secure storage'**
  String get wsPayloadSigningSourceEnvironmentAndSecureStorage;

  /// No description provided for @wsPayloadSigningToggleOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Sign outgoing frames'**
  String get wsPayloadSigningToggleOutgoing;

  /// No description provided for @wsPayloadSigningToggleIncoming.
  ///
  /// In en, this message translates to:
  /// **'Require signed incoming frames'**
  String get wsPayloadSigningToggleIncoming;

  /// No description provided for @wsPayloadSigningHelp.
  ///
  /// In en, this message translates to:
  /// **'Keys are read from secure storage and PAYLOAD_SIGNING_* environment variables. Keep incoming signature enforcement off until the hub is confirmed to sign frames.'**
  String get wsPayloadSigningHelp;

  /// No description provided for @wsPayloadSigningIssueEnabledWithoutKey.
  ///
  /// In en, this message translates to:
  /// **'Outgoing PayloadFrame signing is enabled, but no active signing key is configured.'**
  String get wsPayloadSigningIssueEnabledWithoutKey;

  /// No description provided for @wsPayloadSigningIssueIncomingRequiredWithoutKey.
  ///
  /// In en, this message translates to:
  /// **'Incoming PayloadFrame signatures are required, but the agent cannot verify frames without a key.'**
  String get wsPayloadSigningIssueIncomingRequiredWithoutKey;

  /// No description provided for @wsPayloadSigningIssueActiveKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Signing keys exist, but no active key id is selected.'**
  String get wsPayloadSigningIssueActiveKeyMissing;

  /// No description provided for @wsPayloadSigningIssueActiveKeyNotFound.
  ///
  /// In en, this message translates to:
  /// **'The selected active signing key id is not present in the configured key set.'**
  String get wsPayloadSigningIssueActiveKeyNotFound;

  /// No description provided for @wsPayloadSigningIssueSecureStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Payload signing keys are configured, but secure storage is unavailable on this runtime.'**
  String get wsPayloadSigningIssueSecureStorageUnavailable;

  /// No description provided for @wsPayloadSigningIssueRotationSingleKey.
  ///
  /// In en, this message translates to:
  /// **'Only one signing key is configured. Add a second key before rotating key ids in production.'**
  String get wsPayloadSigningIssueRotationSingleKey;

  /// No description provided for @wsPayloadSigningIssueConfigNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Payload signing configuration was not registered at app startup.'**
  String get wsPayloadSigningIssueConfigNotRegistered;

  /// No description provided for @wsPayloadSigningIssueGenericWarning.
  ///
  /// In en, this message translates to:
  /// **'Payload signing configuration warning: {code}.'**
  String wsPayloadSigningIssueGenericWarning(String code);

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

  /// No description provided for @odbcErrorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load advanced settings.'**
  String get odbcErrorLoadFailed;

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
  /// **'All tables'**
  String get ctFlagAllTables;

  /// No description provided for @ctFlagAllViews.
  ///
  /// In en, this message translates to:
  /// **'All views'**
  String get ctFlagAllViews;

  /// No description provided for @ctFlagAllPermissions.
  ///
  /// In en, this message translates to:
  /// **'All permissions'**
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

  /// No description provided for @ctInfoClientTokenLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load this token secret'**
  String get ctInfoClientTokenLoadFailed;

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
  /// **'Filter by client ID or name'**
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

  /// No description provided for @ctNoRulesConfigured.
  ///
  /// In en, this message translates to:
  /// **'No specific rules configured'**
  String get ctNoRulesConfigured;

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

  /// No description provided for @ctErrorRuleOrGlobalPermissionsRequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one valid rule when global scope is disabled.'**
  String get ctErrorRuleOrGlobalPermissionsRequired;

  /// No description provided for @ctErrorGlobalPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one global permission when all_tables or all_views is enabled.'**
  String get ctErrorGlobalPermissionRequired;

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

  /// No description provided for @ctErrorPayloadDatabaseMustBeString.
  ///
  /// In en, this message translates to:
  /// **'payload.database must be a string.'**
  String get ctErrorPayloadDatabaseMustBeString;

  /// No description provided for @ctErrorPayloadDatabaseCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'payload.database must not be empty.'**
  String get ctErrorPayloadDatabaseCannotBeEmpty;

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

  /// No description provided for @ctRuleTypeTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get ctRuleTypeTable;

  /// No description provided for @ctRuleTypeView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get ctRuleTypeView;

  /// No description provided for @ctRuleTypeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get ctRuleTypeUnknown;

  /// No description provided for @ctRuleEffectAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get ctRuleEffectAllow;

  /// No description provided for @ctRuleEffectDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get ctRuleEffectDeny;

  /// No description provided for @ctDialogDismissCreateToken.
  ///
  /// In en, this message translates to:
  /// **'Dismiss create token dialog'**
  String get ctDialogDismissCreateToken;

  /// No description provided for @ctDialogDismissRule.
  ///
  /// In en, this message translates to:
  /// **'Dismiss rule dialog'**
  String get ctDialogDismissRule;

  /// No description provided for @ctPermissionDdl.
  ///
  /// In en, this message translates to:
  /// **'DDL'**
  String get ctPermissionDdl;

  /// No description provided for @ctGlobalScopeRulesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Global scope is enabled. Resource rules are hidden and will be removed when you save this token.'**
  String get ctGlobalScopeRulesDisabled;

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
  /// **'Edits to name, agent or payload keep the token. The token is rotated only when access rules change.'**
  String get ctEditUpdatesTokenHint;

  /// No description provided for @ctEditPolicyChangedHint.
  ///
  /// In en, this message translates to:
  /// **'Saving will rotate the token because the access rules changed.'**
  String get ctEditPolicyChangedHint;

  /// No description provided for @ctEditMetadataOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Access rules unchanged. The current token will be kept.'**
  String get ctEditMetadataOnlyHint;

  /// No description provided for @ctEditNoChangesHint.
  ///
  /// In en, this message translates to:
  /// **'No changes to save.'**
  String get ctEditNoChangesHint;

  /// No description provided for @ctMsgTokenRotated.
  ///
  /// In en, this message translates to:
  /// **'Token rotated. Copy the new value before closing.'**
  String get ctMsgTokenRotated;

  /// No description provided for @ctMsgTokenMetadataUpdated.
  ///
  /// In en, this message translates to:
  /// **'Token metadata updated. The token value was kept.'**
  String get ctMsgTokenMetadataUpdated;

  /// No description provided for @ctMsgTokenNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes detected. The token was not modified.'**
  String get ctMsgTokenNoChanges;

  /// No description provided for @ctButtonCopyToken.
  ///
  /// In en, this message translates to:
  /// **'Copy token'**
  String get ctButtonCopyToken;

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

  /// No description provided for @ctImportRulesErrorReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the selected file.'**
  String get ctImportRulesErrorReadFailed;

  /// No description provided for @ctImportRulesErrorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file exceeds the maximum allowed size (512 KB).'**
  String get ctImportRulesErrorFileTooLarge;

  /// No description provided for @ctExportRulesError.
  ///
  /// In en, this message translates to:
  /// **'Could not export the rules to the selected file.'**
  String get ctExportRulesError;

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

  /// No description provided for @connectionStatusHubReconnectingSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Hub: Signing in again...'**
  String get connectionStatusHubReconnectingSigningIn;

  /// No description provided for @connectionStatusHubReconnectingSocket.
  ///
  /// In en, this message translates to:
  /// **'Hub: Restoring connection...'**
  String get connectionStatusHubReconnectingSocket;

  /// No description provided for @connectionStatusHubReconnectingWaitingHub.
  ///
  /// In en, this message translates to:
  /// **'Hub: Waiting for server...'**
  String get connectionStatusHubReconnectingWaitingHub;

  /// No description provided for @connectionStatusHubReconnectingNegotiationTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Hub: Protocol negotiation stalled; retrying...'**
  String get connectionStatusHubReconnectingNegotiationTimedOut;

  /// No description provided for @connectionStatusSessionAuthenticated.
  ///
  /// In en, this message translates to:
  /// **'Session: signed in'**
  String get connectionStatusSessionAuthenticated;

  /// No description provided for @connectionStatusSessionUnauthenticated.
  ///
  /// In en, this message translates to:
  /// **'Session: not signed in'**
  String get connectionStatusSessionUnauthenticated;

  /// No description provided for @connectionStatusSessionError.
  ///
  /// In en, this message translates to:
  /// **'Session: error'**
  String get connectionStatusSessionError;

  /// No description provided for @wsSubtitleSessionWaitingForHub.
  ///
  /// In en, this message translates to:
  /// **'You are signed in; waiting for the hub connection to finish.'**
  String get wsSubtitleSessionWaitingForHub;

  /// No description provided for @diagnosticsHubRecoverySnapshotTitle.
  ///
  /// In en, this message translates to:
  /// **'Hub recovery (live)'**
  String get diagnosticsHubRecoverySnapshotTitle;

  /// No description provided for @diagnosticsHubRecoveryRecoveryId.
  ///
  /// In en, this message translates to:
  /// **'recovery_id'**
  String get diagnosticsHubRecoveryRecoveryId;

  /// No description provided for @diagnosticsHubRecoveryConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'connection_status'**
  String get diagnosticsHubRecoveryConnectionStatus;

  /// No description provided for @diagnosticsHubRecoveryUiHint.
  ///
  /// In en, this message translates to:
  /// **'ui_hint'**
  String get diagnosticsHubRecoveryUiHint;

  /// No description provided for @diagnosticsHubRecoveryConsecutiveFailures.
  ///
  /// In en, this message translates to:
  /// **'consecutive_failures'**
  String get diagnosticsHubRecoveryConsecutiveFailures;

  /// No description provided for @diagnosticsHubRecoveryPersistentTick.
  ///
  /// In en, this message translates to:
  /// **'persistent_tick_count'**
  String get diagnosticsHubRecoveryPersistentTick;

  /// No description provided for @diagnosticsHubRecoveryPersistentFailures.
  ///
  /// In en, this message translates to:
  /// **'persistent_failure_count'**
  String get diagnosticsHubRecoveryPersistentFailures;

  /// No description provided for @diagnosticsHubRecoveryHardReloginAttempted.
  ///
  /// In en, this message translates to:
  /// **'hard_relogin_attempted_in_cycle'**
  String get diagnosticsHubRecoveryHardReloginAttempted;

  /// No description provided for @diagnosticsHubRecoveryLastError.
  ///
  /// In en, this message translates to:
  /// **'last_error'**
  String get diagnosticsHubRecoveryLastError;

  /// No description provided for @diagnosticsHubRecoveryCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get diagnosticsHubRecoveryCopyAll;

  /// No description provided for @diagnosticsHubRecoveryCopiedToast.
  ///
  /// In en, this message translates to:
  /// **'Hub recovery diagnostics copied to the clipboard.'**
  String get diagnosticsHubRecoveryCopiedToast;

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

  /// No description provided for @formPasswordShow.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get formPasswordShow;

  /// No description provided for @formPasswordHide.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get formPasswordHide;

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
