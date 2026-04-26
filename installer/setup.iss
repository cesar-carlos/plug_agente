; Plug Agente - Inno Setup Script
; Version is updated by installer/update_version.py
; Uses #$XXXX for Unicode chars to avoid encoding issues on build machines

#include "constants.iss"
#define MyAppName "Plug Agente"
#define MyAppVersion "1.2.6"
#define MyAppPublisher "com.se7esistemas"
#define MyAppURL "https://github.com/cesar-carlos/plug_agente"
#define MyAppExeName "plug_agente.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=PlugAgente-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
MinVersion=10.0
CloseApplications=yes
CloseApplicationsFilter=plug_agente.exe
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "Opções de Inicialização"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib,*.log"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: "{code:GetAutostartValue}"; Flags: uninsdeletevalue; Tasks: startup

[UninstallDelete]
Type: dirifempty; Name: "{commonappdata}\PlugAgente"

[Code]
function GetAutostartValue(Param: String): String;
begin
  Result := AddQuotes(ExpandConstant('{app}\{#MyAppExeName}')) + '{#AutostartArg}';
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

function InitializeSetup(): Boolean;
begin
  Result := True;

  if not IsVCRedistInstalled() then
  begin
    if WizardSilent() then
    begin
      Log('Microsoft Visual C++ Redistributable x64 was not detected. Continuing because setup is running silently.');
    end
    else
    begin
      if MsgBox('Microsoft Visual C++ Redistributable x64 n' + Chr(227) + 'o foi detectado.' + #13#10 + #13#10 +
        'Instale-o antes de usar o ' + ExpandConstant('{#MyAppName}') + ':' + #13#10 +
        'https://aka.ms/vs/17/release/vc_redist.x64.exe' + #13#10 + #13#10 +
        'Deseja continuar a instala' + Chr(231) + Chr(227) + 'o mesmo assim?', mbConfirmation, MB_YESNO) = IDNO then
        Result := False;
    end;
  end;
end;
