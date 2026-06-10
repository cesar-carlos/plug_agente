# Configuracao de Testes E2E

Indice central dos testes E2E e de integracao do agente. Os detalhes por
familia de teste estao em subdocs dedicados; este arquivo concentra
pre-requisitos, preflight e como rodar.

## Pre-requisitos

1. Copie `.env.example` para `.env`:

   ```bash
   # Windows
   copy .env.example .env

   # Linux / macOS
   cp .env.example .env
   ```

2. Edite `.env` com as variaveis das familias que voce vai rodar. Cada
   subdoc abaixo lista as variaveis especificas.

## Subdocs por familia

| Familia | Subdoc | Quando consultar |
| --- | --- | --- |
| API HTTP | [e2e_api.md](e2e_api.md) | Login/refresh contra hub real |
| Hub Socket.IO | [e2e_hub.md](e2e_hub.md) | Smoke do canal, `PayloadFrame` assinado, contrato `agent.action.*` live |
| Acoes (`agent.action.*`) | [e2e_actions.md](e2e_actions.md) | Stub COM, retencao de acoes, runner elevado Windows |
| ODBC | [e2e_odbc.md](e2e_odbc.md) | Streaming, RPC, DML perf, bulk load, queue burst, lock contention |
| Concorrencia da fila SQL | [sql_queue_concurrency_tests.md](sql_queue_concurrency_tests.md) | Estrategia de testes da `SqlExecutionQueue` |
| Single instance Windows | [single_instance_multiuser.md](single_instance_multiuser.md) | Cenarios manuais multi-usuario |

## Verificar configuracao

Antes de rodar os testes, valide o `.env`:

```bash
dart run tool/check_e2e_env.dart
```

O script exibe quais variaveis estao definidas e quais testes serao
executados ou ignorados. Pode ser executado de qualquer diretorio. Inclui
`RUN_ODBC_BURST_TESTS` e o estado do `sql_queue_burst_test`.

No Windows, o wrapper consolidado roda preflight e gera worksheet
operacional:

```powershell
.\tool\run_odbc_operational_validation.ps1
.\tool\run_odbc_operational_validation.ps1 -All
```

Para preflight especifico do Hub `agent.action.*` live, ver
[e2e_hub.md](e2e_hub.md).

### Agent-actions operational gate (local / CI)

Acoes agendadas (`agent.action.*`) tem gate dedicado sem Hub real. No Windows,
use o atalho `tool/run_agent_actions_operational_gate.ps1` ou os wrappers
equivalentes:

- `tool/preflight_agent_actions_production.ps1 -RunContractTests` — preflight
  estatico + testes de contrato listados em `tool/agent_actions_*_test_paths.txt`
- `tool/homologate_hub_agent_actions.ps1 -RunContractTests` — homologacao
  consolidada (contrato local)

Homologacao live contra Hub real e opt-in (`RUN_LIVE_HUB_*`, `E2E_HUB_URL`,
`E2E_HUB_TOKEN`, assinatura `PAYLOAD_SIGNING_*`); preflight:
`dart run tool/validate_live_hub_agent_actions_env.dart` com
`homologate_hub_agent_actions.ps1 -ValidateLiveEnv -RunLiveTests`. Detalhes em
`.cursor/rules/project_specifics.mdc` e `docs/implemente/plano_acoes_agendadas_execucoes.md`.

## Executar

```bash
# Suite rapida: exclui testes marcados como live/slow/perf
flutter test --exclude-tags "live || slow || perf"

# Suite completa, incluindo marcados (pode falhar se opt-ins estiverem ligados sem .env adequado)
flutter test

# Todos os testes de integracao
flutter test --tags live test/integration/
```

Comandos por familia ficam nos subdocs correspondentes. Testes que dependem
de variaveis nao definidas sao **ignorados** (skip) com mensagem
explicativa.

## Referencias do harness

- `test/helpers/e2e_env.dart` — helper `E2EEnv` para acesso as variaveis
- `test/helpers/odbc_e2e_coverage_sql.dart` — DDL/DML por dialeto para E2E ODBC
- `test/helpers/odbc_e2e_row_assertions.dart` — leitura de colunas ODBC case-insensitive nos testes
- `test/helpers/odbc_e2e_rpc_harness.dart` — gateway real + `RpcMethodDispatcher` para E2E RPC
- `tool/run_odbc_operational_validation.ps1` — wrapper operacional Windows
- `.env.example` — template das variaveis E2E/integracao

## Notas

- **`.env` nos testes Flutter:** o `E2EEnv` localiza a raiz do projeto
  (sobe diretorios ate achar `pubspec.yaml`) e le `.env` via sistema de
  arquivos + `flutter_dotenv.loadFromString` (nao usa assets do
  `pubspec.yaml`).
- **`check_e2e_env` vs `E2EEnv`:** o script `tool/check_e2e_env.dart` roda
  com `dart run` (sem `dart:ui`) e usa um parser de linhas equivalente ao
  caso comum `chave=valor` (primeiro `=` separa chave e valor). Para
  entradas exoticas, a fonte de verdade nos testes e o `E2EEnv`.
- **Benchmarks (fora do `E2EEnv`):** variaveis como `ODBC_E2E_BENCHMARK_*`,
  `SOCKET_TRANSPORT_BENCHMARK_*`, `PAYLOAD_FRAME_BENCHMARK_*`, etc., sao
  usadas por testes de performance/regressao (`test/live/`, ficheiros
  `*benchmark*`). Nao entram no `E2EEnv` nem no `check_e2e_env.dart`; o
  contrato fica no proprio teste. Podem viver no `.env` local com lista
  longa; o `.env.example` cobre o conjunto E2E/integracao.
