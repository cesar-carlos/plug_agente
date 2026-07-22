# Performance and Reliability Improvements

Estado atual das melhorias de performance/confiabilidade do caminho ODBC
(`odbc_fast 3.8.1`). **Comportamento runtime** (pool, failFast, workers,
transacoes): [`docs/runtime/odbc_pool_and_transactions.md`](../runtime/odbc_pool_and_transactions.md).
**Tuning operacional**: [`QUICKSTART.md`](QUICKSTART.md).

## Status

| Area | Status | Observacao |
| --- | --- | --- |
| `SqlExecutionQueue` / `QueuedDatabaseGateway` | Implementado | Fila bounded com backpressure e metricas. |
| `OdbcConnectionPool` lease-based | Implementado | Fallback seguro; obrigatorio para SQL Anywhere. |
| Pool warm-up | Implementado | Respeita estrategia adaptativo/lease. |
| Circuit breaker | Implementado | Evita timeouts completos em falhas repetidas. |
| Retry com backoff exponencial | Implementado | `RetryManager`. |
| Bulk insert | Implementado | `sql.bulkInsert` nativo quando aplicavel. |
| Streaming | Implementado | `streamQuery` → `streamQueryBatched` com fallback. |
| Worker pool assincrono `odbc_fast` | Implementado | Default `min(poolSize, CPU cores)`. |
| Adaptive/native pool | Implementado | Default on para SQL Server/PostgreSQL; SQL Anywhere fora. |
| Result encoding columnar | Opt-in | Default `rowMajor`; columnar exige flag + benchmark. |

## Runtime e env

Bootstrap: `useAsync: true`, workers derivados do `poolSize` persistido,
`asyncBackpressureMode: failFast` (fila do app e a fronteira de backpressure).

Tabela completa de `ODBC_ASYNC_*`, `ODBC_POOL_SIZE`, `ODBC_RESULT_ENCODING` e
regras de override: [`runtime/odbc_pool_and_transactions.md`](../runtime/odbc_pool_and_transactions.md).
Mapa DSN por driver: [`database/readme.md`](../database/readme.md).

## Observability

Diagnostico ODBC expoe `runtime_tuning`, `sql_queue` e `async_worker_pool`
(pending, saturation, routed/completed/failed). Warning estruturado quando
`pending_requests` aproxima `max_pending_requests`.

## Result Encoding

Default `rowMajor`. Opt-in:

```env
ODBC_RESULT_ENCODING=rowMajor|columnar|columnarCompressed
```

Antes de `columnarCompressed`:

```powershell
dart run tool/odbc/check_odbc_fast_runtime.dart --require-columnar-compressed
```

## Validacao

```bash
flutter test test/core/constants/connection_constants_test.dart
flutter test test/infrastructure/metrics/odbc_native_metrics_service_test.dart
flutter test test/application/services/health_service_test.dart
flutter analyze
```

Benchmarks / runbook:

```powershell
python tool/benchmarks/odbc_async_benchmark.py
python tool/benchmarks/odbc_streaming_benchmark.py
python tool/benchmarks/odbc_driver_matrix_benchmark.py
python tool/odbc/run_odbc_operational_validation.py --all
```

Registrar resultados em
[`odbc_operational_validation_runbook.md`](odbc_operational_validation_runbook.md).
E2E ODBC: [`docs/testing/e2e_odbc.md`](../testing/e2e_odbc.md).
