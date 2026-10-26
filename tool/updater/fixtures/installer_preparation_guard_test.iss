[Setup]
AppName=Private installation guard regression
AppVersion=1
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
OutputBaseFilename=installer-preparation-guard-test
SetupLogging=yes
[Code]
var
  Requests, Queries, Cancellations: Integer;
  ManualClosure, ApplicationRunning: Boolean;
  FirstParameters: String;
procedure AssertTrue(Value: Boolean; MessageText: String);
begin
  if not Value then RaiseException(MessageText);
end;
procedure FixtureExtractTemporaryFile(Name: String);
begin
  AssertTrue(Name = 'plug_update_client.exe', 'Unexpected extraction');
end;
function RunDependencyCommand(const Filename, Parameters: String; var Details: String): Boolean;
begin
  if Pos(' request', Parameters) > 0 then
  begin
    Requests := Requests + 1;
    FirstParameters := Copy(Parameters, 1, Length(Parameters) - Length(' request'));
  end
  else if Pos(' status', Parameters) > 0 then
  begin
    Queries := Queries + 1;
    AssertTrue(Parameters = FirstParameters + ' status', 'Verification changed installation or operation');
  end
  else if Pos(' cancel', Parameters) > 0 then Cancellations := Cancellations + 1
  else RaiseException('Unexpected command');
  Details := '';
  Result := True;
  if ManualClosure and ApplicationRunning then
  begin
    Details := '{"code":"close_previous_application_manually","ok":false}';
    Result := False;
  end;
end;
function CanMigrateManifestPolicy(const Administrator, Silent, Attempted: Boolean): Boolean;
begin
  Result := False;
end;
#include TestProductionFile
function InitializeSetup(): Boolean;
var
  Details, Directory, Guard, TestCase: String;
begin
  Result := False;
  Directory := ExpandConstant('{tmp}\guard-app');
  Guard := Directory + '\.installation-lock';
  TestCase := ExpandConstant('{param:CASE}');
  if TestCase <> 'new' then AssertTrue(ForceDirectories(Directory), 'Fixture directory failed');
  if TestCase = 'guard_directory' then
  begin
    AssertTrue(ForceDirectories(Guard), 'Fixture guard directory failed');
    AssertTrue(not PrepareRunningInstallation(Details), 'Invalid guard creation must block');
    AssertTrue((Requests = 0) and not InstallationGuardOwned, 'Failed guard must not dispatch');
    AssertTrue(DirExists(Guard), 'Existing guard directory removed');
  end
  else if TestCase = 'existing_guard' then
  begin
    AssertTrue(SaveStringToFile(Guard, 'preserve', False), 'Fixture guard failed');
    AssertTrue(not PrepareRunningInstallation(Details), 'Existing guard was overwritten');
    AssertTrue((Requests = 0) and not InstallationGuardOwned, 'Existing evidence must block dispatch');
    AssertTrue(FileExists(Guard), 'Existing guard removed');
  end
  else
  begin
    try
      ManualClosure := TestCase = 'manual_closure';
      if ManualClosure then
      begin
        ApplicationRunning := True;
        AssertTrue(not PrepareRunningInstallation(Details), 'Running application must block');
        AssertTrue(Pos('close_previous_application_manually', Details) > 0, 'Manual closure diagnostic missing');
        AssertTrue(not PrepareRunningInstallation(Details), 'Repeated check must remain blocked while running');
        AssertTrue((Requests = 1) and (Queries = 1), 'Blocked verification replayed request');
        AssertTrue(InstallationGuardOwned and FileExists(Guard), 'Blocked verification lost startup guard');
        ApplicationRunning := False;
      end;
      AssertTrue(PrepareRunningInstallation(Details), 'Preparation failed after closure: ' + Details);
      AssertTrue(Requests = 1, 'Request not dispatched');
      AssertTrue(InstallationGuardOwned = (TestCase <> 'new'), 'Guard ownership mismatch');
      if InstallationGuardOwned then AssertTrue(FileExists(Guard), 'Live guard missing');
      AssertTrue(PrepareRunningInstallation(Details), 'Status query failed: ' + Details);
      if ManualClosure then
        AssertTrue((Requests = 1) and (Queries = 3), 'Manual closure replayed request')
      else
        AssertTrue((Requests = 1) and (Queries = 1), 'Verification replayed request');
    finally
      ReleaseInstallationGuard;
    end;
    AssertTrue(not FileExists(Guard), 'Guard not deleted on close');
    AssertTrue(Cancellations = 1, 'Cancellation missing');
  end;
  AssertTrue(SaveStringToFile(ExpandConstant('{param:RESULT}'), 'passed', False), 'Result write failed');
end;
