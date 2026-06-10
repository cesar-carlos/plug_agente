# Database

Guias de connection string ODBC por driver suportado pelo agente. Todos os
drivers passam pela mesma camada (`odbc_fast` -> `OdbcDatabaseGateway` ->
`OdbcConnectionPool`); o que muda e o formato do DSN.

| Driver | Doc | Pool nativo |
| --- | --- | --- |
| SQL Anywhere / Sybase | [sql_anywhere_connection.md](sql_anywhere_connection.md) | nao (lease-based obrigatorio) |
| SQL Server | [sql_server_connection.md](sql_server_connection.md) | sim (adaptativo por default) |
| PostgreSQL | [postgresql_connection.md](postgresql_connection.md) | sim (adaptativo por default) |

## Variaveis de ambiente equivalentes

O mesmo DSN pode ser configurado para producao e/ou para testes E2E:

| Driver | Producao (`OdbcConnectionSettings`) | Testes E2E |
| --- | --- | --- |
| SQL Anywhere | `ODBC_DSN` | `ODBC_TEST_DSN` |
| SQL Server | `ODBC_DSN_SQL_SERVER` | `ODBC_TEST_DSN_SQL_SERVER` |
| PostgreSQL | `ODBC_DSN_POSTGRESQL` | `ODBC_TEST_DSN_POSTGRESQL` |

Detalhes E2E e prioridade entre DSNs: `docs/testing/e2e_setup.md`.

## Tuning compartilhado

- `ODBC_POOL_SIZE` — tamanho do pool lease-based (default **8**,
  `ConnectionConstants.defaultPoolSize`).
- `ODBC_ASYNC_WORKER_COUNT` — workers do worker pool interno do `odbc_fast`
  (default `min(ODBC_POOL_SIZE, CPU cores)`).
- `ODBC_ASYNC_MAX_PENDING_REQUESTS` — fila do worker pool (default
  `ODBC_POOL_SIZE * 4`).
- `ODBC_RESULT_ENCODING` — `rowMajor` (default), `columnar`,
  `columnarCompressed`.

Detalhes em `docs/architecture/performance_reliability_improvements.md`.

## Pool adaptativo

O pool adaptativo do `odbc_fast` fica habilitado por default para drivers
elegiveis (SQL Server, PostgreSQL). SQL Anywhere permanece no caminho
lease/direct.

Para desligar manualmente como opt-out operacional, persista
`feature_enable_odbc_experimental_driver_adaptive_pooling=false`.
