# ODBC Worker Evaluation Criteria

Atualizado: 2026-05-14

Este documento separa dois assuntos que nao devem ser misturados:

- **Worker pool interno do `odbc_fast`**: suporte oficial do pacote 3.8.1.
  Agora e o default do app, configurado por `ODBC_ASYNC_WORKER_COUNT` e
  `ODBC_ASYNC_MAX_PENDING_REQUESTS`.
- **Arquitetura customizada multi-`ServiceLocator`/multi-pool**: continuamos
  fora de escopo. Ela cria roteamento, cancelamento, lifecycle e metricas por
  pool que o app ainda nao precisa manter.

## Runtime Atual

- `odbc.ServiceLocator.initialize(useAsync: true, asyncWorkerCount: ..., asyncMaxPendingRequests: ..., asyncBackpressureMode: failFast)`
- `asyncWorkerCount` default: `min(poolSize persistido, CPU cores)`, minimo 1
- `asyncMaxPendingRequests` default: `poolSize * 4`
- Pool adaptativo fica habilitado por default para drivers elegiveis
- `OdbcConnectionPool` lease-based continua sendo fallback seguro
- SQL Anywhere permanece fora do native pool

## Quando Ajustar o Worker Pool Interno

Ajuste apenas depois de medir:

| Sinal | Acao sugerida |
| --- | --- |
| `pending_requests` cresce e CPU/driver ainda tem folga | Aumentar `ODBC_ASYNC_WORKER_COUNT`, respeitando o teto `min(poolSize, CPU cores)`. |
| Rejeicoes `failFast` aparecem em bursts esperados | Aumentar `ODBC_ASYNC_MAX_PENDING_REQUESTS` ou reduzir concorrencia upstream. |
| Timeouts crescem junto com `active_requests` alto | Verificar query, driver e banco antes de aumentar workers. |
| Queue wait do app cresce mas workers ficam ociosos | Ajustar `SqlExecutionQueue` e pool lease-based, nao o worker pool interno. |

## Fora de Escopo: Multi-ServiceLocator Customizado

Nao implementar multiplos `ServiceLocator` com pools separados sem evidencia
forte. Essa arquitetura so deve ser reavaliada se todos os criterios abaixo
forem verdadeiros:

- o worker pool interno do pacote ja foi medido e ajustado;
- banco e driver nao sao o gargalo;
- `SqlExecutionQueue` e `OdbcConnectionPool` estao estaveis;
- cancelamento, retry, circuito e metricas ja conseguem identificar o worker
  responsavel por cada request;
- benchmark mostra ganho relevante que justifica a complexidade.

## Metricas Obrigatorias

O diagnostico ODBC deve registrar:

- `runtime_tuning.pool_size`
- `runtime_tuning.async_worker_count`
- `runtime_tuning.async_max_pending_requests`
- `runtime_tuning.async_backpressure_mode`
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
- estatisticas por worker quando disponiveis

Compare essas metricas com:

- `sql_queue.current_size`, workers ativos, rejeicoes e timeouts da fila SQL;
- timeouts de acquire do pool lease-based;
- throughput e p95/p99 por metodo RPC;
- CPU e memoria do processo;
- erros especificos de driver (`invalid connection id`, buffer, cancelamento).

`near_pending_limit=true` indica que o worker pool interno esta perto do limite
configurado de requests pendentes. Trate como sinal para medir throughput,
latencia p95/p99 e rejeicoes antes de aumentar limites.

## Driver Matrix

| Driver family | Recomendacao |
| --- | --- |
| SQL Anywhere | Lease-based pool como default. Nao usar native pool global. Validar qualquer aumento de concorrencia com burst e soak test. |
| SQL Server | Bom candidato para benchmarks de throughput, mantendo rollback por env/config. |
| PostgreSQL | Validar streaming, paginacao, lock timeout e cancelamento antes de aumentar agressivamente. |

## Benchmark

Use DSN representativo e compare baseline/candidato:

```powershell
dart run D:\Developer\dart_odbc_fast\example\async_concurrency_benchmark.dart
```

Ou use o wrapper do repo:

```powershell
.\tool\odbc_async_benchmark.ps1
```

Para comparar streaming legado e batched streaming:

```powershell
.\tool\odbc_streaming_benchmark.ps1
```

Para comparar SQL Anywhere, SQL Server e PostgreSQL configurados:

```powershell
.\tool\odbc_driver_matrix_benchmark.ps1
```

Tambem rode o burst do app:

```powershell
$env:RUN_ODBC_BURST_TESTS='true'
flutter test test/integration/sql_queue_burst_test.dart
```

No Windows, para consolidar preflight, testes e worksheet de evidencias:

```powershell
.\tool\run_odbc_operational_validation.ps1
.\tool\run_odbc_operational_validation.ps1 -All
```

O modo `-All` grava snapshots `health_burst_*_before/after.json` e logs
`driver_matrix_*`. Use esses artefatos antes de aumentar workers/pool e antes
de aceitar o pool nativo em SQL Server/PostgreSQL.

Rollback imediato se throughput melhorar pouco enquanto p95/p99, timeouts,
falhas de cancelamento ou erros de driver piorarem.

Depois de comparar baseline/candidato, registre os numeros e a decisao de
tuning em `docs/architecture/odbc_operational_validation_runbook.md`.
