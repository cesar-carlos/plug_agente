# Performance and Reliability Improvements

Atualizado: 2026-05-14

Este documento registra o estado atual das melhorias de performance e
confiabilidade do caminho ODBC. O foco atual e `odbc_fast 3.8.1`: usar o
worker pool assincrono interno do pacote por padrao e habilitar o pool
adaptativo para drivers elegiveis com fallback seguro.

## Status

| Area | Status | Observacao |
| --- | --- | --- |
| `SqlExecutionQueue` / `QueuedDatabaseGateway` | Implementado | O fluxo RPC usa fila bounded com backpressure e metricas. |
| `OdbcConnectionPool` lease-based | Implementado | Continua sendo fallback seguro e caminho obrigatorio para SQL Anywhere. |
| Pool warm-up | Implementado | Warm-up respeita a estrategia efetiva do pool adaptativo/lease. |
| Circuit breaker | Implementado | Falhas repetidas de conexao deixam de consumir timeouts completos por request. |
| Retry com backoff exponencial | Implementado | `RetryManager` permanece como mecanismo padrao de retry. |
| Bulk insert | Implementado | `sql.bulkInsert` usa suporte nativo do pacote quando aplicavel. |
| Streaming | Implementado | O app chama `streamQuery`; o `odbc_fast` tenta `streamQueryBatched` internamente antes do fallback. |
| Worker pool assincrono `odbc_fast` | Implementado | Default configuravel: `min(poolSize persistido, CPU cores)`, minimo 1. |
| Adaptive/native pool | Implementado | Habilitado por default para SQL Server/PostgreSQL elegiveis; SQL Anywhere fica fora. |
| Result encoding columnar | Opt-in implementado | Row-major continua default compativel. Columnar/columnarCompressed exigem flag e benchmark. |

## ODBC Fast 3.8.1

O bootstrap do runtime inicializa `odbc.ServiceLocator` com:

- `useAsync: true`
- `asyncWorkerCount`: calculado a partir do `poolSize` persistido em `OdbcConnectionSettings` e do numero de CPUs
- `asyncMaxPendingRequests`: default `poolSize * 4`
- `asyncBackpressureMode: failFast`

`failFast` e intencional: a fila `SqlExecutionQueue` e a fronteira visivel de
backpressure do app. Os presets `OdbcUsageProfile` do pacote continuam uteis
como referencia, mas o app usa tuning explicito para alinhar workers ao pool
persistido pelo usuario.

Variaveis de ambiente:

| Variavel | Default | Regra |
| --- | --- | --- |
| `ODBC_ASYNC_WORKER_COUNT` | `min(poolSize, CPU cores)` | Deve ser positiva e e limitada ao mesmo teto. Valor invalido ou `0` e ignorado. |
| `ODBC_ASYNC_MAX_PENDING_REQUESTS` | `poolSize * 4` | Deve ser positiva. Valor invalido ou `0` e ignorado. |
| `ODBC_RESULT_ENCODING` | `rowMajor` | Aceita `rowMajor`, `columnar` e `columnarCompressed`; so afeta queries parametrizadas. |
| `ODBC_POOL_SIZE` | `4` | Define o tamanho do pool lease-based quando nao ha valor persistido. |

O `poolSize` persistido pelo usuario vence o default de `ConnectionConstants`.
Isso evita configurar workers com base em um valor diferente daquele usado pelo
pool real de conexoes.

## Observability

O payload de diagnostico ODBC inclui `runtime_tuning`, `sql_queue` e
`async_worker_pool`. Isso permite comparar, no mesmo snapshot, a fila do app e
o worker pool interno do pacote.

`runtime_tuning` registra o que foi usado no bootstrap:

- `pool_size`
- `processor_count`
- `async_worker_count`
- `async_max_pending_requests`
- `async_backpressure_mode`
- `result_encoding`

`async_worker_pool` inclui:

- `worker_count`
- `max_pending_requests`
- `pending_requests`
- `pending_saturation_percent`
- `near_pending_limit`
- `active_requests`
- `total_routed`
- `completed`
- `failed`
- `timeouts`
- `fallbacks_to_blocking`
- estatisticas por worker quando o pacote fornece esses dados

`sql_queue` inclui tamanho atual, maximo observado, workers ativos, rejeicoes,
timeouts e tempos de espera da fila.

Quando `pending_requests` chega perto de `max_pending_requests`, o app registra
warning estruturado com sugestao de aumentar `ODBC_ASYNC_MAX_PENDING_REQUESTS`
ou reduzir concorrencia upstream.

Essa exposicao fica no diagnostico ODBC do RPC. O `HealthService` so deve ser
expandido quando houver caminho direto consumido pela UI; o tuning de runtime
tambem e exposto ali para facilitar suporte operacional.

## Result Encoding

Nao habilite `ResultEncoding.columnar` por padrao sem benchmark. O app mantem
`rowMajor` como default compativel e aceita opt-in apenas por ambiente para
workloads com muitas linhas e tipos estaveis.

Use:

```env
ODBC_RESULT_ENCODING=rowMajor|columnar|columnarCompressed
```

A aplicacao fica restrita aos caminhos parametrizados que ja usam
`executeQueryParams`. Antes de ativar `columnarCompressed`, valide os exports
nativos locais:

```powershell
dart run tool/check_odbc_fast_runtime.dart --require-columnar-compressed
```

## Validacao

Testes obrigatorios para mudancas neste eixo:

```bash
flutter test test/core/constants/connection_constants_test.dart
flutter test test/infrastructure/metrics/odbc_native_metrics_service_test.dart
flutter test test/application/services/health_service_test.dart
flutter analyze
```

Validacao manual/opt-in:

```powershell
dart run D:\Developer\dart_odbc_fast\example\async_concurrency_benchmark.dart
```

Ou pelo wrapper local:

```powershell
.\tool\odbc_async_benchmark.ps1
```

Para validar streaming batched-first do `odbc_fast 3.8.1`:

```powershell
.\tool\odbc_streaming_benchmark.ps1
```

O wrapper usa a query longa configurada para o driver quando
`ODBC_STREAM_BENCH_QUERY` nao estiver definido. Para comparar SQL Anywhere, SQL
Server e PostgreSQL em uma unica rodada, use:

```powershell
.\tool\odbc_driver_matrix_benchmark.ps1
```

No Windows, o fluxo consolidado de validacao operacional pode ser executado via:

```powershell
.\tool\run_odbc_operational_validation.ps1
.\tool\run_odbc_operational_validation.ps1 -All
```

Tambem rode `RUN_ODBC_BURST_TESTS=true` com DSN representativo e query longa
para comparar throughput, p95/p99, queue wait, pending requests dos workers e
timeouts antes/depois.

O fluxo `-All` grava snapshots `health_burst_*_before/after.json` e logs
`driver_matrix_*` no diretorio da validacao. Use
`batch.bulk_insert_recommended_total` para identificar batches grandes de
`INSERT` que devem migrar para `sql.bulkInsert`.

Para registrar os resultados observados e a decisao final de tuning, use
`docs/architecture/odbc_operational_validation_runbook.md`.
