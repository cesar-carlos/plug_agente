function CanSkipUpdaterPreparation(const ExistingUpdater, ServiceUpdate: Boolean): Boolean;
begin
  Result := not ExistingUpdater and not ServiceUpdate;
end;

procedure SkipUpdaterInstallation(const Details: String);
var
  Summary, RepairAction: String;
begin
  UpdaterInstallationSkipped := True;
  UpdaterHostNeeded := False;
  Summary := CustomMessage('UpdaterOptionalFailed');
  RepairAction := CustomMessage('UpdaterRepairAction');
  if Pos('"feed_keys_unavailable"', Details) > 0 then
  begin
    Summary := CustomMessage('UpdaterFeedKeysMissing');
    RepairAction := CustomMessage('UpdaterFeedKeysRepairAction');
  end;
  RecordInstallationIssue(ifOptionalFeature, 'updater_disabled', 'PlugAgenteUpdater', Summary,
    RepairAction, Details);
end;

procedure RecoverUpdaterEnrollmentFailure(const ClientPath, FailureDetails: String);
var
  CleanupDetails: String;
begin
  // Enrollment can fail after enabling the policy. Confirm revocation before continuing.
  if not RunDependencyCommand(ClientPath, '--revoke', CleanupDetails) then
  begin
    RecordInstallationIssue(ifUpdaterSafety, 'updater_revocation_failed', 'PlugAgenteUpdater',
      CustomMessage('UpdaterDisableCritical'), CustomMessage('UpdaterAuthorizationRepairAction'), CleanupDetails);
  end;
  if not StoreUpdaterAuthorization(0) then
    RecordInstallationIssue(ifOptionalFeature, 'updater_authorization_write_failed', 'HKLM64\Software\Se7e Sistemas\PlugAgenteUpdater', CustomMessage('UpdaterAuthorizationSaveFailed'),
      CustomMessage('UpdaterAuthorizationRepairAction'), 'Authorized=0');
  SkipUpdaterInstallation(FailureDetails);
end;
