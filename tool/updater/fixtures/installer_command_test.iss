[Setup]
AppName=Private bounded command regression
AppVersion=1
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
OutputBaseFilename=installer-command-test
[Code]
#include ProductionInstallerDir + "\installation_command.iss"
function InitializeSetup(): Boolean;
var
  Details, Exe: String;
begin
  Result := False;
  Exe := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if RunInstallationCommand(Exe, '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"', 200, Details) then
    RaiseException('Blocked command accepted');
  if Details <> 'installation_command_timeout_unknown' then RaiseException(Details);
  if not RunInstallationCommand(Exe, '-NoProfile -NonInteractive -Command "Write-Output bounded-success"', 15000, Details) then
    RaiseException('Success failed: ' + Details);
  if Pos('bounded-success', Details) = 0 then RaiseException('Output lost');
  if RunInstallationCommand(Exe, '-NoProfile -NonInteractive -Command "exit 7"', 15000, Details) then
    RaiseException('Nonzero exit accepted');
  if Pos('Exit code: 7', Details) = 0 then RaiseException('Exit code lost');
  SaveStringToFile(ExpandConstant('{param:RESULT}'), 'passed', False);
end;
