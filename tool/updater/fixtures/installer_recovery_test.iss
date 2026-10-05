#define MyAppName "Plug Agente"
#define MyAppVersion "test"
#define MyAppWorkerVersion "test+1"
#define MyAppChannel "stable"

[Setup]
AppName=Plug Agente installer recovery tests
AppVersion=1
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
DisableWelcomePage=yes
DisableFinishedPage=yes
OutputBaseFilename=installer-recovery-test
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[CustomMessages]
#include TestMessagesFile

[Code]
var
  UpdaterInstallationSkipped, UpdaterHostNeeded: Boolean;
  RejectRevocation, RejectAuthorizationWrite: Boolean;
  CommandCount, AuthorizationWriteCount: Integer;
  LastCommand: String;

#include ProductionInstallerDir + "\installation_reporting.iss"

function RunDependencyCommand(const Filename, Parameters: String; var Details: String): Boolean;
begin
  CommandCount := CommandCount + 1;
  LastCommand := Parameters;
  Details := 'simulated service permission failure';
  Result := not RejectRevocation;
end;

function StoreUpdaterAuthorization(const Authorized: Cardinal): Boolean;
begin
  if Authorized <> 0 then
    RaiseException('Recovery must never enable automatic updates');
  AuthorizationWriteCount := AuthorizationWriteCount + 1;
  Result := not RejectAuthorizationWrite;
end;

#include ProductionInstallerDir + "\updater_recovery.iss"
#include ProductionInstallerDir + "\installation_repair.iss"

procedure AssertTrue(const Condition: Boolean; const Failure: String);
begin
  if not Condition then
    RaiseException(Failure);
end;

function InitializeSetup(): Boolean;
var
  TestCase, ReportPath: String;
  CriticalErrorRaised: Boolean;
begin
  Result := False;
  TestCase := ExpandConstant('{param:CASE}');
  ReportPath := ExpandConstant('{param:REPORT}');
  UpdaterHostNeeded := True;
  if TestCase = 'initial_preparation_failure' then
  begin
    AssertTrue(CanSkipUpdaterPreparation(False, False), 'Fresh manual install must continue');
    SkipUpdaterInstallation('missing optional dependency');
    AssertTrue(UpdaterInstallationSkipped and not UpdaterHostNeeded, 'Privileged updater copying must be skipped');
    AssertTrue(HasInstallationWarnings(), 'The failed dependency must be reported');
  end
  else if TestCase = 'existing_updater_preparation_failure' then
    AssertTrue(not CanSkipUpdaterPreparation(True, False), 'Unconfirmed existing updater state must block installation')
  else if TestCase = 'service_update_preparation_failure' then
    AssertTrue(not CanSkipUpdaterPreparation(False, True), 'Automatic service updates must never bypass preparation')
  else if TestCase = 'failed_enrollment_cleanup_failure' then
  begin
    RejectRevocation := True;
    CriticalErrorRaised := False;
    try
      RecoverUpdaterEnrollmentFailure('fixture.exe', 'service registration failed');
    except
      CriticalErrorRaised := True;
    end;
    AssertTrue(CriticalErrorRaised, 'Unconfirmed revocation must remain a critical error');
    AssertTrue(CriticalInstallationError, 'Critical errors must request the full installer log');
    AssertTrue(not UpdaterInstallationSkipped, 'Failed cleanup must never be reported as recovered');
    AssertTrue(AuthorizationWriteCount = 0, 'Registry status cannot replace actual revocation');
    AssertTrue(not HasInstallationWarnings(), 'Critical failure cannot become a successful warning');
  end
  else if (TestCase = 'failed_enrollment_recovered') or (TestCase = 'authorization_metadata_failure') then
  begin
    RejectAuthorizationWrite := TestCase = 'authorization_metadata_failure';
    RecoverUpdaterEnrollmentFailure('fixture.exe', '{"ok":false,"code":"feed_keys_unavailable"}');
    AssertTrue((CommandCount = 1) and (LastCommand = '--revoke'), 'Recovery must revoke actual service authorization');
    AssertTrue(AuthorizationWriteCount = 1, 'Recovery must clear the Windows authorization marker');
    AssertTrue(UpdaterInstallationSkipped and not UpdaterHostNeeded, 'Recovered install must disable automatic updates');
    AssertTrue(HasInstallationWarnings(), 'Failed enrollment must preserve its repair instructions');
    if RejectAuthorizationWrite then
      AssertTrue(GetArrayLength(InstallationWarnings) = 2, 'Registry metadata failure must also be reported');
  end
  else if TestCase = 'report_write_failure_fallback' then
  begin
    RecordInstallationWarning('optional dependency unavailable', 'repair the optional feature', 'exit code 1');
    PersistInstallationWarnings(ReportPath + '\missing\report.log', ReportPath);
    AssertTrue(InstallationReportPath = ReportPath, 'Report failure must fall back to a persistent file');
    AssertTrue(GetArrayLength(InstallationWarnings) = 2, 'Report persistence failure must also be visible');
  end
  else if TestCase = 'failure_policy' then
  begin
    AssertTrue(not IsCriticalInstallationFailure(ifOptionalFeature), 'Optional feature failures must continue');
    AssertTrue(not IsCriticalInstallationFailure(ifDataAccess), 'Missing driver or data access must warn');
    AssertTrue(IsCriticalInstallationFailure(ifCoreRuntime), 'Broken application core must stop');
    AssertTrue(IsCriticalInstallationFailure(ifUpdaterSafety), 'Unsafe updater state must stop');
  end
  else if TestCase = 'core_failure' then
  begin
    CriticalErrorRaised := False;
    try
      RecordInstallationIssue(ifCoreRuntime, 'core_boot_failed', 'plug_agente.exe',
        'agent cannot start', 'restore application files', 'exit code 3');
    except
      CriticalErrorRaised := True;
    end;
    AssertTrue(CriticalErrorRaised and CriticalInstallationError, 'Core failure must stop and preserve its log');
    AssertTrue(not HasInstallationWarnings(), 'Core failure cannot be reported as successful');
  end
  else if TestCase = 'optional_repair_mode' then
  begin
    AssertTrue(IsOptionalRepair(), 'Explicit optional repair must be recognized');
    AssertTrue(not ShouldCopyApplicationFiles(), 'Repair must never copy the core application again');
  end
  else if TestCase = 'optional_repair_identity' then
  begin
    AssertTrue(ValidateOptionalRepair('test+1', 'user', 'stable', False, False), 'Matching user repair must be permitted');
    AssertTrue(ValidateOptionalRepair('test+1', 'global', 'stable', True, False), 'Matching global repair must be permitted');
    AssertTrue(not ValidateOptionalRepair('test+2', 'global', 'stable', True, False), 'Different build cannot repair');
    AssertTrue(not ValidateOptionalRepair('test+1', 'global', 'beta', True, False), 'Different channel cannot repair');
    AssertTrue(not ValidateOptionalRepair('test+1', 'user', 'stable', True, False), 'Different privilege mode cannot repair');
    AssertTrue(not ValidateOptionalRepair('test+1', 'global', 'stable', True, True), 'Service update cannot request repair');
  end
  else if TestCase = 'data_access_warning' then
    RecordInstallationIssue(ifDataAccess, 'odbc_driver_missing', 'ODBC x64',
      'database connections unavailable', 'install database driver', 'SQL_NO_DATA')
  else if TestCase = 'clean_installation' then
  begin
    AssertTrue(not HasInstallationWarnings(), 'Clean installation must have no warnings');
    AssertTrue(not WriteInstallationWarningReport(ReportPath), 'Clean install must not create an error report');
    AssertTrue(not ShouldOpenInstallationReport(False), 'Clean install must not open a report');
    AssertTrue(not FileExists(ReportPath), 'No stale report may be created');
  end
  else
    RaiseException('Unknown test case');

  if HasInstallationWarnings() then
  begin
    AssertTrue(WriteInstallationWarningReport(ReportPath), 'Warning report must be written');
    AssertTrue(ShouldOpenInstallationReport(False), 'Interactive install must open its warning report');
    AssertTrue(not ShouldOpenInstallationReport(True), 'Silent service install must not open desktop UI');
  end;
  AssertTrue(SaveStringToFile(ExpandConstant('{param:RESULT}'), 'passed', False), 'Could not save test result');
end;
