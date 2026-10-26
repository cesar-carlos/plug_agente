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
  DialogCalls, HostUpgrades, Enrollments, DialogChoice: Integer;
  SilentMode, StopFailure, OtherContractFailure: Boolean;
  ClosureCase: String;
  PreparationChecks: Integer;

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
  Result := SilentMode;
end;

procedure FixtureWizardSelectTasks(const Tasks: String);
begin
  AssertTrue(Tasks = '!autoupdate', 'Only automatic updates may be deselected');
  Selected := False;
end;

function FixtureTaskDialogMsgBox(const Instruction, Text: String; const Typ: TMsgBoxType;
  const Buttons: Cardinal; const Labels: TArrayOfString; const ShieldButton: Integer): Integer;
begin
  DialogCalls := DialogCalls + 1;
  AssertTrue(not SilentMode, 'Silent installs must never display a dialog');
  if ClosureCase <> '' then
  begin
    AssertTrue(Buttons = MB_RETRYCANCEL, 'Closure must offer a real retry/cancel choice');
    AssertTrue((GetArrayLength(Labels) = 1) and (Labels[0] <> ''), 'Retry needs a visible label');
    Result := IDCANCEL;
    if ClosureCase = 'closure_retry' then Result := IDRETRY;
    if ClosureCase = 'closure_channel_busy' then
    begin
      AssertTrue(Pos(CustomMessage('InstallationChannelBusy'), Text) > 0, 'Busy channel must have a distinct diagnostic');
      Result := IDRETRY;
    end;
    if ClosureCase = 'closure_operations' then
      AssertTrue(Pos(CustomMessage('InstallationBusy'), Text) > 0, 'Blocked operations must explain manual exit');
    Exit;
  end;
  AssertTrue(Buttons = (MB_YESNOCANCEL or MB_DEFBUTTON1), 'First option must be the default, with cancellation available');
  AssertTrue((GetArrayLength(Labels) = 2) and (Labels[0] = CustomMessage('UpdaterHostContinueManual')) and
    (Labels[1] = CustomMessage('UpdaterHostContinueUpgrade')), 'Manual continuation must be the first choice');
  AssertTrue(ShieldButton = IDNO, 'Only upgrading the service has the administrative shield');
  Result := DialogChoice;
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
  AssertTrue(IsOptionalRepair(), 'Manual full installation must not enter optional repair');
end;

function StoreUpdaterAuthorization(const Value: Cardinal): Boolean;
begin
  Authorized := Value;
  Result := True;
end;

function RunDependencyCommand(const Filename, Parameters: String; var Details: String): Boolean;
begin
  if Pos('--enroll ', Parameters) = 1 then
  begin
    AssertTrue(HostUpgrades = 1, 'Only the replaced host may be enrolled');
    AssertTrue(Filename = ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_client.exe'), 'Enroll with the newly installed client');
  end
  else
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
    if OtherContractFailure then Details := '{"code":"binary_hash_mismatch","ok":false}';
    Result := False;
  end
  else if Parameters = '--revoke' then
  begin
    Revocations := Revocations + 1;
    Result := not RejectRevocation;
    if Result then PolicyEnabled := False else Details := 'service_manager_denied';
  end
  else if Parameters = '--prepare-host-upgrade' then
  begin
    HostUpgrades := HostUpgrades + 1;
    PolicyEnabled := False;
    Result := not StopFailure;
    if StopFailure then Details := 'host_stop_unconfirmed';
  end
  else if Pos('--prepare-control ', Parameters) = 1 then
    AssertTrue(HostUpgrades = 1, 'Control preparation must follow explicit host upgrade')
  else if Pos('--enroll ', Parameters) = 1 then
  begin
    Enrollments := Enrollments + 1;
    PolicyEnabled := True;
  end
  else RaiseException('Unexpected updater command: ' + Parameters);
end;

#include ProductionInstallerDir + "\updater_recovery.iss"
#include ProductionInstallerDir + "\updater_install_preparation.iss"
function PrepareRunningInstallation(var Details: String): Boolean;
begin
  PreparationChecks := PreparationChecks + 1;
  Result := (ClosureCase = '') or (PreparationChecks > 1);
  if not Result then
  begin
    Details := 'close_previous_application_manually';
    if ClosureCase = 'closure_recovery' then Details := 'installation_recovery_required';
    if ClosureCase = 'closure_unknown' then Details := 'Exit code: -1073741515';
    if ClosureCase = 'closure_channel_busy' then Details := 'installation_channel_busy';
    if ClosureCase = 'closure_operations' then Details := 'installation_operations_active';
  end;
end;
function PrepareManifestPolicy(var Details: String): Boolean;
begin
  Result := True;
end;
#include TestProductionFile

function InitializeSetup(): Boolean;
var
  TestCase, ErrorText: String;
  NeedsRestart, Failed: Boolean;
begin
  Result := False;
  TestCase := ExpandConstant('{param:CASE}');
  if Pos('closure_', TestCase) = 1 then
  begin
    ClosureCase := TestCase;
    SilentMode := TestCase = 'closure_silent';
    ErrorText := RunPreparation(NeedsRestart);
    if (TestCase = 'closure_retry') or (TestCase = 'closure_channel_busy') then
      AssertTrue((ErrorText = '') and (PreparationChecks = 2) and (DialogCalls = 1),
        'Manual closure must allow a fresh verification in the same installer')
    else
    begin
      AssertTrue((ErrorText <> '') and (PreparationChecks = 1), 'Blocked/cancelled preparation must not dispatch again');
      AssertTrue((ExpandConstant('{log}') <> '') and (Pos(ExpandConstant('{log}'), ErrorText) > 0),
        'Blocked preparation must show the actual installer log path');
      if (TestCase = 'closure_cancel') or (TestCase = 'closure_operations') then AssertTrue(DialogCalls = 1, 'Operator must be able to cancel the retry dialog')
      else AssertTrue(DialogCalls = 0, 'Silent, unknown and recovery states must not offer retry');
      if TestCase = 'closure_unknown' then
        AssertTrue(Pos('-1073741515', ErrorText) > 0, 'Unknown helper failure must expose diagnostics, not claim a running process');
    end;
    AssertTrue(not NeedsRestart and (OperationChecks = 0) and (HostUpgrades = 0), 'Closure failure must not mutate updater or request reboot');
    AssertTrue(SaveStringToFile(ExpandConstant('{param:RESULT}'), 'passed', False), 'Cannot save assertions');
    Exit;
  end;
  UpdaterWasPresent := True;
  PolicyEnabled := True;
  Authorized := 1;
  if Pos('silent_repair_', TestCase) = 1 then
  begin
    SilentMode := True;
    AssertTrue(IsOptionalRepair(), 'Repair regression requires the real repair flag');
    AssertTrue(ForceDirectories(ExpandConstant('{tmp}\fixture-app')), 'Cannot create private repair metadata');
    AssertTrue(SaveStringToFile(ExpandConstant('{tmp}\fixture-app\install-mode.ini'),
      '[installation]' + #13#10 + 'workerVersion=test+1' + #13#10 + 'mode=global' + #13#10 + 'channel=stable', False),
      'Cannot save private repair metadata');
    if TestCase = 'silent_repair_enabled' then
      AssertTrue(WantsAutomaticUpdates(), 'Explicit optional updater repair must remain available')
    else
    begin
      ErrorText := RunPreparation(NeedsRestart);
      AssertTrue(ErrorText = '', 'Optional repair without auto-update must bypass the legacy contract');
      AssertTrue((OperationChecks = 1) and (ContractChecks = 0), 'Repair keeps the safety check only');
      AssertTrue(not ShouldInstallUpdaterHost() and not ShouldInstallUpdaterClient() and
        not ShouldInstallUpdaterWorker(), 'Optional repair must not copy updater binaries');
      AssertTrue(not ShouldCopyApplicationFiles(), 'Optional repair must not replace the core');
      ConfigureUpdaterAuthorization;
      AssertTrue((Enrollments = 0) and (Revocations = 0) and PolicyEnabled and (Authorized = 1),
        'Unrequested updater repair must preserve existing authorization without enrollment or revocation');
    end;
    AssertTrue(SaveStringToFile(ExpandConstant('{param:RESULT}'), 'passed', False), 'Cannot save assertions');
    Exit;
  end;
  DialogChoice := IDCANCEL;
  ClientMissing := TestCase = 'missing_client';
  ActiveOperation := TestCase = 'active_operation';
  RejectRevocation := TestCase = 'revocation_failure';
  if TestCase = 'retry_after_contract_error' then
  begin
    Selected := True;
    ErrorText := RunPreparation(NeedsRestart);
    AssertTrue(ErrorText <> '', 'Legacy contract must reproduce the initial error');
    AssertTrue(ContractChecks = 1, 'Legacy contract must actually be checked');
    AssertTrue(DialogCalls = 1, 'Legacy contract must offer interactive choices');
  end;
  Selected := False;
  DialogCalls := 0;
  if Pos('dialog_', TestCase) = 1 then Selected := True;
  if TestCase = 'dialog_manual' then DialogChoice := IDYES;
  if (TestCase = 'dialog_upgrade') or (TestCase = 'dialog_stop_failure') then DialogChoice := IDNO;
  StopFailure := TestCase = 'dialog_stop_failure';
  SilentMode := TestCase = 'silent_legacy';
  OtherContractFailure := TestCase = 'other_contract_failure';
  if OtherContractFailure then Selected := True;
  if TestCase = 'dialog_active_operation' then ActiveOperation := True;
  ContractChecks := 0;
  ErrorText := RunPreparation(NeedsRestart);
  AssertTrue(OperationChecks > 0, 'Manual install must still check active operations');
  if (Pos('dialog_', TestCase) <> 1) and not SilentMode and not OtherContractFailure then
    AssertTrue(ContractChecks = 0, 'Unchecked automatic updates must bypass legacy contract checks');
  if TestCase = 'dialog_upgrade' then
  begin
    AssertTrue((ErrorText = '') and (DialogCalls = 1) and (HostUpgrades = 1), 'Explicit service upgrade must continue in the same installation');
    AssertTrue(ShouldInstallUpdaterHost() and ShouldInstallUpdaterClient() and ShouldInstallUpdaterWorker(), 'Upgrade must replace all updater components');
    AssertTrue(not PolicyEnabled and (Authorized = 0), 'Old authorization must be disabled before replacement');
    ConfigureUpdaterAuthorization;
    AssertTrue((Enrollments = 1) and PolicyEnabled and (Authorized = 1), 'New host must be enrolled and authorized');
  end
  else if (TestCase = 'dialog_cancel') or StopFailure or SilentMode or OtherContractFailure then
  begin
    AssertTrue(ErrorText <> '', 'Unresolved or cancelled preparation must prevent installation');
    AssertTrue(not ShouldInstallUpdaterHost() and (Enrollments = 0), 'Failure must never install or enroll a new host');
    if SilentMode or OtherContractFailure then AssertTrue(DialogCalls = 0, 'Only interactive legacy-contract failures offer migration');
    if StopFailure then AssertTrue(not PolicyEnabled and (Authorized = 0), 'Failed stop must keep authorization disabled');
    if TestCase = 'dialog_cancel' then AssertTrue(PolicyEnabled and (Authorized = 1) and (HostUpgrades = 0), 'Cancel must not authorize or mutate the service');
  end
  else if ActiveOperation then
  begin
    AssertTrue(ErrorText <> '', 'Active update must still prevent file replacement');
    AssertTrue(DialogCalls = 0, 'Active operation must block before offering choices');
  end
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
      if TestCase = 'dialog_manual' then AssertTrue((DialogCalls = 1) and not Selected and (HostUpgrades = 0), 'Manual choice must deselect automatic updates without replacing the host');
    end;
  end;
  AssertTrue(SaveStringToFile(ExpandConstant('{param:RESULT}'), 'passed', False), 'Cannot save assertions');
end;
