@echo off
REM Teste de conexao SQL Anywhere via CMD (dbping)
REM
REM Uso:
REM   tool\test_db_cmd.bat           [porta default 2650]
REM   tool\test_db_cmd.bat 2638     [porta como argumento]
REM
REM Para customizar: edite as variaveis abaixo antes de executar.
REM   HOST  - hostname ou IP do servidor (default: LOCALHOST)
REM   PORT  - porta do servidor (default: 2650, ou 1o argumento)
REM   DBN   - nome do banco (default: VL)
REM   UID   - usuario (default: dba)
REM   PWD   - senha (default: sql)

setlocal
set PORT=%1
if "%PORT%"=="" set PORT=2650

set HOST=LOCALHOST
set DBN=VL
set UID=dba
set PWD=sql

echo Testando conexao SQL Anywhere...
echo Host: %HOST%  Porta: %PORT%  Banco: %DBN%  Usuario: %UID%
echo.

REM Caminhos comuns do SQL Anywhere 16
set "DBPING="
if exist "C:\Program Files\SQL Anywhere 16\Bin64\dbping.exe" set "DBPING=C:\Program Files\SQL Anywhere 16\Bin64\dbping.exe"
if exist "C:\Program Files (x86)\SQL Anywhere 16\Bin64\dbping.exe" set "DBPING=C:\Program Files (x86)\SQL Anywhere 16\Bin64\dbping.exe"
if exist "C:\Program Files\SAP\SQL Anywhere 16\Bin64\dbping.exe" set "DBPING=C:\Program Files\SAP\SQL Anywhere 16\Bin64\dbping.exe"

if "%DBPING%"=="" (
    echo ERRO: dbping.exe nao encontrado.
    echo Instale o SQL Anywhere 16 ou ajuste o caminho no script.
    echo Caminhos verificados:
    echo   - C:\Program Files\SQL Anywhere 16\Bin64\
    echo   - C:\Program Files (x86)\SQL Anywhere 16\Bin64\
    echo   - C:\Program Files\SAP\SQL Anywhere 16\Bin64\
    exit /b 1
)

echo Executando dbping -c "Host=%HOST%:%PORT%;DBN=%DBN%;UID=%UID%;PWD=***"
echo.

REM -c = connection string (Host=host:port para SQL Anywhere)
call "%DBPING%" -c "Host=%HOST%:%PORT%;DBN=%DBN%;UID=%UID%;PWD=%PWD%"

if %ERRORLEVEL% equ 0 (
    echo.
    echo SUCESSO: Conexao estabelecida.
) else (
    echo.
    echo ERRO: Falha na conexao. Codigo: %ERRORLEVEL%
    echo Verifique: servidor rodando, host, porta, firewall.
)

endlocal
exit /b %ERRORLEVEL%
