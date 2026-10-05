procedure VerifyInstalledCore;
var
  Details: String;
begin
  if not RunDependencyCommand(ExpandConstant('{app}\plug_install_check.exe'), '--core', Details) then
    RecordInstallationIssue(ifCoreRuntime, 'core_check_failed', ExpandConstant('{app}'),
      CustomMessage('CoreCheckFailed'), CustomMessage('CoreRepairAction'), Details);
end;

procedure VerifyInstalledDataAccess;
var
  Details: String;
  ResultCode: Integer;
  Accessible: Boolean;
begin
  if not RunDependencyCommand(ExpandConstant('{app}\plug_install_check.exe'), '--odbc', Details) then
    RecordInstallationIssue(ifDataAccess, 'odbc_check_failed', 'ODBC x64',
      CustomMessage('OdbcCheckFailed'), CustomMessage('OdbcRepairAction'), Details);
  ResultCode := -1;
  Accessible := False;
  try
    Accessible := ExecAsOriginalUser(ExpandConstant('{app}\plug_install_check.exe'),
      '--data ' + AddQuotes(ExpandConstant('{commonappdata}\PlugAgente')), '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  except
    Log('Original-user data check failed: ' + GetExceptionMessage);
  end;
  if not Accessible then
    RecordInstallationIssue(ifDataAccess, 'user_data_access_failed',
      ExpandConstant('{commonappdata}\PlugAgente'), CustomMessage('SharedDataSetupFailed'),
      CustomMessage('SharedDataRepairAction'), 'Original-user check exit/error code: ' + IntToStr(ResultCode));
end;
