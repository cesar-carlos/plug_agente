; Plug Agente - Inno Setup Script
; Version is updated by installer/update_version.py
; File encoding: UTF-8. Portuguese CustomMessages must use real Unicode
; characters; Inno does not expand #$XXXX escapes in [CustomMessages].

#include "constants.iss"
#define MyAppName "Plug Agente"
#define MyAppVersion "1.8.6"
#define MyAppPublisher "Se7e Sistemas"
#define MyAppURL "https://github.com/cesar-carlos/plug_agente"
#define MyAppExeName "plug_agente.exe"
#define VCRedistUrl "https://aka.ms/vs/17/release/vc_redist.x64.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=Copyright (C) 2026 {#MyAppPublisher}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableWelcomePage=yes
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=PlugAgente-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardImageFile=wizard\wizard-image.png
WizardSmallImageFile=wizard\wizard-small-image.png
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
MinVersion=10.0
; Prevent two Setup.exe instances (manual + silent helper) from racing.
; AppMutex is intentionally omitted: silent updates wait for the app PID
; first; an AppMutex check would abort /VERYSILENT if the process is still
; in its pre-close grace window.
SetupMutex=PlugAgenteSetup
CloseApplications=force
CloseApplicationsFilter=plug_agente.exe
SetupLogging=yes
#ifdef SIGN_INSTALLER
SignTool=mysigntool
SignedUninstaller=yes
#endif

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
english.StartWithWindows=Start with Windows
brazilianportuguese.StartWithWindows=Iniciar com o Windows
english.StartupOptionsGroup=Startup options
brazilianportuguese.StartupOptionsGroup=Opções de Inicialização
english.VCRedistDownloading=Downloading Microsoft Visual C++ Redistributable x64
brazilianportuguese.VCRedistDownloading=Baixando o Microsoft Visual C++ Redistributable x64
english.VCRedistDownloadFailed=Could not download Microsoft Visual C++ Redistributable x64. Check your internet connection and try again.%n{#VCRedistUrl}
brazilianportuguese.VCRedistDownloadFailed=Não foi possível baixar o Microsoft Visual C++ Redistributable x64. Verifique a conexão com a internet e tente novamente.%n{#VCRedistUrl}
english.VCRedistInstallFailed=Could not install Microsoft Visual C++ Redistributable x64.
brazilianportuguese.VCRedistInstallFailed=Não foi possível instalar o Microsoft Visual C++ Redistributable x64.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:StartWithWindows}"; GroupDescription: "{cm:StartupOptionsGroup}"

#ifndef COMPILE_SCRIPT_ONLY
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib,*.log"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent; Check: ShouldLaunchAfterSilentUpdate
; Write HKCU Run for the logged-on user (not the elevated admin token).
; Silent updates pass /MERGETASKS="!desktopicon,!startup", so this Task is skipped.
Filename: "{sys}\reg.exe"; Parameters: "{code:GetLoggedOnUserAutostartRegParams}"; Flags: runasoriginaluser runhidden; Tasks: startup

[Registry]
Root: HKLM; Subkey: "Software\Classes\plugdb"; ValueType: string; ValueName: ""; ValueData: "URL:Plug Agente Protocol"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\plugdb"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKLM; Subkey: "Software\Classes\plugdb\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKLM; Subkey: "Software\Classes\plugdb\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

; [UninstallRun] on Inno 6.6.1 does not accept runasoriginaluser.
; cmd swallows "value not found" so a missing Run key does not fail uninstall.
[UninstallRun]
Filename: "{cmd}"; Parameters: "/c reg delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""{#MyAppName}"" /f >nul 2>&1"; Flags: runhidden; RunOnceId: "RemoveAutostart"

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\PlugAgente\updates"
Type: files; Name: "{commonappdata}\PlugAgente\{#AutostartRequestMarker}"
Type: dirifempty; Name: "{commonappdata}\PlugAgente"

[Code]
function GetAutostartValue(Param: String): String;
begin
  Result := AddQuotes(ExpandConstant('{app}\{#MyAppExeName}')) + ' ' + AddQuotes('{#AutostartArg}');
end;

function GetLoggedOnUserAutostartRegParams(Param: String): String;
var
  ValueData: String;
begin
  ValueData := GetAutostartValue('');
  StringChangeEx(ValueData, '"', '\"', True);
  Result := 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "{#MyAppName}" /t REG_SZ /d "' + ValueData + '" /f';
end;

function ShouldLaunchAfterSilentUpdate(): Boolean;
begin
  Result := WizardSilent() and (ExpandConstant('{param:LAUNCHAFTERUPDATE|0}') = '1');
end;

procedure ConfigureSharedProgramDataPermissions;
var
  ResultCode: Integer;
  DataDir: String;
begin
  DataDir := ExpandConstant('{commonappdata}\PlugAgente');
  if not DirExists(DataDir) then
    CreateDir(DataDir);
  Exec(
    'icacls.exe',
    AddQuotes(DataDir) + ' /grant *S-1-5-11:(OI)(CI)(M) /grant *S-1-5-32-545:(OI)(CI)(M)',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
  if ResultCode <> 0 then
    Log('icacls on shared ProgramData failed with exit code ' + IntToStr(ResultCode))
  else
    Log('icacls on shared ProgramData succeeded');
end;

procedure WriteAutostartRequestMarker;
var
  MarkerPath: String;
begin
  MarkerPath := ExpandConstant('{commonappdata}\PlugAgente\{#AutostartRequestMarker}');
  SaveStringToFile(MarkerPath, '1', False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ConfigureSharedProgramDataPermissions;
    // Silent updates pass /MERGETASKS="!startup", so this does not re-request
    // auto-start. The app then writes HKCU for the interactive user.
    if WizardIsTaskSelected('startup') then
      WriteAutostartRequestMarker;
  end;
end;

function IsVCRedistInstalled(): Boolean;
var
  Installed: Cardinal;
begin
  if RegQueryDWordValue(
    HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed',
    Installed
  ) then
    Result := Installed = 1
  else
    Result := False;
end;

function IsVCRedistInstallExitCodeSuccess(ResultCode: Integer): Boolean;
begin
  Result := (ResultCode = 0) or (ResultCode = 1638) or (ResultCode = 3010);
end;

function DownloadAndInstallVCRedist(): String;
var
  DownloadPage: TDownloadWizardPage;
  ResultCode: Integer;
  RedistPath: String;
begin
  Result := '';
  DownloadPage := CreateDownloadPage(
    CustomMessage('VCRedistDownloading'),
    CustomMessage('VCRedistDownloading'),
    nil
  );
  DownloadPage.Clear;
  DownloadPage.Add('{#VCRedistUrl}', 'vc_redist.x64.exe', '');
  try
    try
      DownloadPage.Show;
      DownloadPage.Download;
    except
      Result := CustomMessage('VCRedistDownloadFailed');
      Log('VC++ Redistributable download failed: ' + GetExceptionMessage);
      Exit;
    end;
  finally
    DownloadPage.Hide;
  end;

  RedistPath := ExpandConstant('{tmp}\vc_redist.x64.exe');
  if not FileExists(RedistPath) then
  begin
    Result := CustomMessage('VCRedistDownloadFailed');
    Exit;
  end;

  if not Exec(
    RedistPath,
    '/install /quiet /norestart',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    Result := CustomMessage('VCRedistInstallFailed');
    Exit;
  end;

  if not IsVCRedistInstallExitCodeSuccess(ResultCode) then
  begin
    Log('VC++ Redistributable installer exit code: ' + IntToStr(ResultCode));
    Result := CustomMessage('VCRedistInstallFailed') + ' (' + IntToStr(ResultCode) + ')';
    Exit;
  end;

  if ResultCode = 3010 then
    Log('VC++ Redistributable installed with reboot pending (3010). Continuing.');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  NeedsRestart := False;
  if IsVCRedistInstalled() then
    Exit;
  Log('Microsoft Visual C++ Redistributable x64 was not detected. Downloading and installing.');
  Result := DownloadAndInstallVCRedist();
end;
