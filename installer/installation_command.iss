type
  TInstallationSecurity = record
    Size, Descriptor, Inherit: Cardinal;
  end;
  TInstallationStartup = record
    Size, Reserved, Desktop, Title: Cardinal;
    X, Y, XSize, YSize, XChars, YChars, Fill, Flags: Cardinal;
    Show, ReservedSize: Word;
    ReservedBytes: Cardinal;
    Input, Output, Error: THandle;
  end;
  TInstallationProcess = record
    Process, Thread: THandle;
    ProcessId, ThreadId: Cardinal;
  end;

var
  InstallationCommandSequence: Integer;

function InstallationCreateFile(Name: String; Access, Sharing: Cardinal;
  var Security: TInstallationSecurity; Creation, Flags: Cardinal; Template: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';
function InstallationCreateProcess(Application, Command: String; ProcessSecurity,
  ThreadSecurity: Integer; Inherit: Boolean; Flags: Cardinal; Environment: Integer;
  Directory: String; var Startup: TInstallationStartup; var Process: TInstallationProcess): Boolean;
  external 'CreateProcessW@kernel32.dll stdcall';
function InstallationWait(Process: THandle; Timeout: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function InstallationExitCode(Process: THandle; var Code: Cardinal): Boolean;
  external 'GetExitCodeProcess@kernel32.dll stdcall';
function InstallationTerminate(Process: THandle; Code: Cardinal): Boolean;
  external 'TerminateProcess@kernel32.dll stdcall';
function InstallationClose(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function InstallationCommandTick: Cardinal;
  external 'GetTickCount@kernel32.dll stdcall';

function RunInstallationCommand(const Filename, Parameters: String;
  Budget: Cardinal; var Details: String): Boolean;
var
  Security: TInstallationSecurity;
  Startup: TInstallationStartup;
  Process: TInstallationProcess;
  Output, Input: THandle;
  OutputPath: String;
  Captured: AnsiString;
  WaitResult, Code, Started, Elapsed: Cardinal;
begin
  Result := False;
  Details := 'installation_command_unknown';
  if Budget = 0 then Exit;
  Started := InstallationCommandTick;
  Security.Size := SizeOf(Security);
  Security.Inherit := 1;
  InstallationCommandSequence := InstallationCommandSequence + 1;
  OutputPath := ExpandConstant('{tmp}\installation-command-') + IntToStr(InstallationCommandSequence) + '.log';
  Output := InstallationCreateFile(OutputPath, $40000000, 1, Security, 1, $100, 0);
  if Output = THandle(-1) then Exit;
  try
    Input := InstallationCreateFile('NUL', $80000000, 3, Security, 3, 0, 0);
    if Input = THandle(-1) then Exit;
    try
      Startup.Size := SizeOf(Startup);
      Startup.Flags := $100;
      Startup.Input := Input;
      Startup.Output := Output;
      Startup.Error := Output;
      if not InstallationCreateProcess(Filename, AddQuotes(Filename) + ' ' + Parameters,
        0, 0, True, $08000000, 0, ExtractFileDir(Filename), Startup, Process) then Exit;
      InstallationClose(Process.Thread);
      try
        Elapsed := InstallationCommandTick - Started;
        WaitResult := 258;
        if Elapsed < Budget then
          WaitResult := InstallationWait(Process.Process, Budget - Elapsed);
        if WaitResult <> 0 then
        begin
          // Stop only our command client, never the application or its descendants.
          // The request may already have effects; termination is not cancellation.
          Details := 'installation_command_timeout_unknown';
          if not InstallationTerminate(Process.Process, 124) or
            (InstallationWait(Process.Process, 1000) <> 0) then
            Details := 'installation_command_cleanup_unknown';
          Exit;
        end;
        if not InstallationExitCode(Process.Process, Code) then Exit;
        Result := Code = 0;
      finally
        InstallationClose(Process.Process);
      end;
    finally
      InstallationClose(Input);
    end;
  finally
    InstallationClose(Output);
  end;
  if LoadStringFromFile(OutputPath, Captured) then
    Details := 'Exit code: ' + IntToStr(Code) + #13#10 + String(Captured)
  else
  begin
    Result := False;
    Details := 'installation_command_output_unknown';
  end;
  DeleteFile(OutputPath);
end;
