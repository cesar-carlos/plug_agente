; Plug Agente - Inno Setup Script
; Version is updated by installer/update_version.py
; File encoding: UTF-8. Portuguese CustomMessages must use real Unicode
; characters; Inno does not expand #$XXXX escapes in [CustomMessages].

#include "constants.iss"
#define MyAppName "Plug Agente"
#define MyAppVersion "1.8.6"
#ifndef MyAppWorkerVersion
  #if defined(SIGN_INSTALLER) || defined(ExternalSignedUninstallerDir)
    #error Signed installers require the exact MyAppWorkerVersion including build number
  #else
    #define MyAppWorkerVersion MyAppVersion + "+1"
  #endif
#endif
#define MyAppPublisher "Se7e Sistemas"
#define MyAppURL "https://github.com/cesar-carlos/plug_agente"
#define MyAppExeName "plug_agente.exe"
#ifndef MyAppChannel
  #define MyAppChannel "stable"
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
VersionInfoVersion={#StringChange(MyAppWorkerVersion, "+", ".")}
VersionInfoProductTextVersion={#MyAppWorkerVersion}
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
#ifdef PrivacyNoticeFile
InfoBeforeFile={#PrivacyNoticeFile}
#endif
#ifdef SIGN_INSTALLER
SignTool=mysigntool
SignedUninstaller=yes
#else
  #ifdef ExternalSignedUninstallerDir
SignedUninstaller=yes
SignedUninstallerDir={#ExternalSignedUninstallerDir}
  #endif
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
english.UpdaterOptionalFailed=Automatic updates could not be configured. The agent was installed with this feature disabled.
brazilianportuguese.UpdaterOptionalFailed=Não foi possível configurar as atualizações automáticas. O agente foi instalado com esse recurso desabilitado.
english.UpdaterRepairAction=Use manual updates. Check the signing certificate, feed keys and service permissions, then run the installer again to enable automatic updates.
brazilianportuguese.UpdaterRepairAction=Use atualizações manuais. Verifique o certificado de assinatura, as chaves do feed e as permissões do serviço; depois execute o instalador novamente para habilitar as atualizações automáticas.
english.UpdaterFeedKeysMissing=Automatic updates were disabled because the updater was built without the public keys needed to verify updates. The agent was installed.
brazilianportuguese.UpdaterFeedKeysMissing=As atualizações automáticas foram desabilitadas porque o atualizador foi compilado sem as chaves públicas necessárias para verificar as atualizações. O agente foi instalado.
english.UpdaterFeedKeysRepairAction=Use manual updates. Ask support for a corrected installer built with the feed public keys configured. Running this same installer again will not fix the missing keys.
brazilianportuguese.UpdaterFeedKeysRepairAction=Use atualizações manuais. Solicite ao suporte um instalador corrigido, gerado com as chaves públicas do feed configuradas. Executar este mesmo instalador novamente não corrige a ausência das chaves.
english.UpdaterDisableCritical=Critical error: automatic updates could not be safely disabled. Check the updater policy and service permissions before installing again.
brazilianportuguese.UpdaterDisableCritical=Erro grave: não foi possível desabilitar as atualizações automáticas com segurança. Verifique a política e as permissões do serviço antes de instalar novamente.
english.UpdaterPreparationCritical=Critical error: the existing update service could not be safely prepared. Resolve the updater permissions or pending recovery before installing again.
brazilianportuguese.UpdaterPreparationCritical=Erro grave: não foi possível preparar o serviço de atualização existente com segurança. Resolva as permissões do serviço ou a recuperação pendente antes de instalar novamente.
english.UpdaterOperationCritical=Installation is blocked by an active update, pending recovery or an unavailable safety check. Finish the update or repair the updater service before trying again.
brazilianportuguese.UpdaterOperationCritical=A instalação foi bloqueada por uma atualização em andamento, recuperação pendente ou falha na verificação de segurança. Conclua a atualização ou repare o serviço antes de tentar novamente.
english.UpdaterAuthorizationSaveFailed=The updater was disabled, but its authorization status could not be saved in Windows.
brazilianportuguese.UpdaterAuthorizationSaveFailed=O serviço de atualização foi desabilitado, mas não foi possível salvar seu estado de autorização no Windows.
english.UpdaterAuthorizationRepairAction=Check access to the PlugAgenteUpdater registry key and run the installer again to synchronize the service authorization.
brazilianportuguese.UpdaterAuthorizationRepairAction=Verifique o acesso à chave de registro PlugAgenteUpdater e execute o instalador novamente para sincronizar a autorização do serviço.
english.InstallationRequiredAction=Required action:
brazilianportuguese.InstallationRequiredAction=Ajuste necessário:
english.InstallationTechnicalDetails=Technical details:
brazilianportuguese.InstallationTechnicalDetails=Detalhes técnicos:
english.InstallationReportTitle=Installation warnings and required actions
brazilianportuguese.InstallationReportTitle=Avisos da instalação e ajustes necessários
english.InstallationWarningsSummary=Installation completed with warnings. Review the required actions below.
brazilianportuguese.InstallationWarningsSummary=A instalação foi concluída com avisos. Revise os ajustes necessários abaixo.
english.InstallationWarningsCompleted=Installation completed with warnings. Review the required actions below. The report will open when you finish the installer.
brazilianportuguese.InstallationWarningsCompleted=A instalação foi concluída com avisos. Revise os ajustes necessários no relatório, que será aberto ao concluir o instalador.
english.InstallationFullLog=Full installer log:
brazilianportuguese.InstallationFullLog=Log completo do instalador:
english.InstallationReportFooter=Keep this report for support. After applying the fixes, run the installer again if necessary.
brazilianportuguese.InstallationReportFooter=Guarde este relatório para o suporte. Após aplicar os ajustes, execute o instalador novamente se necessário.
english.InstallationReportSaveFailed=The warning report could not be saved in the application folder.
brazilianportuguese.InstallationReportSaveFailed=Não foi possível salvar o relatório de avisos na pasta do aplicativo.
english.InstallationReportSaveAction=Check folder permissions. A backup report is saved beside the full installer log when possible.
brazilianportuguese.InstallationReportSaveAction=Verifique as permissões da pasta. Quando possível, uma cópia do relatório é salva junto ao log completo do instalador.
english.InstallationReportOpenFailed=The installation warning report could not be opened automatically.
brazilianportuguese.InstallationReportOpenFailed=Não foi possível abrir o relatório de avisos automaticamente.
english.InstallationReportOpenAction=Open this file manually:
brazilianportuguese.InstallationReportOpenAction=Abra este arquivo manualmente:
english.SharedDataSetupFailed=The shared application data folder could not be configured.
brazilianportuguese.SharedDataSetupFailed=Não foi possível configurar a pasta de dados compartilhados do aplicativo.
english.SharedDataRepairAction=Ask an administrator to check the PlugAgente folder in ProgramData and grant your Windows account read and write access.
brazilianportuguese.SharedDataRepairAction=Solicite ao administrador que verifique a pasta PlugAgente em ProgramData e conceda leitura e gravação à sua conta do Windows.
english.AutostartSetupFailed=Start with Windows could not be configured for the logged-on user.
brazilianportuguese.AutostartSetupFailed=Não foi possível configurar a inicialização com o Windows para o usuário conectado.
english.AutostartRepairAction=Open the agent manually, enable Start with Windows in Settings and check whether Windows Startup Apps has disabled it.
brazilianportuguese.AutostartRepairAction=Abra o agente manualmente, habilite Iniciar com o Windows nas Configurações e verifique se Aplicativos de inicialização do Windows desabilitou esse recurso.
english.InstallationMetadataFailed=Some installation settings could not be saved.
brazilianportuguese.InstallationMetadataFailed=Não foi possível salvar algumas configurações da instalação.
english.InstallationMetadataRepairAction=Check write access to install-mode.ini in the application folder and run the installer again to repair the settings.
brazilianportuguese.InstallationMetadataRepairAction=Verifique o acesso de gravação a install-mode.ini na pasta do aplicativo e execute o instalador novamente para reparar as configurações.
english.InstallationIssueCode=Issue code:
brazilianportuguese.InstallationIssueCode=Código do problema:
english.InstallationSeverity=Severity:
brazilianportuguese.InstallationSeverity=Gravidade:
english.InstallationCritical=Critical
brazilianportuguese.InstallationCritical=Grave
english.InstallationRecoverable=Recoverable warning
brazilianportuguese.InstallationRecoverable=Aviso recuperável
english.InstallationResource=Affected resource:
brazilianportuguese.InstallationResource=Recurso afetado:
english.InstallationImpact=Impact:
brazilianportuguese.InstallationImpact=Impacto:
english.CoreCheckFailed=Critical error: the installed agent or its native runtime could not start.
brazilianportuguese.CoreCheckFailed=Erro grave: o agente instalado ou seu runtime nativo não conseguiu iniciar.
english.CoreRepairAction=Check the detailed error, disk space, antivirus quarantine and application folder access. Run the full installer to restore the application files.
brazilianportuguese.CoreRepairAction=Verifique o erro detalhado, o espaço em disco, a quarentena do antivírus e o acesso à pasta do aplicativo. Execute a instalação completa para restaurar os arquivos.
english.OdbcCheckFailed=The 64-bit ODBC driver manager or driver list is unavailable. Database connections may not work.
brazilianportuguese.OdbcCheckFailed=O gerenciador ou a lista de drivers ODBC de 64 bits está indisponível. As conexões com o banco podem não funcionar.
english.OdbcRepairAction=Install the 64-bit ODBC driver for your database, configure the agent connection and test it in the application. Driver presence alone does not validate a database connection.
brazilianportuguese.OdbcRepairAction=Instale o driver ODBC de 64 bits do seu banco, configure a conexão no agente e teste no aplicativo. A presença do driver não valida a conexão com o banco.
english.OptionalRepairDescription=You can repeat the optional configuration and diagnostics without copying the application again.
brazilianportuguese.OptionalRepairDescription=Você pode repetir a configuração opcional e os diagnósticos sem copiar novamente o aplicativo.
english.OptionalRepairTaskInstructions=Run the command above with this same installer. Select only the features you want to repair. Automatic updates still require explicit authorization.
brazilianportuguese.OptionalRepairTaskInstructions=Execute o comando acima com este mesmo instalador. Selecione apenas os recursos que deseja reparar. As atualizações automáticas continuam exigindo autorização explícita.
english.OptionalRepairInvalid=Optional repair requires the same application build, channel, installation folder and privilege mode. Use the full installer to restore missing or incompatible application files.
brazilianportuguese.OptionalRepairInvalid=O reparo opcional exige a mesma compilação do aplicativo, canal, pasta de instalação e modo de privilégios. Use a instalação completa para restaurar arquivos ausentes ou incompatíveis.
english.OptionalRepairCompleted=Optional repair and diagnostics completed.
brazilianportuguese.OptionalRepairCompleted=Reparo opcional e diagnósticos concluídos.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:StartWithWindows}"; GroupDescription: "{cm:StartupOptionsGroup}"
Name: "autoupdate"; Description: "{cm:AutomaticUpdate}"; GroupDescription: "{cm:UpdateOptionsGroup}"; Check: IsAdminInstallMode

#ifndef COMPILE_SCRIPT_ONLY
#if !FileExists("..\build\windows\x64\runner\Release\msvcp140.dll") || !FileExists("..\build\windows\x64\runner\Release\vcruntime140.dll") || !FileExists("..\build\windows\x64\runner\Release\vcruntime140_1.dll")
  #error Rebuild Windows before packaging: the application bundle requires Visual C++ runtime DLLs
#endif
#if !FileExists("..\build\windows\x64\runner\Release\plug_install_check.exe")
  #error Rebuild Windows before packaging: the installation diagnostic executable is missing
#endif
[Files]
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion; Check: ShouldCopyApplicationFiles
Source: "..\assets\fonts\montserrat\OFL.txt"; DestDir: "{app}\licenses"; DestName: "Montserrat-OFL.txt"; Flags: ignoreversion; Check: ShouldCopyApplicationFiles
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib,*.log,updater,updater\*"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: ShouldCopyApplicationFiles
Source: "..\build\windows\x64\runner\Release\updater\plug_update_client.exe"; Flags: dontcopy
Source: "..\build\windows\x64\runner\Release\updater\plug_update_service.exe"; DestDir: "{commonpf}\PlugAgenteUpdater"; Flags: ignoreversion; Check: ShouldInstallUpdaterHost
Source: "..\build\windows\x64\runner\Release\updater\plug_update_client.exe"; DestDir: "{commonpf}\PlugAgenteUpdater"; Flags: ignoreversion; Check: ShouldInstallUpdaterHost
Source: "..\build\windows\x64\runner\Release\updater\plug_update_worker.exe"; DestDir: "{commonpf}\PlugAgenteUpdater\workers\{#MyAppWorkerVersion}"; Flags: ignoreversion; Check: ShouldInstallUpdaterWorker
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Check: ShouldCopyApplicationFiles
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"; Check: ShouldCopyApplicationFiles
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; Check: ShouldCopyApplicationFiles

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent runasoriginaluser; Check: ShouldCopyApplicationFiles
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent runasoriginaluser; Check: ShouldLaunchAfterSilentUpdate

[Registry]
Root: HKA; Subkey: "Software\Classes\plugdb"; ValueType: string; ValueName: ""; ValueData: "URL:Plug Agente Protocol"; Flags: uninsdeletekey; Check: ShouldCopyApplicationFiles
Root: HKA; Subkey: "Software\Classes\plugdb"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Check: ShouldCopyApplicationFiles
Root: HKA; Subkey: "Software\Classes\plugdb\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"; Check: ShouldCopyApplicationFiles
Root: HKA; Subkey: "Software\Classes\plugdb\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Check: ShouldCopyApplicationFiles

; [UninstallRun] on Inno 6.6.1 does not accept runasoriginaluser.
; cmd swallows "value not found" so a missing Run key does not fail uninstall.
[UninstallRun]
Filename: "{cmd}"; Parameters: "/c reg delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""{#MyAppName}"" /f >nul 2>&1"; Flags: runhidden; RunOnceId: "RemoveAutostart"

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\PlugAgente\updates"
Type: files; Name: "{commonappdata}\PlugAgente\{#AutostartRequestMarker}"
Type: files; Name: "{app}\installation-warnings-*.log"
Type: dirifempty; Name: "{commonappdata}\PlugAgente"

[Code]
var
  UpdaterHostNeeded: Boolean;
  UpdaterInstallationSkipped: Boolean;
  UpdaterWasPresent: Boolean;

#include "installation_reporting.iss"
#include "installation_repair.iss"

function RunDependencyCommand(const Filename, Parameters: String; var Details: String): Boolean;
var
  Output: TExecOutput;
  ResultCode, Index: Integer;
begin
  Result := False;
  ResultCode := -1;
  Details := '';
  try
    Result := ExecAndCaptureOutput(Filename, Parameters, '', SW_SHOWNORMAL,
      ewWaitUntilTerminated, ResultCode, Output) and (ResultCode = 0);
    Details := 'Exit code: ' + IntToStr(ResultCode);
    for Index := 0 to GetArrayLength(Output.StdOut) - 1 do
      Details := Details + #13#10 + Output.StdOut[Index];
    for Index := 0 to GetArrayLength(Output.StdErr) - 1 do
      Details := Details + #13#10 + Output.StdErr[Index];
    if Output.Error then
      Details := Details + #13#10 + 'Command output could not be captured completely.';
  except
    Result := False;
    Details := GetExceptionMessage;
  end;
  Log(Filename + ' ' + Parameters + ': ' + Details);
end;

#include "installation_checks.iss"

function StoreUpdaterAuthorization(const Authorized: Cardinal): Boolean;
begin
  Result := RegWriteDWordValue(HKLM64, 'Software\Se7e Sistemas\PlugAgenteUpdater', 'Authorized', Authorized);
end;

#include "updater_recovery.iss"

function UpdaterExists(): Boolean;
begin
  // Failed first enrollment must not pin an incomplete updater host on the next repair.
  Result := FileExists(ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_service.exe')) and
    FileExists(ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_client.exe')) and
    FileExists(ExpandConstant('{commonappdata}\PlugAgenteUpdater\policy.json'));
end;

function WantsAutomaticUpdates(): Boolean;
var
  Authorized: Cardinal;
begin
  Result := False;
  if UpdaterInstallationSkipped or not IsAdminInstallMode then
    Exit;
  if IsOptionalRepair() and not WantsAutomaticUpdates() then
    Exit;
  if WizardSilent() then
  begin
    if IsOptionalRepair() and (ExpandConstant('{param:AUTOUPDATE|0}') = '1') then
    begin
      Result := True;
      Exit;
    end;
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
  Details: String;
begin
  if UpdaterInstallationSkipped or not IsAdminInstallMode then
    Exit;
  ClientPath := ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_client.exe');
  if WantsAutomaticUpdates() then
  begin
    // The supervisor survives routine bundle/worker updates. Enrollment is an
    // administrative transition, never an implicit action of a silent upgrade.
    if UpdaterHostNeeded or not WizardSilent() or IsOptionalRepair() then
    begin
      if not RunDependencyCommand(ClientPath, '--enroll ' + AddQuotes(ExpandConstant('{app}')) + ' ' +
          AddQuotes(ExpandConstant('{srcexe}')) + ' ' + ExpandConstant('{param:CHANNEL|{#MyAppChannel}}') + ' {#MyAppWorkerVersion}',
          Details) then
      begin
        RecoverUpdaterEnrollmentFailure(ClientPath, Details);
        Exit;
      end;
      if not StoreUpdaterAuthorization(1) then
        RecoverUpdaterEnrollmentFailure(ClientPath, 'Could not save Authorized=1 in the updater registry key.');
    end;
  end
  else if not WizardSilent() and FileExists(ClientPath) then
  begin
    if not RunDependencyCommand(ClientPath, '--revoke', Details) then
      RecordInstallationIssue(ifUpdaterSafety, 'updater_revocation_failed', 'PlugAgenteUpdater',
        CustomMessage('UpdaterDisableCritical'), CustomMessage('UpdaterAuthorizationRepairAction'), Details);
    if not StoreUpdaterAuthorization(0) then
      RecordInstallationIssue(ifOptionalFeature, 'updater_authorization_write_failed', 'HKLM64\Software\Se7e Sistemas\PlugAgenteUpdater', CustomMessage('UpdaterAuthorizationSaveFailed'),
        CustomMessage('UpdaterAuthorizationRepairAction'), 'Authorized=0');
  end;
end;

function InitializeSetup(): Boolean;
var
  ClientPath: String;
  Details: String;
begin
  Result := True;
  if (ExpandConstant('{param:REPAIR|}') <> '') and not IsOptionalRepair() then
  begin
    RegisterCriticalInstallationError(CustomMessage('OptionalRepairInvalid'));
    Result := False;
    Exit;
  end;
  ClientPath := ExpandConstant('{commonpf}\PlugAgenteUpdater\plug_update_client.exe');
  UpdaterWasPresent := UpdaterExists() or FileExists(ClientPath) or
    FileExists(ExpandConstant('{commonappdata}\PlugAgenteUpdater\policy.json'));
  if UpdaterWasPresent or (ExpandConstant('{param:UPDATERSERVICE|0}') = '1') then
    Result := RunDependencyCommand(ClientPath, '--check-install ' + ExpandConstant('{param:UPDATERSERVICE|0}'), Details);
  if not Result then
  begin
    RegisterCriticalInstallationError(CustomMessage('UpdaterOperationCritical') + #13#10 + Details);
    SuppressibleMsgBox(CustomMessage('UpdaterOperationCritical') + #13#10 + Details,
      mbCriticalError, MB_OK, IDOK);
  end;
end;

procedure DeinitializeSetup;
begin
  OpenCriticalInstallationLog;
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
  DataDir, Details: String;
begin
  DataDir := ExpandConstant('{commonappdata}\PlugAgente');
  try
    if not DirExists(DataDir) and not ForceDirectories(DataDir) then
    begin
      RecordInstallationIssue(ifDataAccess, 'data_directory_create_failed', DataDir, CustomMessage('SharedDataSetupFailed'),
        CustomMessage('SharedDataRepairAction'), 'Could not create ' + DataDir);
      Exit;
    end;
    if not RunDependencyCommand(ExpandConstant('{sys}\icacls.exe'),
      AddQuotes(DataDir) + ' /grant *S-1-5-11:(OI)(CI)(M) /grant *S-1-5-32-545:(OI)(CI)(M)', Details) then
      RecordInstallationIssue(ifDataAccess, 'data_permissions_failed', DataDir, CustomMessage('SharedDataSetupFailed'),
        CustomMessage('SharedDataRepairAction'), Details);
  except
    RecordInstallationIssue(ifDataAccess, 'data_configuration_failed', DataDir, CustomMessage('SharedDataSetupFailed'),
      CustomMessage('SharedDataRepairAction'), GetExceptionMessage);
  end;
end;

procedure WriteAutostartRequestMarker;
var
  MarkerPath: String;
begin
  MarkerPath := ExpandConstant('{commonappdata}\PlugAgente\{#AutostartRequestMarker}');
  try
    if not SaveStringToFile(MarkerPath, '1', False) then
      RecordInstallationIssue(ifOptionalFeature, 'autostart_marker_failed', MarkerPath, CustomMessage('AutostartSetupFailed'),
        CustomMessage('AutostartRepairAction'), 'Could not write ' + MarkerPath);
  except
    RecordInstallationIssue(ifOptionalFeature, 'autostart_marker_failed', MarkerPath, CustomMessage('AutostartSetupFailed'),
      CustomMessage('AutostartRepairAction'), GetExceptionMessage);
  end;
end;

procedure ConfigureLoggedOnUserAutostart;
var
  ResultCode: Integer;
begin
  if not WizardIsTaskSelected('startup') then
    Exit;
  WriteAutostartRequestMarker;
  // Use the initial user's token; elevated HKCU may belong to another administrator.
  try
    ResultCode := -1;
    if not ExecAsOriginalUser(ExpandConstant('{sys}\reg.exe'),
      GetLoggedOnUserAutostartRegParams(''), '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or
      (ResultCode <> 0) then
      RecordInstallationIssue(ifOptionalFeature, 'autostart_registration_failed', 'HKCU\{#RunKeyPath}', CustomMessage('AutostartSetupFailed'),
        CustomMessage('AutostartRepairAction'), 'reg.exe exit/error code: ' + IntToStr(ResultCode));
  except
    RecordInstallationIssue(ifOptionalFeature, 'autostart_registration_failed', 'HKCU\{#RunKeyPath}', CustomMessage('AutostartSetupFailed'),
      CustomMessage('AutostartRepairAction'), GetExceptionMessage);
  end;
end;

procedure WriteInstallationSetting(const KeyName, Value: String);
begin
  try
    if not SetIniString('installation', KeyName, Value, ExpandConstant('{app}\install-mode.ini')) then
      RecordInstallationIssue(ifOptionalFeature, 'installation_metadata_failed', ExpandConstant('{app}\install-mode.ini'), CustomMessage('InstallationMetadataFailed'),
        CustomMessage('InstallationMetadataRepairAction'), 'Could not save ' + KeyName);
  except
    RecordInstallationIssue(ifOptionalFeature, 'installation_metadata_failed', ExpandConstant('{app}\install-mode.ini'), CustomMessage('InstallationMetadataFailed'),
      CustomMessage('InstallationMetadataRepairAction'), KeyName + ': ' + GetExceptionMessage);
  end;
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
    VerifyInstalledCore;
    ConfigureUpdaterAuthorization;
    ConfigureSharedProgramDataPermissions;
    if IsAdminInstallMode then
      WriteInstallationSetting('mode', 'global')
    else
      WriteInstallationSetting('mode', 'user');
    WriteInstallationSetting('directory', ExpandConstant('{app}'));
    WriteInstallationSetting('channel', ExpandConstant('{param:CHANNEL|{#MyAppChannel}}'));
    WriteInstallationSetting('workerVersion', '{#MyAppWorkerVersion}');
    // Silent updates pass /MERGETASKS="!startup", so this does not re-request
    // auto-start. The app then writes HKCU for the interactive user.
    ConfigureLoggedOnUserAutostart;
    VerifyInstalledDataAccess;
    AppendOptionalRepairInstructions;
    PersistInstallationWarnings(ExpandConstant('{app}\installation-warnings-') +
      GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '.log', ExpandConstant('{log}') + '.warnings.log');
  end
  else if CurStep = ssDone then
  begin
    CriticalInstallationError := False;
    OpenInstallationWarningReport;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and HasInstallationWarnings() then
    WizardForm.FinishedLabel.Caption := CustomMessage('InstallationWarningsCompleted') + #13#10 + InstallationReportPath
  else if (CurPageID = wpFinished) and IsOptionalRepair() then
    WizardForm.FinishedLabel.Caption := CustomMessage('OptionalRepairCompleted');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Details, SettingsPath: String;
  Prepared: Boolean;
begin
  Result := '';
  NeedsRestart := False;
  CriticalInstallationError := False;
  if IsOptionalRepair() then
  begin
    SettingsPath := ExpandConstant('{app}\install-mode.ini');
    if not ValidateOptionalRepair(GetIniString('installation', 'workerVersion', '', SettingsPath),
      GetIniString('installation', 'mode', '', SettingsPath),
      GetIniString('installation', 'channel', '', SettingsPath), IsAdminInstallMode,
      ExpandConstant('{param:UPDATERSERVICE|0}') = '1') then
    begin
      Result := CustomMessage('OptionalRepairInvalid');
      RegisterCriticalInstallationError(Result);
      Exit;
    end;
    VerifyInstalledCore;
  end;
  UpdaterHostNeeded := WantsAutomaticUpdates() and not UpdaterExists();
  if WantsAutomaticUpdates() then
  begin
    // Execute the installer-embedded client before copying privileged files:
    // existing user-owned/reparse directories must fail ACL validation.
    Prepared := False;
    try
      ExtractTemporaryFile('plug_update_client.exe');
      Prepared := RunDependencyCommand(ExpandConstant('{tmp}\plug_update_client.exe'),
        '--prepare-control {#MyAppWorkerVersion}', Details);
    except
      Details := GetExceptionMessage;
      Log('Updater preparation failed: ' + Details);
    end;
    if not Prepared then
    begin
      if CanSkipUpdaterPreparation(UpdaterWasPresent, ExpandConstant('{param:UPDATERSERVICE|0}') = '1') then
        SkipUpdaterInstallation(Details)
      else
      begin
        Result := CustomMessage('UpdaterPreparationCritical') + #13#10 + Details;
        RegisterCriticalInstallationError(Result);
      end;
    end;
  end;
end;
