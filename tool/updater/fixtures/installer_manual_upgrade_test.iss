#define MyAppName "Plug Agente"
#define MyAppVersion "test"
#define MyAppWorkerVersion "test+1"
#define MyAppChannel "stable"

[Setup]
AppName=Plug Agente manual upgrade tests
AppVersion=1
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
OutputBaseFilename=installer-manual-upgrade-test

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[CustomMessages]
#include TestMessagesFile

[Code]
var
  UpdaterHostNeeded, UpdaterHostUpgradeAuthorized, UpdaterClientNeeded: Boolean;
  UpdaterInstallationSkipped, UpdaterWasPresent: Boolean;
  Selected, ClientMissing, ActiveOperation, RejectRevocation, PolicyEnabled: Boolean;
  Authorized: Cardinal;
  ContractChecks, Revocations, OperationChecks: Integer;

#include ProductionInstallerDir + "\installation_reporting.iss"
#include ProductionInstallerDir + "\installation_repair.iss"

procedure AssertTrue(const Condition: Boolean; const MessageText: String);
begin
  if not Condition then RaiseException(MessageText);
end;

function FixtureIsAdminInstallMode(): Boolean;
begin
  Result := True;
end;

function FixtureWizardSilent(): Boolean;
begin
  Result := False;
end;

function FixtureWizardIsTaskSelected(const Task: String): Boolean;
begin
  Result := Selected;
end;

function FixtureRegQueryDWordValue(const Root: Integer; const Key, Name: String; var Value: Cardinal): Boolean;
begin
  Value := Authorized;
  Result := True;
end;

function FixtureFileExists(const Filename: String): Boolean;
begin
  Result := not (ClientMissing and (ExtractFileName(Filename) = 'plug_update_client.exe'));
end;

procedure FixtureExtractTemporaryFile(const Filename: String);
begin
  AssertTrue(Filename = 'plug_update_client.exe', 'Only the embedded client is needed');
end;

procedure VerifyInstalledCore;
begin
  RaiseException('Manual full installation must not enter optional repair');
end;

function StoreUpdaterAuthorization(const Value: Cardinal): Boolean;
begin
  Authorized := Value;
  Result := True;
end;

function RunDependencyCommand(const Filename, Parameters: String; var Details: String): Boolean;
begin
  AssertTrue(Filename = ExpandConstant('{tmp}\plug_update_client.exe'), 'Must use embedded client, not legacy installed client');
  Details := '';
  Result := True;
  if Parameters = '--check-install 0' then
  begin
    OperationChecks := OperationChecks + 1;
    Result := not ActiveOperation;
    if not Result then Details := 'update_operation_prevents_manual_install';
  end
  else if Parameters = '--check-host-contract' then
  begin
    ContractChecks := ContractChecks + 1;
    Details := '{"code":"host_upgrade_required","ok":false}';
    Result := False;
  end
  else if Parameters = '--revoke' then
  begin
    Revocations := Revocations + 1;
    Result := not RejectRevocation;
    if Result then PolicyEnabled := False else Details := 'service_manager_denied';
  end
  else RaiseException('Unexpected updater command: ' + Parameters);
end;

#include ProductionInstallerDir + "\updater_recovery.iss"
#include ProductionInstallerDir + "\updater_install_preparation.iss"
#include TestProductionFile

function InitializeSetup(): Boolean;
var
  TestCase, ErrorText: String;
  NeedsRestart, Failed: Boolean;
begin
  Result := False;
  TestCase := ExpandConstant('{param:CASE}');
  UpdaterWasPresent := True;
  PolicyEnabled := True;
  Authorized := 1;
  ClientMissing := TestCase = 'missing_client';
  ActiveOperation := TestCase = 'active_operation';
  RejectRevocation := TestCase = 'revocation_failure';
  if TestCase = 'retry_after_contract_error' then
  begin
    Selected := True;
    ErrorText := RunPreparation(NeedsRestart);
    AssertTrue(ErrorText <> '', 'Legacy contract must reproduce the initial error');
    AssertTrue(ContractChecks = 1, 'Legacy contract must actually be checked');
    AssertTrue(CriticalInstallationError, 'Initial error must be recorded');
  end;
  Selected := False;
  ContractChecks := 0;
  ErrorText := RunPreparation(NeedsRestart);
  AssertTrue(OperationChecks > 0, 'Manual install must still check active operations');
  AssertTrue(ContractChecks = 0, 'Unchecked automatic updates must bypass legacy contract checks');
  if ActiveOperation then
    AssertTrue(ErrorText <> '', 'Active update must still prevent file replacement')
  else
  begin
    AssertTrue(ErrorText = '', 'Manual installation must pass preparation: ' + ErrorText);
    AssertTrue(not CriticalInstallationError, 'Retry must clear the old critical error');
    AssertTrue(not ShouldInstallUpdaterHost() and not ShouldInstallUpdaterClient() and
      not ShouldInstallUpdaterWorker(), 'Manual installation must not copy updater components');
    AssertTrue(ShouldCopyApplicationFiles(), 'Manual installation must copy application files');
    Failed := False;
    try
      ConfigureUpdaterAuthorization;
    except
      Failed := True;
    end;
    AssertTrue(Revocations = 1, 'Existing authorization must be revoked exactly once');
    if RejectRevocation then
      AssertTrue(Failed and CriticalInstallationError and PolicyEnabled, 'Unsafe revocation cannot be reported as success')
    else
    begin
      AssertTrue(not Failed and not CriticalInstallationError, 'Manual configuration must complete');
      AssertTrue(not PolicyEnabled and (Authorized = 0), 'Policy and Windows authorization must both be disabled');
      AssertTrue(not HasInstallationWarnings(), 'Legacy contract alone must not produce warnings');
    end;
  end;
  AssertTrue(SaveStringToFile(ExpandConstant('{param:RESULT}'), 'passed', False), 'Cannot save assertions');
end;
