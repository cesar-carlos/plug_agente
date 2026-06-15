@echo off
REM Executa SELECT 1 no banco SQL Anywhere via CMD (dbisql)
REM
REM Uso:
REM   tool\test_select1_cmd.bat     [porta default 2650]
REM   tool\test_select1_cmd.bat 2638
REM
REM Para customizar: edite as variaveis abaixo.
REM   HOST, PORT, DBN, UID, PWD - mesmos do test_db_cmd.bat

setlocal
set PORT=%1
if "%PORT%"=="" set PORT=2650

set HOST=LOCALHOST
set DBN=VL
set UID=dba
set PWD=sql

set SCRIPT_DIR=%~dp0
set SQL_FILE=%SCRIPT_DIR%select1.sql

echo Executando SELECT 1 no SQL Anywhere...
echo Host: %HOST%  Porta: %PORT%  Banco: %DBN%  Usuario: %UID%
echo.

REM Caminhos comuns do SQL Anywhere 16
set "DBISQL="
if exist "C:\Program Files\SQL Anywhere 16\Bin64\dbisql.exe" set "DBISQL=C:\Program Files\SQL Anywhere 16\Bin64\dbisql.exe"
if exist "C:\Program Files (x86)\SQL Anywhere 16\Bin64\dbisql.exe" set "DBISQL=C:\Program Files (x86)\SQL Anywhere 16\Bin64\dbisql.exe"
if exist "C:\Program Files\SAP\SQL Anywhere 16\Bin64\dbisql.exe" set "DBISQL=C:\Program Files\SAP\SQL Anywhere 16\Bin64\dbisql.exe"

if "%DBISQL%"=="" (
    echo ERRO: dbisql.exe nao encontrado.
    echo Instale o SQL Anywhere 16 ou ajuste o caminho no script.
    exit /b 1
)

echo Executando: dbisql -c "Host=%HOST%:%PORT%;DBN=%DBN%;UID=%UID%;PWD=***" -nogui "%SQL_FILE%"
echo.

call "%DBISQL%" -c "Host=%HOST%:%PORT%;DBN=%DBN%;UID=%UID%;PWD=%PWD%" -nogui "%SQL_FILE%"

if %ERRORLEVEL% equ 0 (
    echo.
    echo SUCESSO: SELECT 1 executado com sucesso.
) else (
    echo.
    echo ERRO: Falha ao executar. Codigo: %ERRORLEVEL%
)

endlocal
exit /b %ERRORLEVEL%
