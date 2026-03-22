# Configuração de Testes E2E / Live

Testes que usam recursos reais (API, ODBC) dependem de variáveis no `.env`.

## Estrutura `test/`

| Pasta                                                    | Conteúdo                                                                                  |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `test/live/`                                             | Testes com tag **`live`**: rede, ODBC real, RPC real. Podem ficar em **skip** sem `.env`. |
| `test/integration/`                                      | Integração **offline** (mocks/fakes), sem ODBC nem API live.                              |
| Restantes (`test/application`, `test/infrastructure`, …) | Unitários / widget / integração leve.                                                     |

**Tag `live`:** definida em `dart_test.yaml`. Correr `flutter test --exclude-tags=live` exclui toda a pasta semântica live (ficheiros anotados com `@Tags(['live'])`). Atalhos: `tool/flutter_test_no_api.bat` (Windows) ou `tool/flutter_test_no_api.sh` (Unix).

**API live é opcional:** com `RUN_LIVE_API_TESTS` ausente ou `false`, `test/live/api_live_test.dart` fica em skip; o fluxo local/CI sem hub pode manter assim e usar apenas ODBC ou testes offline.

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

### API (`test/live/api_live_test.dart`)

| Variável               | Obrigatória | Descrição                                                     |
| ---------------------- | ----------- | ------------------------------------------------------------- |
| `RUN_LIVE_API_TESTS`   | Não         | `true` para executar testes de API; omitir/false no dia a dia |
| `API_TEST_BASE_URL`    | Não         | URL base (default: `http://31.97.29.223:3000/`)               |
| `API_TEST_TIMEOUT_URL` | Não         | URL para teste de timeout (default: IP não roteável)          |

### ODBC streaming (`test/live/odbc_streaming_live_test.dart`)

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

### ODBC RPC live (`test/live/odbc_rpc_execute_live_e2e_test.dart`)

Cobre **caminhos de produto** (`sql.execute` / `sql.executeBatch`, multi-result, DML em lote), não cobertura de linhas Dart — para LCOV use `flutter test --coverage`.

**Matriz de DSN:** corre **um grupo aninhado por connection string distinta**, nesta ordem: `ODBC_TEST_DSN` / `ODBC_DSN` (rótulo `primary`), `ODBC_TEST_DSN_SQL_SERVER` / `ODBC_DSN_SQL_SERVER` (`sql_server`), `ODBC_TEST_DSN_POSTGRESQL` / `ODBC_DSN_POSTGRESQL` (`postgresql`). Strings duplicadas são executadas uma vez só.

Cada grupo cria uma tabela com nome único (`plug_agente_e2e_live_<uuid>`) para isolamento entre execuções.

| Variável                        | Obrigatória | Descrição                                                                                      |
| ------------------------------- | ----------- | ---------------------------------------------------------------------------------------------- |
| `ODBC_E2E_REQUIRE_MULTI_RESULT` | Não         | `true`: falha se `multi_result` não devolver `result_sets`/linhas (sem fallback RPC no teste). |
| `ODBC_E2E_TRANSACTIONAL_BATCH`  | Não         | `true`: habilita o 4.º teste do grupo (`sql.executeBatch` com `transaction: true`).            |

### ODBC RPC benchmark (latência + histórico JSONL)

Documentação completa: [`benchmark/README.md`](../../benchmark/README.md).

| Variável                        | Obrigatória       | Descrição                                                                       |
| ------------------------------- | ----------------- | ------------------------------------------------------------------------------- |
| `ODBC_E2E_BENCHMARK`            | Sim (para correr) | `true`: executa `test/live/odbc_rpc_benchmark_live_e2e_test.dart`.              |
| `ODBC_E2E_BENCHMARK_RECORD`     | Não               | `true`: anexa linhas ao ficheiro JSONL (padrão `benchmark/e2e_odbc_rpc.jsonl`). |
| `ODBC_E2E_BENCHMARK_FILE`       | Não               | Caminho alternativo do JSONL.                                                   |
| `ODBC_E2E_BENCHMARK_DB_HOSTING` | Não               | `local` ou `remote` — metadado para gráficos.                                   |
| `ODBC_E2E_BENCHMARK_MAX_MS_*`   | Não               | Limites de regressão por caso (ex.: `ODBC_E2E_BENCHMARK_MAX_MS_MATERIALIZED`).  |

Resumo do histórico: `dart run tool/summarize_e2e_benchmark.dart`.

CI opcional (manual): `.github/workflows/e2e_benchmark_optional.yml`.

### Micro-benchmarks gzip / compressor (tag `benchmark`)

Suites leves que medem apenas CPU de gzip e do `GzipCompressor` (sem Socket.IO nem ODBC). Documentação detalhada: [`benchmark/README.md`](../../benchmark/README.md) (secções 4 e 5).

| Variável                         | Obrigatória       | Descrição                                                                                                                                        |
| -------------------------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CODEC_GZIP_BENCHMARK`           | Sim (para correr) | `true`: executa `test/benchmark/gzip_codec_benchmark_test.dart` (primitivas byte-a-byte).                                                        |
| `CODEC_GZIP_BENCHMARK_ITERATIONS` | Não               | Iterações (default 24).                                                                                                                          |
| `CODEC_GZIP_BENCHMARK_PAYLOAD_KB` | Não              | Tamanho do buffer de teste em KiB (default 256).                                                                                                   |
| `GZIP_COMPRESSOR_BENCHMARK`      | Sim (para correr) | `true`: executa `test/benchmark/gzip_compressor_benchmark_test.dart` (mapas `compressed_data` + base64).                                        |
| `GZIP_COMPRESSOR_BENCHMARK_*`    | Não               | Ver comentários no ficheiro de teste / `benchmark/README.md` (iterações, contagem de linhas, tamanho de payload por linha).                      |

**Importante:** estes testes leem `Platform.environment`. O Flutter **não** carrega automaticamente o `.env` para variáveis de processo; defina-as no shell (por exemplo `CODEC_GZIP_BENCHMARK=true flutter test ...`) ou use a mesma convenção que o vosso CI. Os benchmarks de transporte (`SOCKET_TRANSPORT_*`) continuam a usar `E2EEnv` / `.env` via `loadLiveTestEnv()`.

#### Métricas esperadas (diagnóstico)

Chaves estáveis no `MetricsCollector` (exportação, ex.: OpenTelemetry):

| Contador (chave)                     | Quando incrementa                                                                            |
| ------------------------------------ | -------------------------------------------------------------------------------------------- |
| `multi_result_pool_vacuous_fallback` | Multi-result no pool devolveu sucesso mas envelope vazio; gateway repetiu em conexão direta. |
| `multi_result_direct_still_vacuous`  | Mesmo em conexão direta o multi-result seguiu vazio (driver/edge case).                      |
| `transactional_batch_direct_path`    | Cada `executeBatch` com `transaction: true` executado pelo caminho ODBC direto.              |

O 3.º teste do grupo valida multi-result e, quando há dados, espera `multi_result_direct_still_vacuous` = 0. O 4.º teste (opcional) espera `transactional_batch_direct_path` ≥ 1.

### Cobertura Dart (RPC + ODBC / multi-result)

Para LCOV só em `lib/application/rpc/` e ficheiros `lib/infrastructure/external_services/odbc_*`:

```bash
# Windows
tool\flutter_test_coverage_multi_result.bat

# Linux / macOS
./tool/flutter_test_coverage_multi_result.sh
```

Gera `coverage/lcov.info` completo e `coverage/lcov_multi_result.info` filtrado (`dart run tool/filter_lcov_info.dart …`).

## Verificar Configuração

Antes de rodar os testes, verifique se as variáveis estão corretas:

```bash
dart run tool/check_e2e_env.dart
```

O script exibe quais variáveis estão definidas e quais testes serão executados ou ignorados. Pode ser executado de qualquer diretório; localiza a raiz do projeto automaticamente.

## Executar Testes

```bash
# Suíte completa (live em skip se faltar .env / flags)
flutter test

# Rápido: exclui ficheiros com tag live (CI usa este modo num dos passos)
flutter test --exclude-tags=live
# Windows: tool\flutter_test_fast.bat
# Unix: sh tool/flutter_test_fast.sh | sh tool/flutter_test_live.sh

# Só testes live (API + ODBC + RPC conforme .env)
flutter test --tags=live
# ou
flutter test test/live/

# Integração offline apenas (sem rede/ODBC)
flutter test test/integration/

# ODBC SQL Anywhere TOP/START AT (DSN deve parecer SQL Anywhere)
flutter test test/live/odbc_sql_anywhere_top_start_at_live_test.dart

# Recuperação de conexão (mocks — offline)
flutter test test/integration/connection_recovery_integration_test.dart
```

Testes live que dependem de variáveis não definidas são **ignorados** (skip) com mensagem explicativa (`E2EEnv.skipUnless*`, constantes em `e2e_env.dart`).

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

- `dart_test.yaml` – descrição da tag `live`
- `tool/flutter_test_fast.bat` / `tool/flutter_test_fast.sh` – exclui tag `live`
- `tool/flutter_test_live.sh` – só tag `live`
- `test/helpers/e2e_env.dart` – variáveis, matriz `odbcRpcLiveTargets`, mensagens `skipUnless*` / `skipReason*`
- `test/helpers/live_test_env.dart` – `loadLiveTestEnv()` (alias de `E2EEnv.load()`)
- `test/helpers/odbc_live_bootstrap.dart` – ciclo de vida `ServiceLocator` partilhado (streaming, TOP/START AT)
- `tool/e2e_dotenv_parse.dart` – parser partilhado `.env` (chave=valor, primeiro `=`)
- `test/helpers/odbc_e2e_live_sql.dart` – DDL/DML por dialeto e nome de tabela isolado
- `test/helpers/odbc_e2e_rpc_request_builders.dart` – construtores de `RpcRequest` para os testes
- `test/helpers/odbc_e2e_row_assertions.dart` – leitura de colunas ODBC case-insensitive nos testes
- `test/helpers/odbc_e2e_rpc_harness.dart` – gateway real + `RpcMethodDispatcher` para E2E RPC
- `.env.example` – template com todas as variáveis documentadas
- `benchmark/README.md` – suites de benchmark (ODBC RPC, transporte Socket, micro gzip)
- `test/benchmark/gzip_codec_benchmark_test.dart` / `test/benchmark/gzip_compressor_benchmark_test.dart` – micro-benchmarks gzip (variáveis `CODEC_GZIP_*` / `GZIP_COMPRESSOR_*`)
- `tool/summarize_e2e_benchmark.dart` – resumo textual do histórico JSONL
- `docs/database/sql_anywhere_connection.md` – formato de connection string SQL Anywhere

## Notas

- **`.env` nos testes Flutter:** O `E2EEnv` localiza a raiz do projeto (sobe diretórios até achar `pubspec.yaml`) e lê `.env` do disco com o mesmo parser que `tool/check_e2e_env.dart` (`parseDotEnvContent` em `tool/e2e_dotenv_parse.dart`). Chaves do ficheiro têm prioridade sobre `Platform.environment` e sobre `dotenv` do asset bundle.
- **CI:** `.github/workflows/flutter_ci.yml` corre `dart run tool/check_e2e_env.dart`, `flutter analyze`, `flutter test --exclude-tags=live` e em seguida `flutter test --tags=live` (este último faz skips rápidos se não houver `.env` no runner). Benchmark ODBC RPC é **separado**: workflow manual `e2e_benchmark_optional.yml`.
