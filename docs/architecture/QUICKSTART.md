# Quick Start: Tuning e Troubleshooting ODBC

Guia operacional curto. Os defaults ja estao ativos; nenhuma configuracao e
necessaria para funcionamento basico. Comportamento runtime (pool,
backpressure, retry, quarentena, streaming, bulk):
[`docs/runtime/odbc_pool_and_transactions.md`](../runtime/odbc_pool_and_transactions.md).

## Tuning opcional

1. Criar `.env` a partir de `.env.example` (se nao existir).
2. Ajustar somente o necessario. Defaults atuais:

```env
ODBC_POOL_SIZE=8
# ODBC_ASYNC_MAX_PENDING_REQUESTS e auto: max(ODBC_POOL_SIZE * 4, SQL_QUEUE_MAX_WORKERS)
SQL_QUEUE_MAX_SIZE=16      # manter <= ODBC_ASYNC_MAX_PENDING_REQUESTS
SQL_QUEUE_MAX_WORKERS=8    # default = ODBC_POOL_SIZE
SQL_QUEUE_TIMEOUT_SEC=5    # so o tempo de espera na fila
CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
CIRCUIT_BREAKER_RESET_SEC=30
```

Sugestoes por carga (mesmas do `.env.example`):

- Carga leve (< 10 req/s): `ODBC_POOL_SIZE=4`, `SQL_QUEUE_MAX_SIZE=8`
- Carga alta (> 50 req/s): `ODBC_POOL_SIZE=16`, `SQL_QUEUE_MAX_SIZE=32`

O tamanho do pool salvo nas configuracoes do app tem precedencia; o
`ODBC_POOL_SIZE` so vale quando nao ha valor persistido (limite 1–20).

3. Reiniciar a aplicacao (as variaveis de ambiente sao lidas no boot).

## Verificar que esta funcionando

Logs de startup:

```
[plug_dependency_registrar] SQL queue initialized: maxSize=16, maxWorkers=8, batchWorkers=2, longQueryWorkers=2, streamingWorkers=2, nonQueryWorkers=4
[connection_pool] Warming up connection pool with 4 connections
[connection_pool] Pool warm-up completed: 4/4 connections
```

Em SQL Server/PostgreSQL com pool nativo, o warm-up aparece como
`Warming up native pool with N connections`.

Circuit breaker (apenas se houver falhas de conexao):

```
[circuit_breaker] Connection failure recorded (3/5)
[circuit_breaker] Circuit breaker OPENED after 5 failures
```

Fila cheia:

```
[sql_execution_queue] SQL request REJECTED (queue full)
```

## Monitoramento

Use `agent.getHealth` (ou `getIt<HealthService>().getHealthStatusAsync()`).
Contrato: `docs/communication/schemas/rpc.result.agent-get-health.schema.json`.
Leitura campo a campo: secao "Como ler o snapshot de health" em
[`odbc_operational_validation_runbook.md`](odbc_operational_validation_runbook.md).

`status` vira `degraded` quando `secure_storage.degraded` e true ou a fila SQL
esta perto de saturar.

## Sinais de alerta

### Rejeicoes da fila altas

Sintoma: `SQL request REJECTED (queue full)` e `sql_queue.rejections_total`
acima de ~5% das requisicoes.

Acao: aumentar `SQL_QUEUE_MAX_SIZE` (mantendo `<= ODBC_ASYNC_MAX_PENDING_REQUESTS`);
aumentar `ODBC_POOL_SIZE`/`SQL_QUEUE_MAX_WORKERS` somente se o banco tiver
folga. Batches grandes de `INSERT` (`batch.bulk_insert_recommended_total`)
devem migrar para `sql.bulkInsert`.

### Fila sempre cheia

Sintoma: `sql_queue.current_size` igual a `max_size` e `active_workers` igual a
`max_workers` de forma sustentada.

Significa demanda maior que a capacidade. Imediato: aumentar pool e workers
juntos. Medio prazo: otimizar queries lentas.

### Circuit breaker abrindo com frequencia

O breaker conta apenas falhas de conexao (conexao perdida, worker ODBC caido,
falha de connect). Pressao local (fila cheia, pool esgotado, timeout de fila) e
falha de autenticacao nao contam. Em half-open, uma unica sonda passa; as
demais falham rapido.

Causas comuns: banco indisponivel, connection string incorreta, rede instavel.
Verificar conectividade e logs do banco antes de aumentar
`CIRCUIT_BREAKER_FAILURE_THRESHOLD`.

### Latencia alta (p95 > 500 ms)

Investigar queries lentas, indices e contencao no banco antes de aumentar
`ODBC_POOL_SIZE`. `sql_queue.timeouts_after_worker_started_total` > 0 indica
risco de ghost query (ver `docs/testing/sql_queue_concurrency_tests.md`).

## Testes de carga

```powershell
python tool/odbc/run_odbc_operational_validation.py        # preflight + worksheet
python tool/odbc/run_odbc_operational_validation.py --all  # smoke, burst e benchmarks
python tool/benchmarks/run_benchmark_suite.py              # suite (carrega .env)
```

Esperado no burst: rejeicoes controladas, workers voltam a 0 e o sistema se
recupera em poucos segundos. Detalhes em
[`odbc_operational_validation_runbook.md`](odbc_operational_validation_runbook.md)
e `docs/testing/sql_queue_concurrency_tests.md`.

## Troubleshooting

### "Circuit breaker open" com o banco no ar

O breaker ainda esta no intervalo de reset. Aguardar `CIRCUIT_BREAKER_RESET_SEC`
(default 30 s) para o half-open. Salvar ou ativar a configuracao do banco
tambem reseta os breakers daquela connection string.

### "Native ODBC pool is being recycled after an unsafe execution"

Pool nativo em quarentena (`native_pool_quarantined`, retryable). O pool
adaptativo usa lease/direto ate a recuperacao. Se o log mostrar
`native_quarantine_slow_recovery` sem `quarantine_recovered` depois, investigar
driver e causas de timeout/cancelamento.

### Warm-up do pool falhando

Sintoma: `[connection_pool] Warm-up connection 1/4 failed`. O app continua
funcionando (warm-up e opcional). Verificar connection string e conectividade.

### "SQL execution queue disposed before request could be processed"

Esperado durante o encerramento do app. Durante operacao normal indica bug de
lifecycle.

## Logs para debug

- Startup: `[plug_dependency_registrar]` (fila), `[connection_pool]` (warm-up),
  `[bootstrap_service_locator]` (worker pool async).
- Operacao: `[sql_execution_queue]`, `[circuit_breaker]`, `[database_gateway]`.
- Shutdown: `[bootstrap_app_shutdown]`.
- Falhas SQL e eventos de recuperacao ODBC: `plug_agente_errors.log` (DSN como
  fingerprint; nunca SQL, parametros ou connection string).

Ao reportar problemas, anexar o JSON de `agent.getHealth`.

## Checklist pos-deploy

- [ ] Logs de startup (fila inicializada, warm-up concluido)
- [ ] Rejeicoes da fila < 1% durante 1 h
- [ ] Latencias p95/p99 estaveis
- [ ] Circuit breaker nao abre sem motivo
- [ ] Resultados registrados via
      [`odbc_operational_validation_runbook.md`](odbc_operational_validation_runbook.md)
