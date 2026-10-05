type
  TInstallationFailureKind = (ifOptionalFeature, ifDataAccess, ifCoreRuntime, ifUpdaterSafety);

function IsCriticalInstallationFailure(const Kind: TInstallationFailureKind): Boolean;
begin
  Result := (Kind = ifCoreRuntime) or (Kind = ifUpdaterSafety);
end;

var
  InstallationWarnings: TArrayOfString;
  InstallationReportPath: String;
  InstallationRepairInstructions: String;
  CriticalInstallationError: Boolean;

procedure RegisterCriticalInstallationError(const MessageText: String);
begin
  CriticalInstallationError := True;
  Log('Critical installation error: ' + MessageText);
  Log(CustomMessage('InstallationFullLog') + ' ' + ExpandConstant('{log}'));
end;

function HasInstallationWarnings(): Boolean;
begin
  Result := GetArrayLength(InstallationWarnings) > 0;
end;

procedure RecordInstallationIssue(const Kind: TInstallationFailureKind;
  const Code, Resource, MessageText, RequiredAction, Details: String);
var
  Index: Integer;
  Entry, Severity: String;
begin
  if IsCriticalInstallationFailure(Kind) then
    Severity := CustomMessage('InstallationCritical')
  else
    Severity := CustomMessage('InstallationRecoverable');
  Entry := CustomMessage('InstallationIssueCode') + ' ' + Code + #13#10 +
    CustomMessage('InstallationSeverity') + ' ' + Severity + #13#10 +
    CustomMessage('InstallationResource') + ' ' + Resource + #13#10 +
    CustomMessage('InstallationImpact') + ' ' + MessageText + #13#10 +
    CustomMessage('InstallationRequiredAction') + ' ' + RequiredAction;
  if Details <> '' then
    Entry := Entry + #13#10 + CustomMessage('InstallationTechnicalDetails') + ' ' + Details;
  if IsCriticalInstallationFailure(Kind) then
  begin
    RegisterCriticalInstallationError(Entry);
    RaiseException(Entry);
  end;
  Index := GetArrayLength(InstallationWarnings);
  SetArrayLength(InstallationWarnings, Index + 1);
  InstallationWarnings[Index] := Entry;
  Log('Installation warning: ' + InstallationWarnings[Index]);
end;

procedure RecordInstallationWarning(const MessageText, RequiredAction, Details: String);
begin
  RecordInstallationIssue(ifOptionalFeature, 'optional_configuration', '{#MyAppName}',
    MessageText, RequiredAction, Details);
end;

function WriteInstallationWarningReport(const FilePath: String): Boolean;
var
  Lines: TArrayOfString;
  Index: Integer;
begin
  Result := False;
  if not HasInstallationWarnings() then
    Exit;
  SetArrayLength(Lines, GetArrayLength(InstallationWarnings) + 6);
  Lines[0] := CustomMessage('InstallationReportTitle');
  Lines[1] := '{#MyAppName} {#MyAppVersion} - ' + GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':') + #13#10 +
    'Windows: ' + GetWindowsVersionString();
  Lines[2] := CustomMessage('InstallationWarningsSummary');
  Lines[3] := CustomMessage('InstallationFullLog') + ' ' + ExpandConstant('{log}');
  Lines[4] := '';
  for Index := 0 to GetArrayLength(InstallationWarnings) - 1 do
    Lines[Index + 5] := IntToStr(Index + 1) + '. ' + InstallationWarnings[Index] + #13#10;
  Lines[GetArrayLength(Lines) - 1] := CustomMessage('InstallationReportFooter');
  if InstallationRepairInstructions <> '' then
    Lines[GetArrayLength(Lines) - 1] := Lines[GetArrayLength(Lines) - 1] + #13#10 + #13#10 +
      InstallationRepairInstructions;
  try
    Result := SaveStringsToUTF8File(FilePath, Lines, False);
  except
    Log('Could not write installation warning report: ' + GetExceptionMessage);
  end;
  if Result then
  begin
    InstallationReportPath := FilePath;
    Log('Installation warning report saved: ' + FilePath);
  end;
end;

procedure OpenCriticalInstallationLog;
var
  ResultCode: Integer;
begin
  if not CriticalInstallationError or WizardSilent() then
    Exit;
  try
    if not ExecAsOriginalUser(ExpandConstant('{sys}\notepad.exe'),
      AddQuotes(ExpandConstant('{log}')), '', SW_SHOWNORMAL, ewNoWait, ResultCode) then
      Log('Could not open the critical installation log. Error code: ' + IntToStr(ResultCode));
  except
    Log('Could not open the critical installation log: ' + GetExceptionMessage);
  end;
end;

procedure PersistInstallationWarnings(const PreferredPath, BackupPath: String);
begin
  if not HasInstallationWarnings() then
    Exit;
  if WriteInstallationWarningReport(PreferredPath) then
    Exit;
  RecordInstallationIssue(ifOptionalFeature, 'report_storage_failed', PreferredPath, CustomMessage('InstallationReportSaveFailed'),
    CustomMessage('InstallationReportSaveAction'), PreferredPath);
  if WriteInstallationWarningReport(BackupPath) then
    Exit;
  InstallationReportPath := ExpandConstant('{log}');
  Log('Warning report could not be saved. Required actions remain in the Setup log.');
end;

function ShouldOpenInstallationReport(const SilentInstall: Boolean): Boolean;
begin
  Result := HasInstallationWarnings() and (InstallationReportPath <> '') and not SilentInstall;
end;

procedure OpenInstallationWarningReport;
var
  ResultCode: Integer;
  Opened: Boolean;
begin
  if not ShouldOpenInstallationReport(WizardSilent()) then
    Exit;
  Opened := False;
  try
    Opened := ExecAsOriginalUser(ExpandConstant('{sys}\notepad.exe'),
      AddQuotes(InstallationReportPath), '', SW_SHOWNORMAL, ewNoWait, ResultCode);
  except
    Log('Could not open installation warning report: ' + GetExceptionMessage);
  end;
  if not Opened then
  begin
    RecordInstallationIssue(ifOptionalFeature, 'report_viewer_failed', InstallationReportPath, CustomMessage('InstallationReportOpenFailed'),
      CustomMessage('InstallationReportOpenAction') + ' ' + InstallationReportPath, '');
    if InstallationReportPath <> ExpandConstant('{log}') then
      WriteInstallationWarningReport(InstallationReportPath);
    SuppressibleMsgBox(CustomMessage('InstallationReportOpenFailed') + #13#10 +
      CustomMessage('InstallationReportOpenAction') + ' ' + InstallationReportPath,
      mbInformation, MB_OK, IDOK);
  end;
end;
