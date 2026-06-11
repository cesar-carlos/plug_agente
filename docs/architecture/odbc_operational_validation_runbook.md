# ODBC Operational Validation Runbook

Este runbook descreve **como validar** o eixo ODBC/performance apos rollout.
Nao guarde resultados aqui — o wrapper PowerShell ja gera uma worksheet
timestampada e versionada por execucao em `artifacts/odbc_validation/`.

## Quando rodar

- Apos mudanca em `odbc_fast`, `OdbcConnectionPool`, `SqlExecutionQueue`,
  `OdbcDatabaseGateway` ou tuning de runtime.
- Antes de aumentar pool/workers em producao.
- Quando snapshots de `agent.getHealth` mostrarem `pending_saturation_percent`
  alto, `sql_queue.rejections_total` crescente ou `pool.fallbacks_total`
  inesperado.
- Apos habilitar `ODBC_RESULT_ENCODING=columnar*` em qualquer ambiente.

## Perguntas que a validacao deve responder

- O app continua saudavel sob carga normal?
- A fila SQL rejeita de forma controlada quando saturada?
- O worker pool async do `odbc_fast` esta sub/equilibrado/superdimensionado?
- O pool adaptativo esta usando o caminho nativo somente em drivers elegiveis
  (SQL Server, PostgreSQL)?
- `service.streamQuery` continua usando o caminho batched-first do
  `odbc_fast` sem regressao no workload local?
- O runtime local do `odbc_fast` expoe os simbolos necessarios para
  `columnarCompressed`?
- Ha sinais de gargalo no banco/driver em vez do app?

## Wrapper unico (recomendado)

No Windows:

```powershell
python tool/run_odbc_operational_validation.py
python tool/run_odbc_operational_validation.py --all
```

Cada execucao gera uma subpasta timestampada em `artifacts/odbc_validation/`
contendo:

| Arquivo | Conteudo |
| --- | --- |
| `odbc_operational_validation_report.md` | Worksheet em Markdown com ambiente, tuning efetivo e placeholders para preenchimento |
| `health_snapshot_template.json` | Baseline do shape atual de `agent.getHealth` (gerado por `dart run tool/export_odbc_health_snapshot_template.dart`, alinhado a `HealthService` e `rpc.result.agent-get-health.schema.json`) |
| `odbc_runtime.log` | Smoke do runtime `odbc_fast` (sem DSN) |
| `preflight.log` | Resultado de `tool/check_e2e_env.dart` |
| `smoke.log` | Smoke ODBC (`odbc_queued_gateway_smoke_live_e2e_test.dart`) |
| `burst.log` | Burst da fila SQL (`sql_queue_burst_test.dart`, opt-in `RUN_ODBC_BURST_TESTS=true`) |
| `benchmark.log` | `async_concurrency_benchmark.dart` |
| `streaming_benchmark.log` | `streaming_performance_benchmark.dart` |
| `driver_matrix_*.log` | Benchmark async + streaming por driver configurado |
| `health_burst_*_before/after.json` | Snapshots reais de `agent.getHealth` antes/depois do burst |

Sem `-All`, o wrapper executa preflight e gera o template; voce decide quais
etapas rodar.

## Passos manuais (apenas se o wrapper nao for opcao)

1. Smoke runtime `odbc_fast` (sem DSN):

   ```powershell
   dart run tool/check_odbc_fast_runtime.dart --require-columnar-compressed
   ```

2. Preflight de variaveis E2E:

   ```powershell
   dart run tool/check_e2e_env.dart
   ```

3. Smoke com query simples:

   ```powershell
   flutter test test/integration/odbc_queued_gateway_smoke_live_e2e_test.dart
   ```

4. Coletar snapshot de `agent.getHealth` antes/depois do burst.

5. Burst opt-in:

   ```powershell
   $env:RUN_ODBC_BURST_TESTS='true'
   flutter test test/integration/sql_queue_burst_test.dart
   ```

6. Benchmark async ODBC:

   ```powershell
   python tool/odbc_async_benchmark.py
   ```

7. Benchmark streaming:

   ```powershell
   python tool/odbc_streaming_benchmark.py
   ```

8. Driver matrix (se houver mais de um DSN configurado):

   ```powershell
   python tool/odbc_driver_matrix_benchmark.py
   ```

## Como ler o snapshot de health

Campos mais relevantes (nomes atuais do contrato `agent.getHealth`):

- `secure_storage.odbc_available`, `hub_auth_available`,
  `client_tokens_available`, `degraded` — disponibilidade de
  `flutter_secure_storage` por dominio (ODBC, hub auth, client tokens).
- `odbc_runtime_tuning.async_worker_count`,
  `odbc_runtime_tuning.async_max_pending_requests`,
  `odbc_runtime_tuning.result_encoding`
- `pool.effective_strategy`, `pool.native_eligible`, `pool.active_count`,
  `pool.lease_active_count`, `pool.native_active_count`, `pool.fallbacks_total`
- `pool.native_compatible_acquire_success_total`
- `streaming.from_db_responses_total`, `streaming.cancel_requests_total`,
  `streaming.backpressure_cancels_total`, `streaming.active_streams`
- `prepared.cache_hit_total`, `prepared.cache_miss_total`, `prepared.prepare_p95_ms`
- `batch.transactional_native_pool_total`,
  `batch.transactional_native_pool_fallback_total`,
  `batch.bulk_insert_recommended_total`, `batch.bulk_insert_routed_total`
- `sql_queue.current_size`, `sql_queue.rejections_total`,
  `sql_queue.timeouts_total`, `sql_queue.timeouts_after_worker_started_total`,
  `sql_queue.p95_wait_time_ms`
- Worker-kind slots: `sql_queue.active_streaming_workers` /
  `max_streaming_workers`, `active_batch_workers`, `active_long_query_workers`,
  `active_non_query_workers` (e respectivos `max_*`)
- `queries.p95_latency_ms`, `queries.p99_latency_ms`
- `timeouts.pool_total`, `timeouts.cancel_success_total`

`async_worker_pool.near_pending_limit=true` (quando presente no payload ODBC
nativo) indica que o worker pool interno do `odbc_fast` esta proximo do teto
configurado. `timeouts_after_worker_started_total` > 0 sinaliza risco de
**ghost query** — ver `docs/testing/sql_queue_concurrency_tests.md`.

## Decisao de tuning

Regras praticas:

- Aumente `ODBC_ASYNC_MAX_PENDING_REQUESTS` se `pending_requests` saturar e o
  banco ainda tiver folga.
- Aumente `SQL_QUEUE_MAX_SIZE` se a fila rejeitar cedo demais em bursts
  esperados, sem sinal de gargalo no banco.
- Aumente `ODBC_POOL_SIZE` e `SQL_QUEUE_MAX_WORKERS` apenas se houver
  beneficio real em throughput **e** sem piorar p95/p99.
- Use `batch.bulk_insert_recommended_total` para identificar batches grandes
  de `INSERT` que devem migrar para `sql.bulkInsert` antes de aumentar
  concorrencia.
- Nao habilite `ResultEncoding.columnar` ou `columnarCompressed` sem
  benchmark dedicado e smoke de runtime passando.
- Nao introduza multi-`ServiceLocator` ou pools customizados sem evidencia
  forte de que o worker pool suportado foi esgotado (ver
  `odbc_worker_evaluation_criteria.md`).

## Cross-references

- Tuning vigente: `performance_reliability_improvements.md`
- Criterios de avaliacao do worker pool: `odbc_worker_evaluation_criteria.md`
- Quick start operacional: `QUICKSTART.md`
- Concorrencia da fila SQL: `docs/testing/sql_queue_concurrency_tests.md`
- Variaveis E2E: `docs/testing/e2e_setup.md`
