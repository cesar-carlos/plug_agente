# PostgreSQL Connection

## Connection string format

ODBC para PostgreSQL espera `Server=`, `Port=` e `Database=` separados.

### Format

```text
DRIVER={PostgreSQL Unicode};Server=host;Port=5432;Database=name;UID=user;PWD=password
```

### Parameters

| Parameter | Description |
| --------- | ----------- |
| DRIVER | ODBC driver name (ex.: `PostgreSQL Unicode`, `PostgreSQL ANSI`) |
| Server | Hostname ou IP do servidor |
| Port | Porta TCP (default `5432`) |
| Database | Nome da database inicial |
| UID | Usuario |
| PWD | Senha |

Drivers comuns:

- `PostgreSQL Unicode` (recomendado em Windows 64-bit)
- `PostgreSQL ANSI`

### Example

```text
DRIVER={PostgreSQL Unicode};Server=localhost;Port=5432;Database=postgres;UID=postgres;PWD=YourPassword
```

## Common ports

- **5432** — porta padrao do PostgreSQL

## Pool adaptativo

PostgreSQL e elegivel para o pool adaptativo nativo do `odbc_fast`. Antes de
aumentar concorrencia em producao, valide cancelamento, lock timeout e
streaming com benchmark representativo (ver
`docs/architecture/odbc_worker_evaluation_criteria.md`).

## Troubleshooting

### "Connection refused" / "could not translate host name"

- Confirmar que o `postgresql.conf` aceita conexoes TCP (`listen_addresses`).
- Verificar `pg_hba.conf` para permitir o usuario/IP.
- Confirmar que a porta 5432 esta aberta no firewall.
- Confirmar driver ODBC instalado (32-bit vs 64-bit precisa casar com o app).

### "FATAL: password authentication failed"

- Conferir credenciais e metodo de autenticacao em `pg_hba.conf` (md5/scram).
- Em produccao, prefira SSL com `SSLmode=require` na connection string.

### Testing via CMD

1. Instalar `psql` (incluido no PostgreSQL ou via
   [EDB](https://www.enterprisedb.com/downloads/postgres-postgresql-downloads)).
2. Testar:

   ```bash
   psql -h localhost -p 5432 -U postgres -d postgres -c "SELECT 1"
   ```

## Variaveis de ambiente

- Producao: `ODBC_DSN_POSTGRESQL`
- Testes E2E: `ODBC_TEST_DSN_POSTGRESQL`

Ver `.env.example` e `docs/testing/e2e_odbc.md` para mais detalhes.
