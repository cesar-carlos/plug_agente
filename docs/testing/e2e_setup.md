# Configuração de Testes E2E

Testes end-to-end e de integração que usam recursos reais (API, ODBC) dependem de variáveis de ambiente definidas no `.env`.

## Pré-requisitos

1. Copie `.env.example` para `.env`:

   ```bash
   # Windows
   copy .env.example .env

   # Linux / macOS
   cp .env.example .env
   ```

2. Edite `.env` e defina as variáveis necessárias para os testes que deseja rodar.

## Variáveis de Ambiente

### API (api_test.dart)

| Variável               | Obrigatória | Descrição                                            |
| ---------------------- | ----------- | ---------------------------------------------------- |
| `RUN_LIVE_API_TESTS`   | Sim         | `true` para executar testes de API                   |
| `API_TEST_BASE_URL`    | Não         | URL base (default: `http://31.97.29.223:3000/`)      |
| `API_TEST_TIMEOUT_URL` | Não         | URL para teste de timeout (default: IP não roteável) |

### ODBC (odbc_streaming_live_integration_test.dart)

| Variável                                            | Obrigatória  | Descrição                                                                     |
| --------------------------------------------------- | ------------ | ----------------------------------------------------------------------------- |
| `ODBC_TEST_DSN` ou `ODBC_DSN`                       | SQL Anywhere | Connection string SQL Anywhere/Sybase                                         |
| `ODBC_TEST_DSN_SQL_SERVER` ou `ODBC_DSN_SQL_SERVER` | SQL Server   | Connection string SQL Server                                                  |
| `ODBC_TEST_DSN_POSTGRESQL` ou `ODBC_DSN_POSTGRESQL` | PostgreSQL   | Connection string PostgreSQL                                                  |
| `ODBC_INTEGRATION_SMOKE_QUERY`                      | Não          | Query smoke (default: `SELECT 1`)                                             |
| `ODBC_INTEGRATION_LONG_QUERY`                       | Cancelamento | Query longa para teste de cancelamento                                        |
| `ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE`          | Não          | Query longa específica SQL Anywhere (ex.: `SELECT * FROM sys.systab`)         |
| `ODBC_SQL_ANYWHERE_TOP_START_AT_QUERY`              | Não          | Query opcional para `odbc_sql_anywhere_top_start_at_live_test` (TOP/START AT) |
| `ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER`            | Não          | Query longa específica SQL Server (ex.: `SELECT * FROM sys.tables`)           |
| `ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL`            | Não          | Query longa específica PostgreSQL (ex.: `SELECT * FROM pg_tables`)            |

Pelo menos um DSN deve estar definido para rodar os testes ODBC. O teste usa o primeiro disponível na ordem: SQL Anywhere → SQL Server → PostgreSQL.

### ODBC RPC (`odbc_rpc_execute_coverage_live_e2e_test.dart`)

Usa apenas `ODBC_TEST_DSN` / `ODBC_DSN` (não usa fallback SQL Server/PostgreSQL).

| Variável                        | Obrigatória | Descrição                                                                                      |
| ------------------------------- | ----------- | ---------------------------------------------------------------------------------------------- |
| `ODBC_E2E_REQUIRE_MULTI_RESULT` | Não         | `true`: falha se `multi_result` não devolver `result_sets`/linhas (sem fallback RPC no teste). |
| `ODBC_E2E_TRANSACTIONAL_BATCH`  | Não         | `true`: habilita o terceiro teste do ficheiro (`sql.executeBatch` com `transaction: true`).    |

**Multi-result e pool:** o `OdbcDatabaseGateway` tenta `executeQueryMultiFull` na conexão do pool; se o payload vier vazio com sucesso, repete a mesma execução numa **conexão direta** e incrementa o contador de métricas `multi_result_pool_vacuous_fallback` no `MetricsCollector`. Se ainda assim vier vazio, regista `multi_result_direct_still_vacuous`. Os contadores de evento são chaves estáveis para exportação (ex.: OpenTelemetry).

**Batch transacional:** `executeBatch` com `transaction: true` usa **conexão ODBC direta** (sem pool) para `beginTransaction`/`commit`, evitando falhas típicas de handle do pool (`Invalid connection ID`, etc.). O contador de métricas `transactional_batch_direct_path` incrementa por lote transacional executado. O 3.º teste E2E continua **opcional** via `ODBC_E2E_TRANSACTIONAL_BATCH` (desligado por omissão no `.env.example` para `flutter test` verde).

## Verificar Configuração

Antes de rodar os testes, verifique se as variáveis estão corretas:

```bash
dart run tool/check_e2e_env.dart
```

O script exibe quais variáveis estão definidas e quais testes serão executados ou ignorados. Pode ser executado de qualquer diretório; localiza a raiz do projeto automaticamente.

## Executar Testes

```bash
# Todos os testes de integração
flutter test test/integration/

# API tests
flutter test test/infrastructure/external_services/api_test.dart

# ODBC streaming
flutter test test/integration/odbc_streaming_live_integration_test.dart

# ODBC tabela Cliente (SELECT * / COUNT)
flutter test test/integration/odbc_cliente_table_live_test.dart

# ODBC multi-result (duas SELECT no mesmo script — depende do driver)
flutter test test/integration/odbc_multi_result_live_test.dart

# ODBC RPC sql.execute / sql.executeBatch (DDL + DML; usa só ODBC_TEST_DSN / ODBC_DSN)
flutter test test/integration/odbc_rpc_execute_coverage_live_e2e_test.dart
```

Testes que dependem de variáveis não definidas são **ignorados** (skip) com mensagem explicativa.

## Testar Conectividade via CMD

### SQL Anywhere

Use os scripts em `tool/`:

- `tool/test_db_cmd.bat` – teste de conectividade (dbping)
- `tool/test_select1_cmd.bat` – executa `SELECT 1` (dbisql)

Edite as variáveis no início de cada script. Consulte `docs/database/sql_anywhere_connection.md`.

### SQL Server

1. Instale [SQL Server Command Line Utilities](https://go.microsoft.com/fwlink/?linkid=2230791)
2. Adicione ao PATH (ex.: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn`)
3. Teste:
   ```bash
   sqlcmd -S localhost,1433 -U sa -P YourPassword -Q "SELECT 1"
   ```

### PostgreSQL

1. Instale o cliente `psql` (incluído no PostgreSQL ou via [EDB](https://www.enterprisedb.com/downloads/postgres-postgresql-downloads))
2. Teste:
   ```bash
   psql -h localhost -p 5432 -U postgres -d postgres -c "SELECT 1"
   ```

## Referências

- `test/helpers/e2e_env.dart` – helper `E2EEnv` para acesso às variáveis
- `test/helpers/odbc_e2e_coverage_sql.dart` – DDL/DML por dialeto para E2E ODBC
- `test/helpers/odbc_e2e_row_assertions.dart` – leitura de colunas ODBC case-insensitive nos testes
- `test/helpers/odbc_e2e_rpc_harness.dart` – gateway real + `RpcMethodDispatcher` para E2E RPC
- `.env.example` – template com todas as variáveis documentadas
- `docs/database/sql_anywhere_connection.md` – formato de connection string SQL Anywhere

## Notas

- **`.env` nos testes Flutter:** O `E2EEnv` localiza a raiz do projeto (sobe diretórios até achar `pubspec.yaml`) e lê `.env` via sistema de arquivos + `flutter_dotenv.loadFromString` (não usa assets do `pubspec.yaml`).
- **check_e2e_env vs E2EEnv:** O script `tool/check_e2e_env.dart` roda com `dart run` (sem `dart:ui`) e usa um parser de linhas equivalente ao caso comum `chave=valor` (primeiro `=` separa chave e valor). Para entradas muito exóticas, a fonte de verdade nos testes é o `E2EEnv`.
