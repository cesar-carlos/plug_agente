function IsOptionalRepair(): Boolean;
begin
  Result := ExpandConstant('{param:REPAIR|}') = 'optional';
end;

function ShouldCopyApplicationFiles(): Boolean;
begin
  Result := not IsOptionalRepair();
end;

function ValidateOptionalRepair(const InstalledWorkerVersion, InstalledMode,
  InstalledChannel: String; const AdminMode, ServiceUpdate: Boolean): Boolean;
begin
  Result := (InstalledWorkerVersion = '{#MyAppWorkerVersion}') and
    (((InstalledMode = 'global') and AdminMode) or ((InstalledMode = 'user') and not AdminMode)) and
    (InstalledChannel = ExpandConstant('{param:CHANNEL|{#MyAppChannel}}')) and not ServiceUpdate;
end;

function GetOptionalRepairCommand(): String;
begin
  Result := AddQuotes(ExpandConstant('{srcexe}')) + ' /REPAIR=optional /DIR=' +
    AddQuotes(ExpandConstant('{app}')) + ' /CHANNEL=' + ExpandConstant('{param:CHANNEL|{#MyAppChannel}}');
  if not IsAdminInstallMode then
    Result := Result + ' /CURRENTUSER';
end;

procedure AppendOptionalRepairInstructions;
begin
  if HasInstallationWarnings() then
    InstallationRepairInstructions := CustomMessage('OptionalRepairDescription') + #13#10 +
      GetOptionalRepairCommand() + #13#10 + CustomMessage('OptionalRepairTaskInstructions');
end;
