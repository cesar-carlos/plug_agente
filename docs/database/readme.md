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

Detalhes E2E e prioridade entre DSNs: `docs/testing/e2e_odbc.md`
(indice geral: `docs/testing/e2e_setup.md`).

## Tuning compartilhado

Defaults e regras de `ODBC_POOL_SIZE`, `ODBC_ASYNC_*` e
`ODBC_RESULT_ENCODING`: `docs/runtime/odbc_pool_and_transactions.md`.
Status do eixo ODBC: `docs/architecture/performance_reliability_improvements.md`.

## Pool adaptativo

O pool adaptativo do `odbc_fast` fica habilitado por default para drivers
elegiveis (SQL Server, PostgreSQL). SQL Anywhere permanece no caminho
lease/direct.

Para desligar manualmente como opt-out operacional, persista
`feature_enable_odbc_experimental_driver_adaptive_pooling=false`.
