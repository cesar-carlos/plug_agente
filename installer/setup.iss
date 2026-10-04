; Plug Agente - Inno Setup Script
; Version is updated by installer/update_version.py
; File encoding: UTF-8. Portuguese CustomMessages must use real Unicode
; characters; Inno does not expand #$XXXX escapes in [CustomMessages].

#include "constants.iss"
#define MyAppName "Plug Agente"
#define MyAppVersion "1.8.6"
#ifndef MyAppWorkerVersion
  #ifdef SIGN_INSTALLER
    #error Signed installers require the exact MyAppWorkerVersion including build number
  #else
    #define MyAppWorkerVersion MyAppVersion + "+1"
  #endif
#endif
#define MyAppPublisher "Se7e Sistemas"
#define MyAppURL "https://github.com/cesar-carlos/plug_agente"
#define MyAppExeName "plug_agente.exe"
#define VCRedistUrl "https://aka.ms/vs/17/release/vc_redist.x64.exe"
#ifndef MyAppChannel
  #define MyAppChannel "stable"
#endif
#ifndef MinimumVCMinor
  #define MinimumVCMinor 43
#endif

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
SetupMutex=Global\PlugAgenteSetup
CloseApplications=yes
CloseApplicationsFilter=plug_agente.exe
; The app registers crash restart only; the update helper relaunches it via
; LAUNCHAFTERUPDATE, so Restart Manager must not start a second instance.
RestartApplications=no
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
english.AutomaticUpdate=Update automatically (Windows service; briefly restarts the agent; additional permissions require approval)
brazilianportuguese.AutomaticUpdate=Atualizar automaticamente (serviço Windows; reinicia brevemente o agente; permissões adicionais exigem aprovação)
english.UpdateOptionsGroup=Update authorization
brazilianportuguese.UpdateOptionsGroup=Autorização de atualizações
english.UpdaterEnrollmentFailed=Could not authorize the update service. Installation cannot enable automatic updates.
brazilianportuguese.UpdaterEnrollmentFailed=Não foi possível autorizar o serviço de atualização. A instalação não pode habilitar atualizações automáticas.
english.VCRedistDownloading=Downloading Microsoft Visual C++ Redistributable x64
brazilianportuguese.VCRedistDownloading=Baixando o Microsoft Visual C++ Redistributable x64
english.VCRedistDownloadFailed=Could not download Microsoft Visual C++ Redistributable x64. Check your internet connection and try again.%n{#VCRedistUrl}
brazilianportuguese.VCRedistDownloadFailed=Não foi possível baixar o Microsoft Visual C++ Redistributable x64. Verifique a conexão com a internet e tente novamente.%n{#VCRedistUrl}
english.VCRedistInstallFailed=Could not install Microsoft Visual C++ Redistributable x64.
brazilianportuguese.VCRedistInstallFailed=Não foi possível instalar o Microsoft Visual C++ Redistributable x64.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:StartWithWindows}"; GroupDescription: "{cm:StartupOptionsGroup}"
Name: "autoupdate"; Description: "{cm:AutomaticUpdate}"; GroupDescription: "{cm:UpdateOptionsGroup}"; Check: IsAdminInstallMode

#ifndef COMPILE_SCRIPT_ONLY
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib,*.log,updater,updater\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\updater\plug_update_client.exe"; Flags: dontcopy
Source: "..\build\windows\x64\runner\Release\updater\plug_update_service.exe"; DestDir: "{commonpf}\PlugAgenteUpdater"; Flags: ignoreversion; Check: ShouldInstallUpdaterHost
Source: "..\build\windows\x64\runner\Release\updater\plug_update_client.exe"; DestDir: "{commonpf}\PlugAgenteUpdater"; Flags: ignoreversion; Check: ShouldInstallUpdaterHost
Source: "..\build\windows\x64\runner\Release\updater\plug_update_worker.exe"; DestDir: "{commonpf}\PlugAgenteUpdater\workers\{#MyAppWorkerVersion}"; Flags: ignoreversion; Check: ShouldInstallUpdaterWorker
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent runasoriginaluser
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent runasoriginaluser; Check: ShouldLaunchAfterSilentUpdate
; Write HKCU Run for the logged-on user (not the elevated admin token).
; Silent updates pass /MERGETASKS="!desktopicon,!startup", so this Task is skipped.
Filename: "{sys}\reg.exe"; Parameters: "{code:GetLoggedOnUserAutostartRegParams}"; Flags: runasoriginaluser runhidden; Tasks: startup

[Registry]
Root: HKA; Subkey: "Software\Classes\plugdb"; ValueType: string; ValueName: ""; ValueData: "URL:Plug Agente Protocol"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\plugdb"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\plugdb\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\plugdb\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

; [UninstallRun] on Inno 6.6.1 does not accept runasoriginaluser.
; cmd swallows "value not found" so a missing Run key does not fail uninstall.
[UninstallRun]
Filename: "{cmd}"; Parameters: "/c reg delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""{#MyAppName}"" /f >nul 2>&1"; Flags: runhidden; RunOnceId: "RemoveAutostart"

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\PlugAgente\updates"
Type: files; Name: "{commonappdata}\PlugAgente\{#AutostartRequestMarker}"
Type: dirifempty; Name: "{commonappdata}\PlugAgente"

[Code]
var
  RuntimeRebootPending: Boolean;
  UpdaterHostNeeded: Boolean;

function UpdaterExists(): Boolean;
begin
  Result := FileExists(ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_service.exe'));
end;

function WantsAutomaticUpdates(): Boolean;
var
  Authorized: Cardinal;
begin
  Result := False;
  if not IsAdminInstallMode then
    Exit;
  if WizardSilent() then
  begin
    // A normal preference is never administrative authorization. Only this
    // protected registration or an explicit initial-install argument counts.
    if RegQueryDWordValue(HKLM64, 'Software\Se7e Sistemas\PlugAgenteUpdater', 'Authorized', Authorized) then
      Result := (Authorized = 1) and UpdaterExists()
    else
      Result := ExpandConstant('{param:AUTOUPDATE|0}') = '1';
  end
  else
    Result := WizardIsTaskSelected('autoupdate');
end;

function ShouldInstallUpdaterHost(): Boolean;
begin
  Result := UpdaterHostNeeded;
end;

function ShouldInstallUpdaterWorker(): Boolean;
begin
  Result := IsAdminInstallMode and WantsAutomaticUpdates();
end;

procedure ConfigureUpdaterAuthorization;
var
  ClientPath: String;
  ResultCode: Integer;
begin
  if not IsAdminInstallMode then
    Exit;
  ClientPath := ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_client.exe');
  if WantsAutomaticUpdates() then
  begin
    // The supervisor survives routine bundle/worker updates. Enrollment is an
    // administrative transition, never an implicit action of a silent upgrade.
    if UpdaterHostNeeded or not WizardSilent() then
    begin
      if not Exec(ClientPath, '--enroll ' + AddQuotes(ExpandConstant('{app}')) + ' ' +
          AddQuotes(ExpandConstant('{srcexe}')) + ' ' + ExpandConstant('{param:CHANNEL|{#MyAppChannel}}') + ' {#MyAppWorkerVersion}', '',
          SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
        RaiseException(CustomMessage('UpdaterEnrollmentFailed'));
      if not RegWriteDWordValue(HKLM64, 'Software\Se7e Sistemas\PlugAgenteUpdater', 'Authorized', 1) then
        RaiseException(CustomMessage('UpdaterEnrollmentFailed'));
    end;
  end
  else if not WizardSilent() and FileExists(ClientPath) then
  begin
    if not Exec(ClientPath, '--revoke', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      RaiseException(CustomMessage('UpdaterEnrollmentFailed'));
    RegWriteDWordValue(HKLM64, 'Software\Se7e Sistemas\PlugAgenteUpdater', 'Authorized', 0);
  end;
end;

function InitializeSetup(): Boolean;
var
  ClientPath: String;
  ResultCode: Integer;
begin
  Result := True;
  ClientPath := ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_client.exe');
  if FileExists(ClientPath) then
    Result := Exec(ClientPath, '--check-install ' + ExpandConstant('{param:UPDATERSERVICE|0}'), '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  if not Result then
    Log('Installation blocked by an active updater operation or pending recovery.');
end;

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

procedure DeleteAutostartRegistryValue(const RootKey: Integer; const RootLabel, SubKeyName: String);
begin
  if RegValueExists(RootKey, SubKeyName, '{#MyAppName}') then
  begin
    if RegDeleteValue(RootKey, SubKeyName, '{#MyAppName}') then
      Log('Removed auto-start value from ' + RootLabel + '\' + SubKeyName)
    else
      Log('Failed to remove auto-start value from ' + RootLabel + '\' + SubKeyName);
  end;
end;

// Uninstall runs elevated, so HKCU may belong to the admin rather than the
// user who enabled auto-start. Every signed-in user's hive is loaded under
// HKEY_USERS; profiles of signed-out users are not reachable without loading
// their NTUSER.DAT and keep a harmless stale entry.
procedure RemoveLoadedUserProfileAutostartValues;
var
  Sids: TArrayOfString;
  I: Integer;
begin
  if not RegGetSubkeyNames(HKU, '', Sids) then
  begin
    Log('Could not enumerate HKEY_USERS for auto-start cleanup');
    Exit;
  end;
  for I := 0 to GetArrayLength(Sids) - 1 do
  begin
    if (Pos('S-1-5-21-', Sids[I]) = 1) and (Pos('_Classes', Sids[I]) = 0) then
    begin
      DeleteAutostartRegistryValue(HKU, 'HKU', Sids[I] + '\{#RunKeyPath}');
      DeleteAutostartRegistryValue(HKU, 'HKU', Sids[I] + '\{#StartupApprovedRunKeyPath}');
    end;
  end;
end;

// Legacy builds wrote machine-wide Run values; the app itself only writes HKCU
// and the StartupApproved overlay, which [UninstallRun] does not cover.
procedure RemoveAutostartRegistryValues;
begin
  DeleteAutostartRegistryValue(HKLM64, 'HKLM64', '{#RunKeyPath}');
  DeleteAutostartRegistryValue(HKLM32, 'HKLM32', '{#RunKeyPath}');
  DeleteAutostartRegistryValue(HKCU, 'HKCU', '{#StartupApprovedRunKeyPath}');
  RemoveLoadedUserProfileAutostartValues;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveAutostartRegistryValues;
end;

function InitializeUninstall(): Boolean;
var
  ClientPath: String;
  ResultCode: Integer;
begin
  Result := True;
  ClientPath := ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_client.exe');
  if IsAdminInstallMode and FileExists(ClientPath) then
    Result := Exec(ClientPath, '--remove-service', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  if Result and IsAdminInstallMode then
    RegDeleteKeyIncludingSubkeys(HKLM64, 'Software\Se7e Sistemas\PlugAgenteUpdater');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ConfigureUpdaterAuthorization;
    ConfigureSharedProgramDataPermissions;
    if IsAdminInstallMode then
      SetIniString('installation', 'mode', 'global', ExpandConstant('{app}\install-mode.ini'))
    else
      SetIniString('installation', 'mode', 'user', ExpandConstant('{app}\install-mode.ini'));
    SetIniString('installation', 'directory', ExpandConstant('{app}'), ExpandConstant('{app}\install-mode.ini'));
    SetIniString('installation', 'channel', ExpandConstant('{param:CHANNEL|{#MyAppChannel}}'), ExpandConstant('{app}\install-mode.ini'));
    if RuntimeRebootPending then
      SetIniString('installation', 'runtimeRebootPending', '1', ExpandConstant('{app}\install-mode.ini'));
    // Silent updates pass /MERGETASKS="!startup", so this does not re-request
    // auto-start. The app then writes HKCU for the interactive user.
    if WizardIsTaskSelected('startup') then
      WriteAutostartRequestMarker;
  end;
end;

function IsVCRedistInstalled(): Boolean;
var
  Installed, Major, Minor: Cardinal;
begin
  if RegQueryDWordValue(
    HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed',
    Installed
  ) then
    Result := (Installed = 1) and
      RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Major', Major) and
      RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Minor', Minor) and
      ((Major > 14) or ((Major = 14) and (Minor >= {#MinimumVCMinor})))
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
  QuotedRedistPath: String;
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

  QuotedRedistPath := RedistPath;
  StringChangeEx(QuotedRedistPath, '''', '''''', True);
  // Verify Microsoft identity and the Windows trust chain online before elevation.
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "$s=Get-AuthenticodeSignature -LiteralPath ''' +
    QuotedRedistPath + '''; if($s.Status -ne ''Valid'' -or $s.SignerCertificate.Subject -notmatch ''O=Microsoft Corporation(?:,|$)''){exit 1}; ' +
    '$c=New-Object Security.Cryptography.X509Certificates.X509Chain; ' +
    '$c.ChainPolicy.RevocationMode=''Online''; $c.ChainPolicy.RevocationFlag=''ExcludeRoot''; ' +
    'if(-not $c.Build($s.SignerCertificate)){exit 1}; exit 0"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
  begin
    Result := CustomMessage('VCRedistInstallFailed');
    Log('Microsoft runtime trust validation failed. Installation blocked.');
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
  begin
    RuntimeRebootPending := True;
    Log('VC++ Redistributable installed with reboot pending (3010). Continuing without automatic restart.');
  end;
  if not IsVCRedistInstalled() then
    Result := CustomMessage('VCRedistInstallFailed');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  NeedsRestart := False;
  // Native enrollment tools depend on this runtime on a fresh Windows install.
  if not IsVCRedistInstalled() then
  begin
    Log('Microsoft Visual C++ Redistributable x64 was not detected. Downloading and installing.');
    Result := DownloadAndInstallVCRedist();
    if Result <> '' then
      Exit;
  end;
  UpdaterHostNeeded := WantsAutomaticUpdates() and not UpdaterExists();
  if WantsAutomaticUpdates() then
  begin
    // Execute the installer-embedded client before copying privileged files:
    // existing user-owned/reparse directories must fail ACL validation.
    ExtractTemporaryFile('plug_update_client.exe');
    if not Exec(ExpandConstant('{tmp}\plug_update_client.exe'), '--prepare-control {#MyAppWorkerVersion}', '', SW_HIDE,
        ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    begin
      Result := CustomMessage('UpdaterEnrollmentFailed');
      Exit;
    end;
  end;
end;
