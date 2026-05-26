# SQL Server Connection

## Connection string format

ODBC para SQL Server espera `Server=`, `Port=` e `Database=` separados.

### Format

```text
DRIVER={ODBC Driver 17 for SQL Server};Server=host;Port=1433;Database=name;UID=user;PWD=password
```

### Parameters

| Parameter | Description |
| --------- | ----------- |
| DRIVER | ODBC driver name (ex.: `ODBC Driver 17 for SQL Server`, `ODBC Driver 18 for SQL Server`) |
| Server | Hostname ou IP do servidor SQL Server |
| Port | Porta TCP do listener (default `1433`) |
| Database | Nome da database inicial |
| UID | Usuario |
| PWD | Senha |

Drivers comuns:

- `ODBC Driver 17 for SQL Server`
- `ODBC Driver 18 for SQL Server`

### Example

```text
DRIVER={ODBC Driver 17 for SQL Server};Server=localhost;Port=1433;Database=master;UID=sa;PWD=YourPassword
```

## Common ports

- **1433** — porta padrao do listener SQL Server
- **1434** — SQL Browser (UDP)

## Pool adaptativo

SQL Server e elegivel para o pool adaptativo nativo do `odbc_fast`. Por
default o agente usa o caminho native-compatible quando aplicavel; o pool
lease-based continua disponivel como fallback.

## Troubleshooting

### "Login failed" / "Login timeout expired"

- Verificar se o SQL Server permite TCP/IP (SQL Server Configuration Manager).
- Confirmar credenciais e que o usuario tem permissao na database.
- Verificar firewall (porta 1433 aberta).
- Em `ODBC Driver 18`, certificate validation e estrita por default; usar
  `Encrypt=yes;TrustServerCertificate=yes` em ambientes de teste sem
  certificado valido.

### Testing via CMD

1. Instalar [SQL Server Command Line Utilities](https://go.microsoft.com/fwlink/?linkid=2230791).
2. Adicionar ao `PATH` (ex.: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn`).
3. Testar:

   ```bash
   sqlcmd -S localhost,1433 -U sa -P YourPassword -Q "SELECT 1"
   ```

## Variaveis de ambiente

- Producao: `ODBC_DSN_SQL_SERVER`
- Testes E2E: `ODBC_TEST_DSN_SQL_SERVER`

Ver `.env.example` e `docs/testing/e2e_setup.md` para mais detalhes.
