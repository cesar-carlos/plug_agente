var
  InstallationOperation: String;
  InstallationRequested: Boolean;
  ManifestMigrationAttempted: Boolean;
  InstallationGuardOwned: Boolean;
  InstallationGuardHandle: THandle;
  InstallationCommandUnknown: Boolean;

function OpenInstallationGuard(Name: String; Access, Sharing: Cardinal;
  Security: Integer; Creation, Flags: Cardinal; Template: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';
function CloseInstallationGuard(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function InstallationTickCount: Cardinal;
  external 'GetTickCount@kernel32.dll stdcall';

procedure ReleaseInstallationGuard;
var
  Details: String;
begin
  if InstallationRequested and not InstallationCommandUnknown and not RunInstallationCommand(ExpandConstant('{tmp}\plug_update_client.exe'),
    '--prepare-install ' + AddQuotes(ExpandConstant('{app}')) + ' ' + InstallationOperation + ' cancel', 5000, Details) then
    Log('Cancellation does not confirm restoration: ' + Details);
  if InstallationGuardOwned then
  begin
    if not CloseInstallationGuard(InstallationGuardHandle) then
      RaiseException('Could not remove installation startup guard; manual recovery required');
    InstallationGuardOwned := False;
  end;
end;

function PrepareRunningInstallation(var Details: String): Boolean;
var
  Command, Client: String;
  Attempt: Integer;
  Started, Elapsed: Cardinal;
begin
  Result := False;
  if InstallationCommandUnknown then
  begin
    Details := 'installation_command_timeout_unknown';
    Exit;
  end;
  ExtractTemporaryFile('plug_update_client.exe');
  Client := ExpandConstant('{tmp}\plug_update_client.exe');
  if DirExists(ExpandConstant('{app}')) and not InstallationGuardOwned then
  begin
    if FileExists(ExpandConstant('{app}\.installation-lock')) then
    begin
      Details := 'Previous installation guard requires manual recovery';
      Exit;
    end;
    // CREATE_NEW refuses an existing/reparse leaf; delete-on-close owns cleanup.
    InstallationGuardHandle := OpenInstallationGuard(ExpandConstant('{app}\.installation-lock'),
      $40000000, $00000001, 0, 1, $04000000, 0);
    if InstallationGuardHandle = THandle(-1) then
    begin
      Details := 'Could not persist installation startup guard';
      Exit;
    end;
    InstallationGuardOwned := True;
  end;
  if InstallationOperation = '' then
    InstallationOperation := Copy(GetSHA256OfString(ExpandConstant('{srcexe}') +
      GetDateTimeString('yyyymmddhhnnsszzz', #0, #0) + ExpandConstant('{tmp}')), 1, 32);
  Command := 'status';
  if not InstallationRequested then Command := 'request';
  // Set before dispatch. Even a lost response never permits another request.
  InstallationRequested := True;
  Started := InstallationTickCount;
  for Attempt := 0 to 59 do
  begin
    Elapsed := InstallationTickCount - Started;
    if Elapsed >= 59000 then Exit;
    Result := RunInstallationCommand(Client, '--prepare-install ' +
      AddQuotes(ExpandConstant('{app}')) + ' ' + InstallationOperation + ' ' + Command,
      59000 - Elapsed, Details);
    if Pos('installation_command_', Details) > 0 then
    begin
      InstallationCommandUnknown := True;
      Exit;
    end;
    Command := 'status';
    if Result then Exit;
    if Pos('installation_waiting_for_exit', Details) = 0 then Exit;
    Elapsed := InstallationTickCount - Started;
    if Elapsed >= 59000 then Exit;
    if 59000 - Elapsed < 1000 then Sleep(59000 - Elapsed)
    else Sleep(1000);
  end;
end;

function PrepareManifestPolicy(var Details: String): Boolean;
var
  Client: String;
begin
  Client := ExpandConstant('{tmp}\plug_update_client.exe');
  Result := RunDependencyCommand(Client, '--check-manifest-policy ' + AddQuotes(ExpandConstant('{app}')), Details);
  if Result or (Pos('manifest_migration_required', Details) = 0) then Exit;
  if not CanMigrateManifestPolicy(IsAdminInstallMode, WizardSilent(), ManifestMigrationAttempted) then Exit;
  if ExpandConstant('{param:MIGRATEMANIFEST|0}') <> '1' then
    if MsgBox(CustomMessage('ManifestMigrationConsent'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then Exit;
  ManifestMigrationAttempted := True;
  Result := RunDependencyCommand(Client, '--migrate-manifest ' + AddQuotes(ExpandConstant('{app}')), Details);
end;
