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

### Hub Socket.IO (`hub_socket_live_e2e_test.dart`)

Smoke: abre WebSocket via `SocketDataSource` (mesmo código que o transporte), namespace `/agents`, handshake com token, depois `disconnect`.

| Variável             | Obrigatória | Descrição                                                |
| -------------------- | ----------- | -------------------------------------------------------- |
| `RUN_LIVE_HUB_TESTS` | Sim         | `true` para executar este teste                          |
| `E2E_HUB_URL`        | Sim         | URL base do hub (como na app; `ensureAgentsNamespaceUrl` acrescenta `/agents` se faltar) |
| `E2E_HUB_TOKEN`      | Sim         | Token de agente enviado no auth do handshake Socket.IO  |

Não coloque o token em logs. Em CI, use *secrets* do repositório (ver job opcional `live-hub-e2e` no workflow Flutter).

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

O `E2EEnv.odbcLongQuery` escolhe a variável consoante o DSN que o streaming está a usar: específica do motor, senão cai em `ODBC_INTEGRATION_LONG_QUERY` se existir.

Pelo menos um DSN deve estar definido para rodar os testes ODBC. O teste usa o primeiro disponível na ordem: SQL Anywhere → SQL Server → PostgreSQL.

### ODBC RPC (`odbc_rpc_execute_coverage_live_e2e_test.dart`)

Requer **pelo menos um** DSN ODBC (ou um override explícito):

| Variável            | Obrigatória | Descrição                                                                                      |
| ------------------- | ----------- | ---------------------------------------------------------------------------------------------- |
| `ODBC_E2E_RPC_DSN`  | Não         | Se definido e não vazio, usa **só** esta connection string no E2E RPC (ignora os DSNs abaixo). |
| DSNs padrão         | Um deles*   | Se `ODBC_E2E_RPC_DSN` estiver vazio, usa a mesma prioridade que streaming: `ODBC_TEST_DSN` / `ODBC_DSN` → `ODBC_TEST_DSN_SQL_SERVER` → `ODBC_TEST_DSN_POSTGRESQL`. |

\* Mesma prioridade de DSN que a secção **ODBC** (`odbc_streaming_live_integration_test.dart`) acima.

| Variável                        | Obrigatória | Descrição                                                                                      |
| ------------------------------- | ----------- | ---------------------------------------------------------------------------------------------- |
| `ODBC_E2E_REQUIRE_MULTI_RESULT` | Não         | `true`: falha se `multi_result` não devolver `result_sets`/linhas (sem fallback RPC no teste). |
| `ODBC_E2E_TRANSACTIONAL_BATCH`  | Não         | `true`: habilita o terceiro teste do ficheiro (`sql.executeBatch` com `transaction: true`).    |

**Multi-result e pool:** o `OdbcDatabaseGateway` tenta `executeQueryMultiFull` na conexão do pool; se o payload vier vazio com sucesso, repete a mesma execução numa **conexão direta** e incrementa o contador de métricas `multi_result_pool_vacuous_fallback` no `MetricsCollector`. Se ainda assim vier vazio, regista `multi_result_direct_still_vacuous`. Os contadores de evento são chaves estáveis para exportação (ex.: OpenTelemetry).

**Batch transacional:** `executeBatch` com `transaction: true` usa **conexão ODBC direta** (sem pool) para `beginTransaction`/`commit`, evitando falhas típicas de handle do pool (`Invalid connection ID`, etc.). O contador de métricas `transactional_batch_direct_path` incrementa por lote transacional executado. O 3.º teste E2E continua **opcional** via `ODBC_E2E_TRANSACTIONAL_BATCH` (desligado por omissão no `.env.example` para `flutter test` verde).

### ODBC DML performance (`odbc_dml_perf_live_e2e_test.dart`)

Mede o tempo de parede (cliente) para: **lote de INSERTs** (`sql.executeBatch` com N comandos), **UPDATE** em todas as linhas, **DELETE** de todas as linhas. Usa o mesmo DSN que o E2E RPC (`E2EEnv.odbcE2eRpcConnectionString`). **Opt-in** — desligado por omissão.

| Variável | Obrigatória | Descrição |
| -------- | ----------- | --------- |
| `ODBC_E2E_DML_PERF_TESTS` | Sim | `true` para executar este ficheiro |
| `ODBC_E2E_DML_PERF_ROW_COUNT` | Não | Número de linhas no lote de insert (default 100, limite 10–10000) |
| `ODBC_E2E_DML_PERF_MAX_MS_INSERT` | Não | Se definido, falha o teste se a fase de insert exceder estes ms |
| `ODBC_E2E_DML_PERF_MAX_MS_UPDATE` | Não | Idem para UPDATE em massa |
| `ODBC_E2E_DML_PERF_MAX_MS_DELETE` | Não | Idem para DELETE em massa |

Os limites de ms são opcionais (úteis em máquinas conhecidas ou CI com DSN estável); sem eles o teste só verifica sucesso e regista tempos no log (`e2e.odbc_dml_perf`).

### ODBC DML carga em massa (`odbc_dml_bulk_load_live_e2e_test.dart`)

Cria tabela, insere muitas linhas (default **50 000**) com vários `sql.executeBatch` (cada lote com até `ODBC_E2E_DML_BULK_CHUNK_SIZE` comandos, default 1000) — o dispatcher exige `TransportLimits.maxBatchSize` alinhado ao tamanho do lote. Depois: `SELECT COUNT(*)`; **UPDATE** em todas as linhas; **DELETE** de todas; **DROP** da tabela. **Opt-in** — pode demorar muitos minutos.

| Variável | Obrigatória | Descrição |
| -------- | ----------- | --------- |
| `ODBC_E2E_DML_BULK_TESTS` | Sim | `true` para correr |
| `ODBC_E2E_DML_BULK_ROW_COUNT` | Não | Total de linhas (default 50000, limite 10k–200k) |
| `ODBC_E2E_DML_BULK_CHUNK_SIZE` | Não | Linhas por `executeBatch` (default 1000, limite 32–2000) |
| `ODBC_E2E_DML_BULK_MAX_MS_CREATE` | Não | Teto (ms) para CREATE (opcional) |
| `ODBC_E2E_DML_BULK_MAX_MS_INSERT` | Não | Teto (ms) para toda a fase de insert |
| `ODBC_E2E_DML_BULK_MAX_MS_UPDATE` | Não | Teto (ms) para UPDATE em massa |
| `ODBC_E2E_DML_BULK_MAX_MS_DELETE` | Não | Teto (ms) para DELETE em massa |
| `ODBC_E2E_DML_BULK_MAX_MS_DROP` | Não | Teto (ms) para DROP no fim do teste |

Tempos registados no log com nome `e2e.odbc_dml_bulk`. O teste utiliza `timeout` de 30 minutos; aumente o timeout do runner se 200k linhas for insuficiente.

### SQL queue burst (`sql_queue_burst_test.dart`)

Dispara **50** pedidos `executeQuery` em paralelo (`Future.wait`) contra um `QueuedDatabaseGateway` com fila pequena (**20**) e **4** workers, usando uma **query lenta** para saturar a fila (rejeições `sql_queue_full`) e validar recuperação sem fugas de leases no pool. Usa o mesmo DSN que o E2E RPC (`E2EEnv.odbcE2eRpcConnectionString`). **Opt-in.**

| Variável | Obrigatória | Descrição |
| -------- | ----------- | --------- |
| `RUN_ODBC_BURST_TESTS` | Sim | `true` para não ignorar este ficheiro |
| DSN RPC | Sim | `ODBC_E2E_RPC_DSN` ou fallback na ordem habitual (Anywhere → SQL Server → PostgreSQL) |
| Query longa | Sim | `E2EEnv.odbcLongQuery` deve estar definido (variáveis por motor em **ODBC** acima, ou `ODBC_INTEGRATION_LONG_QUERY`) — o teste precisa de SQL que demore o suficiente para encher a fila de propósito |

### ODBC lock contention (`odbc_lock_contention_live_integration_test.dart`)

Cenário com **concorrência real** (pode ser lento ou sensível ao ambiente). Requer o mesmo DSN que os testes ODBC genéricos (`odbcConnectionStringAny`: SQL Anywhere → SQL Server → PostgreSQL).

| Variável                          | Obrigatória | Descrição                                                         |
| --------------------------------- | ----------- | ----------------------------------------------------------------- |
| `ODBC_RUN_LOCK_CONTENTION_TESTS`  | Sim         | `true` para não ignorar este ficheiro (sem isto, os testes dão `skip`). |

## Verificar Configuração

Antes de rodar os testes, verifique se as variáveis estão corretas:

```bash
dart run tool/check_e2e_env.dart
```

O script exibe quais variáveis estão definidas e quais testes serão executados ou ignorados. Pode ser executado de qualquer diretório; localiza a raiz do projeto automaticamente. Inclui também `RUN_ODBC_BURST_TESTS` e o estado de `sql_queue_burst_test` (DSN RPC + query longa).

## Executar Testes

```bash
# Todos os testes de integração
flutter test test/integration/

# API tests
flutter test test/infrastructure/external_services/api_test.dart

# Hub Socket.IO smoke (RUN_LIVE_HUB_TESTS, E2E_HUB_URL, E2E_HUB_TOKEN)
flutter test test/integration/hub_socket_live_e2e_test.dart

# ODBC streaming
flutter test test/integration/odbc_streaming_live_integration_test.dart

# ODBC SQL Anywhere TOP/START AT (DSN deve parecer SQL Anywhere)
flutter test test/integration/odbc_sql_anywhere_top_start_at_live_test.dart

# ODBC RPC sql.execute / sql.executeBatch (DSN: ODBC_E2E_RPC_DSN ou fallback Anywhere → SQL Server → PostgreSQL)
flutter test test/integration/odbc_rpc_execute_coverage_live_e2e_test.dart

# ODBC DML performance — insert/update/delete em lote (opt-in: ODBC_E2E_DML_PERF_TESTS=true e DSN RPC)
flutter test test/integration/odbc_dml_perf_live_e2e_test.dart

# ODBC DML carga massiva (~50k, chunked batches; opt-in: ODBC_E2E_DML_BULK_TESTS=true)
flutter test test/integration/odbc_dml_bulk_load_live_e2e_test.dart

# Fila SQL: burst paralelo + saturação (opt-in: RUN_ODBC_BURST_TESTS=true, DSN RPC e query longa)
flutter test test/integration/sql_queue_burst_test.dart

# Lock / concorrência (opt-in: ODBC_RUN_LOCK_CONTENTION_TESTS=true e DSN)
flutter test test/integration/odbc_lock_contention_live_integration_test.dart

# Recuperação de conexão (quando aplicável ao ambiente)
flutter test test/integration/connection_recovery_integration_test.dart
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
- `test/integration/hub_socket_live_e2e_test.dart` – smoke Socket.IO com `SocketDataSource` (opt-in)
- `test/integration/odbc_dml_perf_live_e2e_test.dart` – desempenho DML em lote (opt-in)
- `test/integration/odbc_dml_bulk_load_live_e2e_test.dart` – carga massiva (ex.: 50k linhas, opt-in)
- `test/integration/sql_queue_burst_test.dart` – burst paralelo na fila ODBC (opt-in: `RUN_ODBC_BURST_TESTS`)
- `.env.example` – template das variáveis E2E/integração (benchmarks podem acrescentar muitas chaves no `.env` local)
- `docs/database/sql_anywhere_connection.md` – formato de connection string SQL Anywhere

## Notas

- **`.env` nos testes Flutter:** O `E2EEnv` localiza a raiz do projeto (sobe diretórios até achar `pubspec.yaml`) e lê `.env` via sistema de arquivos + `flutter_dotenv.loadFromString` (não usa assets do `pubspec.yaml`).
- **check_e2e_env vs E2EEnv:** O script `tool/check_e2e_env.dart` roda com `dart run` (sem `dart:ui`) e usa um parser de linhas equivalente ao caso comum `chave=valor` (primeiro `=` separa chave e valor). Para entradas muito exóticas, a fonte de verdade nos testes é o `E2EEnv`.
- **Benchmarks (fora do E2EEnv):** variáveis como `ODBC_E2E_BENCHMARK_*`, `SOCKET_TRANSPORT_BENCHMARK_*`, `PAYLOAD_FRAME_BENCHMARK_*`, etc., são usadas por testes de performance/regressão (por exemplo em `test/live/` e ficheiros `*benchmark*`). Não entram no `E2EEnv` nem no `check_e2e_env.dart`; o contrato fica no próprio teste. Podes mantê-las no `.env` local com uma lista longa; o `.env.example` cobre o conjunto **E2E/integração**; um `.env` de dev pode alargar isso.
