# ODBC Operational Validation Runbook

Data de referencia: 2026-05-21

Este runbook registra a validacao operacional do eixo ODBC/performance apos o
rollout das quick wins. Use este arquivo para anotar resultados reais de smoke,
burst e benchmark antes de ajustar tuning em producao ou homologacao.

## Objetivo

Responder, com dados, a estas perguntas:

- O app continua saudavel sob carga normal?
- A fila SQL rejeita de forma controlada quando saturada?
- O worker pool async do `odbc_fast` esta subdimensionado, equilibrado ou
  superdimensionado?
- Ha sinais de gargalo no banco/driver em vez do app?

## Ambiente Validado

Preencha antes de rodar:

| Campo | Valor |
| --- | --- |
| Data/hora | |
| Ambiente | |
| Operador | |
| Driver / banco | |
| DSN usado | |
| Query smoke | |
| Query longa | |
| Build / commit | |

## Configuracao Efetiva

Anote os valores vigentes:

```env
ODBC_POOL_SIZE=
ODBC_ASYNC_WORKER_COUNT=
ODBC_ASYNC_MAX_PENDING_REQUESTS=
SQL_QUEUE_MAX_SIZE=
SQL_QUEUE_MAX_WORKERS=
SQL_QUEUE_TIMEOUT_SEC=
CIRCUIT_BREAKER_FAILURE_THRESHOLD=
CIRCUIT_BREAKER_RESET_SEC=
```

## Sequencia Recomendada

0. Rodar preflight de ambiente e confirmar DSN/query longa.
1. Rodar smoke test com query simples.
2. Coletar um snapshot de `agent.getHealth`.
3. Rodar burst test opt-in.
4. Coletar novo snapshot de `agent.getHealth`.
5. Rodar benchmark async ODBC.
6. Comparar resultados e decidir tuning.

Atalho opcional no Windows:

```powershell
.\tool\run_odbc_operational_validation.ps1
```

O script gera uma worksheet Markdown em `artifacts/odbc_validation/` com
ambiente, tuning efetivo e placeholders para snapshots/resultados. Para
executar tudo em sequencia:

```powershell
.\tool\run_odbc_operational_validation.ps1 -All
```

Cada execucao cria uma subpasta timestampada com:

- `odbc_operational_validation_report.md`
- `health_snapshot_template.json`
- `preflight.log`
- `smoke.log`
- `burst.log`
- `benchmark.log`

Os arquivos de log so aparecem para as etapas realmente executadas.
O template JSON e um baseline local do shape atual de `agent.getHealth`; ainda
vale coletar snapshots reais antes/depois do burst quando o app estiver em
execucao.

## 0. Preflight

Comando:

```powershell
dart run tool/check_e2e_env.dart
```

Confirmar no output:

- `ODBC_E2E_RPC_DSN` ou fallback ODBC valido
- `ODBC_INTEGRATION_LONG_QUERY*` definido
- `RUN_ODBC_BURST_TESTS=true` quando for rodar burst

Registrar:

| Item | Valor |
| --- | --- |
| Preflight passou? | |
| DSN efetivo resolvido | |
| Query longa efetiva | |
| Observacoes | |

## 1. Smoke

Referencias:

- `docs/testing/e2e_setup.md`
- `docs/testing/sql_queue_concurrency_tests.md`

Comandos:

```powershell
# Ajuste o DSN/query no .env local antes de executar
flutter test test/integration/odbc_queued_gateway_smoke_live_e2e_test.dart
```

Registrar:

| Medida | Valor |
| --- | --- |
| Passou? | |
| Latencia observada | |
| Erros | |
| Observacoes | |

## 2. Burst

Comandos:

```powershell
$env:RUN_ODBC_BURST_TESTS='true'
flutter test test/integration/sql_queue_burst_test.dart
```

Registrar:

| Medida | Valor |
| --- | --- |
| Passou? | |
| Requests totais | |
| Rejections | |
| Timeouts | |
| Recuperou para fila/pool zerados? | |
| Observacoes | |

## 3. Benchmark Async ODBC

Comandos:

```powershell
dart run D:\Developer\dart_odbc_fast\example\async_concurrency_benchmark.dart
```

Ou via wrapper do repo:

```powershell
.\tool\odbc_async_benchmark.ps1
```

Registrar:

| Medida | Valor |
| --- | --- |
| Throughput | |
| P95 | |
| P99 | |
| Pending requests max | |
| Near pending limit? | |
| Timeouts | |
| Observacoes | |

## Snapshot de Health

Cole aqui um snapshot representativo antes e depois do burst:

```dart
final health = await getIt<HealthService>().getHealthStatusAsync();
print(JsonEncoder.withIndent('  ').convert(health));
```

Campos mais importantes:

- `odbc_runtime_tuning.async_worker_count`
- `odbc_runtime_tuning.async_max_pending_requests`
- `pool.active_count`
- `pool.fallbacks_total`
- `sql_queue.current_size`
- `sql_queue.rejections_total`
- `sql_queue.timeouts_total`
- `sql_queue.p95_wait_time_ms`
- `queries.p95_latency_ms`
- `queries.p99_latency_ms`
- `timeouts.pool_total`

### Snapshot Antes do Burst

```json
{}
```

### Snapshot Depois do Burst

```json
{}
```

### Leitura Rapida

| Campo | Antes | Depois | Observacao |
| --- | --- | --- | --- |
| `odbc_runtime_tuning.async_worker_count` | | | |
| `odbc_runtime_tuning.async_max_pending_requests` | | | |
| `pool.active_count` | | | |
| `pool.fallbacks_total` | | | |
| `sql_queue.rejections_total` | | | |
| `sql_queue.timeouts_total` | | | |
| `sql_queue.p95_wait_time_ms` | | | |
| `queries.p95_latency_ms` | | | |
| `queries.p99_latency_ms` | | | |
| `timeouts.pool_total` | | | |

## Decisao de Tuning

Use esta regra pratica:

- Aumente `ODBC_ASYNC_MAX_PENDING_REQUESTS` se `pending_requests` saturar e o
  banco ainda tiver folga.
- Aumente `SQL_QUEUE_MAX_SIZE` se a fila rejeitar cedo demais em bursts
  esperados, sem sinal de gargalo no banco.
- Aumente `ODBC_POOL_SIZE` e `SQL_QUEUE_MAX_WORKERS` apenas se houver beneficio
  real em throughput e sem piorar p95/p99.
- Nao habilite `ResultEncoding.columnar` sem benchmark dedicado.
- Nao introduza multi-`ServiceLocator` ou pools customizados sem evidencia
  forte de que o worker pool suportado foi esgotado.

## Resultado Final

Preencha ao concluir:

| Item | Resultado |
| --- | --- |
| Status final | |
| Mudancas de tuning aprovadas | |
| Mudancas rejeitadas | |
| Riscos observados | |
| Proxima revisao | |
