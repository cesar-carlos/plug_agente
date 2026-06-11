# E2E - ODBC

Testes E2E que dependem de DSN ODBC real. Cobrem streaming, RPC, DML
performance, bulk load, queue burst e lock contention.

Index geral: [e2e_setup.md](e2e_setup.md). Connection strings por driver:
[`docs/database/`](../database/readme.md).

## DSNs (`odbc_streaming_live_integration_test.dart` e demais)

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_TEST_DSN` ou `ODBC_DSN` | SQL Anywhere | Connection string SQL Anywhere/Sybase |
| `ODBC_TEST_DSN_SQL_SERVER` ou `ODBC_DSN_SQL_SERVER` | SQL Server | Connection string SQL Server |
| `ODBC_TEST_DSN_POSTGRESQL` ou `ODBC_DSN_POSTGRESQL` | PostgreSQL | Connection string PostgreSQL |
| `ODBC_INTEGRATION_SMOKE_QUERY` | Nao | Query smoke (default: `SELECT 1`) |
| `ODBC_INTEGRATION_LONG_QUERY` | Cancelamento | Query longa para teste de cancelamento |
| `ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE` | Nao | Query longa especifica SQL Anywhere |
| `ODBC_SQL_ANYWHERE_TOP_START_AT_QUERY` | Nao | Query opcional para `odbc_sql_anywhere_top_start_at_live_test` (TOP/START AT) |
| `ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER` | Nao | Query longa especifica SQL Server |
| `ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL` | Nao | Query longa especifica PostgreSQL |

`E2EEnv.odbcLongQuery` escolhe a variavel consoante o DSN que o streaming
esta a usar: especifica do motor, senao cai em `ODBC_INTEGRATION_LONG_QUERY`
se existir.

Pelo menos um DSN deve estar definido para rodar os testes ODBC. O teste usa
o primeiro disponivel na ordem: SQL Anywhere -> SQL Server -> PostgreSQL.

## Runtime tuning (`odbc_fast`)

Os harnesses E2E que inicializam `odbc.ServiceLocator` usam os mesmos
calculos do runtime da app:

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_ASYNC_WORKER_COUNT` | Nao | Override positivo para workers assincronos; limitado a `min(poolSize, CPU cores)` |
| `ODBC_ASYNC_MAX_PENDING_REQUESTS` | Nao | Override positivo para requests pendentes no worker pool interno; default `poolSize * 4` |
| `ODBC_RESULT_ENCODING` | Nao | Opt-in para `rowMajor`, `columnar` ou `columnarCompressed` em queries parametrizadas; default `rowMajor` |

O app mantem `asyncBackpressureMode=failFast` de forma explicita porque a
fila `SqlExecutionQueue` ja controla backpressure antes do worker pool
interno do `odbc_fast`.

O pool adaptativo ODBC fica habilitado por default para drivers elegiveis
(SQL Server/PostgreSQL), mas continua bloqueado para SQL Anywhere. Um valor
persistido `feature_enable_odbc_experimental_driver_adaptive_pooling=false`
funciona como opt-out operacional.

### Smoke do runtime (sem DSN)

```powershell
dart run tool/check_odbc_fast_runtime.dart --require-columnar-compressed
```

Inicializa o worker async e verifica exports nativos usados pelo modo
`columnarCompressed`. Faz parte do fluxo operacional consolidado.

### Benchmarks manuais

```powershell
# Async concurrency
dart run D:\Developer\dart_odbc_fast\example\async_concurrency_benchmark.dart
python tool/odbc_async_benchmark.py

# Streaming legado vs batched
dart run D:\Developer\dart_odbc_fast\example\streaming_performance_benchmark.dart
python tool/odbc_streaming_benchmark.py
```

`odbc_streaming_benchmark.py` usa `ODBC_STREAM_BENCH_QUERY` quando
definido; caso contrario, reaproveita a query longa do driver
(`ODBC_INTEGRATION_LONG_QUERY_*` ou `ODBC_INTEGRATION_LONG_QUERY`). Isso
evita benchmark acidental com `SELECT 1`.

### Driver matrix

```powershell
python tool/odbc_driver_matrix_benchmark.py
```

### Fluxo operacional completo

```powershell
python tool/run_odbc_operational_validation.py
python tool/run_odbc_operational_validation.py --all
```

Detalhes em
[`docs/architecture/odbc_operational_validation_runbook.md`](../architecture/odbc_operational_validation_runbook.md).

## ODBC RPC (`odbc_rpc_execute_coverage_live_e2e_test.dart`)

Requer **pelo menos um** DSN ODBC (ou um override explicito):

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_E2E_RPC_DSN` | Nao | Se definido e nao vazio, usa **so** esta connection string no E2E RPC (ignora os DSNs abaixo). |
| DSNs padrao | Um deles* | Se `ODBC_E2E_RPC_DSN` estiver vazio, mesma prioridade que streaming: `ODBC_TEST_DSN` / `ODBC_DSN` -> `ODBC_TEST_DSN_SQL_SERVER` -> `ODBC_TEST_DSN_POSTGRESQL`. |

\* Mesma prioridade de DSN que a seccao de DSNs acima.

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_E2E_REQUIRE_MULTI_RESULT` | Nao | `true`: falha se `multi_result` nao devolver `result_sets`/linhas (sem fallback RPC no teste). |
| `ODBC_E2E_TRANSACTIONAL_BATCH` | Nao | `true`: habilita o terceiro teste do ficheiro (`sql.executeBatch` com `transaction: true`). |

**Multi-result e pool:** o `OdbcDatabaseGateway` tenta `executeQueryMultiFull`
na conexao do pool; se o payload vier vazio com sucesso, repete a mesma
execucao numa **conexao direta** e incrementa o contador de metricas
`multi_result_pool_vacuous_fallback` no `MetricsCollector`. Se ainda assim
vier vazio, registra `multi_result_direct_still_vacuous`. Os contadores de
evento sao chaves estaveis para exportacao (ex.: OpenTelemetry).

**Batch transacional:** `executeBatch` com `transaction: true` usa fast path
pooled/native-compatible para DML-only em SQL Server/PostgreSQL quando
elegivel e continua em conexao direta para SQL Anywhere, batches com
leitura/`RETURNING`/`OUTPUT`, options incompativeis ou fallback. Os
contadores estaveis sao `transactional_batch_native_pool_path`,
`transactional_batch_native_pool_fallback` e
`transactional_batch_direct_path`. O 3.o teste E2E continua **opcional** via
`ODBC_E2E_TRANSACTIONAL_BATCH` (desligado por omissao no `.env.example` para
`flutter test` verde).

## ODBC DML performance (`odbc_dml_perf_live_e2e_test.dart`)

Mede o tempo de parede (cliente) para: **lote de INSERTs**
(`sql.executeBatch` com N comandos), **UPDATE** em todas as linhas,
**DELETE** de todas as linhas. Usa o mesmo DSN que o E2E RPC
(`E2EEnv.odbcE2eRpcConnectionString`). **Opt-in.**

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_E2E_DML_PERF_TESTS` | Sim | `true` para executar este ficheiro |
| `ODBC_E2E_DML_PERF_ROW_COUNT` | Nao | Numero de linhas no lote de insert (default 100, limite 10-10000) |
| `ODBC_E2E_DML_PERF_MAX_MS_INSERT` | Nao | Se definido, falha o teste se a fase de insert exceder estes ms |
| `ODBC_E2E_DML_PERF_MAX_MS_UPDATE` | Nao | Idem para UPDATE em massa |
| `ODBC_E2E_DML_PERF_MAX_MS_DELETE` | Nao | Idem para DELETE em massa |

Os limites de ms sao opcionais (uteis em maquinas conhecidas ou CI com DSN
estavel); sem eles o teste so verifica sucesso e registra tempos no log
(`e2e.odbc_dml_perf`).

## ODBC DML bulk load (`odbc_dml_bulk_load_live_e2e_test.dart`)

Cria tabela, insere muitas linhas (default **50 000**) via `sql.bulkInsert`
(bulk insert nativo do `odbc_fast`), depois: `SELECT COUNT(*)`; **UPDATE**
em todas as linhas; **DELETE** de todas; **DROP** da tabela. **Opt-in.**

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_E2E_DML_BULK_TESTS` | Sim | `true` para correr |
| `ODBC_E2E_DML_BULK_ROW_COUNT` | Nao | Total de linhas (default 50000, limite 10k-200k) |
| `ODBC_E2E_DML_BULK_MAX_MS_CREATE` | Nao | Teto (ms) para CREATE (opcional) |
| `ODBC_E2E_DML_BULK_MAX_MS_INSERT` | Nao | Teto (ms) para toda a fase de insert (default interno: 30000) |
| `ODBC_E2E_DML_BULK_MAX_MS_UPDATE` | Nao | Teto (ms) para UPDATE em massa |
| `ODBC_E2E_DML_BULK_MAX_MS_DELETE` | Nao | Teto (ms) para DELETE em massa |
| `ODBC_E2E_DML_BULK_MAX_MS_DROP` | Nao | Teto (ms) para DROP no fim do teste |

Tempos tambem sao emitidos no log `e2e.odbc_dml_bulk` como
`E2E_DML_BULK_PHASE_TIMINGS` com JSON estruturado por fase. O teste utiliza
`timeout` de 30 minutos; aumente o timeout do runner se 200k linhas for
insuficiente.

## ODBC DML stress (`odbc_dml_stress_live_e2e_test.dart`)

Cria tabela com nome unico por execucao, repete ciclos **INSERT** (lotes
paralelos via `sql.executeBatch`), **UPDATE** e **DELETE** por faixas de `id`,
valida contagem de linhas e ausencia de leases no pool, e faz **DROP** no
`tearDownAll`. Inclui cenario com `QueuedDatabaseGateway` e DML concorrente.
**Opt-in.**

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_E2E_DML_STRESS_TESTS` | Sim | `true` para correr |
| `ODBC_E2E_DML_STRESS_ROW_COUNT` | Nao | Linhas por iteracao (default 100, limite 100-100k) |
| `ODBC_E2E_DML_STRESS_ITERATIONS` | Nao | Ciclos insert/update/delete (default 1, limite 1-50) |
| `ODBC_E2E_DML_STRESS_CONCURRENCY` | Nao | Workers paralelos por fase (default 4, limite 1-32) |
| `ODBC_E2E_DML_STRESS_BATCH_CHUNK_SIZE` | Nao | Comandos por `sql.executeBatch` (default 1000, limite 32-2000) |
| `ODBC_E2E_DML_STRESS_QUEUE_SIZE` | Nao | Fila do gateway enfileirado (default 8) |
| `ODBC_E2E_DML_STRESS_WORKERS` | Nao | Workers do gateway enfileirado (default 4) |
| `ODBC_E2E_DML_STRESS_MAX_MS_PER_ITERATION` | Nao | Teto (ms) por iteracao completa (opcional) |

O cenario com `QueuedDatabaseGateway` limita a 2000 linhas (ou menos, se
`ODBC_E2E_DML_STRESS_ROW_COUNT` for menor) e usa `executeBatch` transacional
por chunk para manter o stress da fila sem um `executeNonQuery` por linha.

Tempos por iteracao aparecem no stdout do `flutter test` (`[odbc_dml_stress]`)
e no log `e2e.odbc_dml_stress` como `E2E_DML_STRESS_ITERATION_TIMINGS`.

## SQL queue burst (`sql_queue_burst_test.dart`)

Dispara pedidos `executeQuery` em paralelo (`Future.wait`) contra um
`QueuedDatabaseGateway` com fila pequena e query lenta para saturar a fila
(rejeicoes `sql_queue_full`) e validar recuperacao sem fugas de leases no
pool. Usa o mesmo DSN que o E2E RPC (`E2EEnv.odbcE2eRpcConnectionString`).
**Opt-in.**

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `RUN_ODBC_BURST_TESTS` | Sim | `true` para nao ignorar este ficheiro |
| DSN RPC | Sim | `ODBC_E2E_RPC_DSN` ou fallback na ordem habitual (Anywhere -> SQL Server -> PostgreSQL) |
| Query longa | Sim | `E2EEnv.odbcLongQuery` deve estar definido (variaveis por motor acima, ou `ODBC_INTEGRATION_LONG_QUERY`) |
| `ODBC_BURST_REQUEST_COUNT` | Nao | Total de requests no burst (default 24, limite 8-200) |
| `ODBC_BURST_QUEUE_SIZE` | Nao | Tamanho da fila (default 8, limite 4-100) |
| `ODBC_BURST_WORKERS` | Nao | Workers concorrentes (default 4, limite 1-32) |
| `ODBC_BURST_ENQUEUE_TIMEOUT_MS` | Nao | Timeout de enfileiramento (default 5000ms) |
| `ODBC_BURST_MAX_MS_PER_TEST` | Nao | Teto por caso de burst (default 45000ms) |

Detalhes da estrategia de testes da fila:
[`sql_queue_concurrency_tests.md`](sql_queue_concurrency_tests.md).

## ODBC lock contention (`odbc_lock_contention_live_integration_test.dart`)

Cenario com **concorrencia real** (pode ser lento ou sensivel ao ambiente).
Requer o mesmo DSN que os testes ODBC genericos (`odbcConnectionStringAny`:
SQL Anywhere -> SQL Server -> PostgreSQL).

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `ODBC_RUN_LOCK_CONTENTION_TESTS` | Sim | `true` para nao ignorar este ficheiro (sem isto, os testes dao `skip`). |

## Executar

```bash
# Streaming
flutter test test/integration/odbc_streaming_live_integration_test.dart

# SQL Anywhere TOP/START AT (DSN deve parecer SQL Anywhere)
flutter test test/integration/odbc_sql_anywhere_top_start_at_live_test.dart

# RPC (sql.execute / sql.executeBatch)
flutter test test/integration/odbc_rpc_execute_coverage_live_e2e_test.dart

# DML performance (opt-in)
flutter test test/integration/odbc_dml_perf_live_e2e_test.dart

# DML bulk load (opt-in, perf)
flutter test --tags perf test/integration/odbc_dml_bulk_load_live_e2e_test.dart

# DML stress (opt-in, perf)
flutter test test/integration/odbc_dml_stress_live_e2e_test.dart

# Queue burst (opt-in)
flutter test test/integration/sql_queue_burst_test.dart

# Lock contention (opt-in)
flutter test test/integration/odbc_lock_contention_live_integration_test.dart

# Recuperacao de conexao (quando aplicavel)
flutter test test/integration/connection_recovery_integration_test.dart
```

## Testar conectividade via CMD

### SQL Anywhere

Use os scripts em `tool/`:

- `tool/test_db_cmd.bat` — teste de conectividade (`dbping`)
- `tool/test_select1_cmd.bat` — executa `SELECT 1` (`dbisql`)

Edite as variaveis no inicio de cada script. Consulte
[`docs/database/sql_anywhere_connection.md`](../database/sql_anywhere_connection.md).

### SQL Server

1. Instale [SQL Server Command Line Utilities](https://go.microsoft.com/fwlink/?linkid=2230791).
2. Adicione ao `PATH` (ex.: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn`).
3. Teste:

   ```bash
   sqlcmd -S localhost,1433 -U sa -P YourPassword -Q "SELECT 1"
   ```

### PostgreSQL

1. Instale o cliente `psql` (incluido no PostgreSQL ou via
   [EDB](https://www.enterprisedb.com/downloads/postgres-postgresql-downloads)).
2. Teste:

   ```bash
   psql -h localhost -p 5432 -U postgres -d postgres -c "SELECT 1"
   ```
