function IsUpdaterHostRegistered(const HostPresent, PolicyPresent: Boolean): Boolean;
begin
  // A missing IPC client requires client repair, never replacement of a live host.
  Result := HostPresent and PolicyPresent;
end;

function ValidateUpdaterOperationBeforeInstall(const UpdaterPresent, Automatic: Boolean;
  const EmbeddedClient: String; var Details: String): Boolean;
var
  Mode: String;
begin
  Result := True;
  if not UpdaterPresent and not Automatic then
    Exit;
  if Automatic then Mode := '1' else Mode := '0';
  Result := RunDependencyCommand(EmbeddedClient, '--check-install ' + Mode, Details);
end;

function CanAdministrativelyUpgradeUpdaterHost(const Administrator, Automatic,
  WantsUpdater: Boolean): Boolean;
begin
  Result := Administrator and not Automatic and WantsUpdater;
end;
