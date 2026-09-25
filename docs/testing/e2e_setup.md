# Configuracao de Testes E2E

Indice central dos testes E2E e de integracao do agente. Os detalhes por
familia de teste (variaveis, comandos, troubleshooting) estao em subdocs
dedicados; este arquivo concentra pre-requisitos, preflight e como rodar.

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
| Hub Socket.IO | [e2e_hub.md](e2e_hub.md) | Smoke do canal, `PayloadFrame` assinado, contrato `agent.action.*` live, push de diagnostico de auto-update |
| Acoes (`agent.action.*`) | [e2e_actions.md](e2e_actions.md) | Stub COM, retencao de acoes, runner elevado Windows, linha de comando |
| ODBC | [e2e_odbc.md](e2e_odbc.md) | Streaming, RPC, DML perf/bulk/stress, queue burst, lock contention, benchmarks |
| Auto-start Windows (registro real) | [Secao abaixo](#auto-start-windows-registro-real) | Adapters Win32 do `Run`/`StartupApproved` em HKCU |
| Concorrencia da fila SQL | [sql_queue_concurrency_tests.md](sql_queue_concurrency_tests.md) | Estrategia de testes da `SqlExecutionQueue` |
| Single instance Windows | [single_instance_multiuser.md](single_instance_multiuser.md) | Cenarios manuais multi-usuario |

## Verificar configuracao

Antes de rodar os testes, valide o `.env`:

```bash
dart run tool/e2e/check_e2e_env.dart
```

O script exibe quais variaveis estao definidas e quais testes serao
executados ou ignorados. Pode ser executado de qualquer diretorio. Flags
opcionais para gate de CI (saem com codigo `1` se a familia nao estiver
configurada): `--fail-if-missing-odbc`, `--fail-if-missing-live-api`,
`--fail-if-missing-hub`.

Preflights especificos:

- ODBC (wrapper operacional + worksheet): [e2e_odbc.md](e2e_odbc.md#fluxo-operacional-completo)
- Hub `agent.action.*` live: [e2e_hub.md](e2e_hub.md#preflight-validate_live_hub_agent_actions_envdart)

### Agent-actions operational gate (local / CI)

Acoes agendadas (`agent.action.*`) tem gate dedicado sem Hub real:

```bash
python tool/agent_actions/run_agent_actions_operational_gate.py
```

Encadeia preflight estatico + testes dos manifestos
`tool/agent_actions/manifests/agent_actions_{contract,ui}_test_paths.txt`.
Flags, wrappers individuais e homologacao live contra Hub real ficam em
[e2e_hub.md](e2e_hub.md#runners-python); status e roteiro em
[plano_acoes_agendadas_execucoes.md](../implemente/plano_acoes_agendadas_execucoes.md#roteiro-operacional).

### Elevated action runner e COM stub

Homologacao manual do helper elevado (build, UAC, tarefa agendada) e do stub
COM (`AGENT_ACTION_COM_STUB_*`): ver [e2e_actions.md](e2e_actions.md).

## Auto-start Windows (registro real)

`test/integration/windows_startup_registry_live_e2e_test.dart` exercita os
adapters Win32 de leitura/escrita do `Run` e do overlay `StartupApproved`
contra o registro real. Usa um valor temporario em HKCU com nome unico por
teste (a entrada instalada "Plug Agente" nunca e tocada) e remove no
teardown. Escopos de maquina so sao lidos (esperado: ausente ou acesso
negado). **Opt-in, somente Windows.**

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `RUN_LIVE_STARTUP_REGISTRY_TESTS` | Sim | `true` para executar (fora do Windows o teste e sempre ignorado) |

```bash
flutter test test/integration/windows_startup_registry_live_e2e_test.dart
```

## Executar

```bash
# Suite rapida: exclui testes marcados como live/slow/perf
flutter test --exclude-tags "live || slow || perf"

# Suite completa, incluindo marcados (pode falhar se opt-ins estiverem ligados sem .env adequado)
flutter test

# Testes de integracao marcados com a tag live
flutter test --tags live test/integration/
```

`--tags live` so seleciona testes marcados; o teste de auto-start acima nao
usa tag e roda pelo caminho do arquivo. Comandos por familia ficam nos
subdocs correspondentes. Testes que dependem de variaveis nao definidas sao
**ignorados** (skip) com mensagem explicativa.

## Referencias do harness

- `test/helpers/e2e_env.dart` — helper `E2EEnv` para acesso as variaveis
- `test/helpers/odbc_e2e_coverage_sql.dart` — DDL/DML por dialeto para E2E ODBC
- `test/helpers/odbc_e2e_row_assertions.dart` — leitura de colunas ODBC case-insensitive nos testes
- `test/helpers/odbc_e2e_rpc_harness.dart` — gateway real + `RpcMethodDispatcher` para E2E RPC
- `.env.example` — template das variaveis E2E/integracao

## Notas

- **`.env` nos testes Flutter:** o `E2EEnv` localiza a raiz do projeto
  (sobe diretorios ate achar `pubspec.yaml`) e le `.env` via sistema de
  arquivos + `flutter_dotenv.loadFromString` (nao usa assets do
  `pubspec.yaml`). Valores ausentes caem em `Platform.environment`.
- **`check_e2e_env` vs `E2EEnv`:** o script `tool/e2e/check_e2e_env.dart` roda
  com `dart run` (sem `dart:ui`) e usa um parser de linhas equivalente ao
  caso comum `chave=valor` (primeiro `=` separa chave e valor). Para
  entradas exoticas, a fonte de verdade nos testes e o `E2EEnv`.
- **Benchmarks:** variaveis de benchmark (`ODBC_E2E_BENCHMARK_*`,
  `ODBC_BENCH_CONNECTION_STRING`, `BENCHMARK_GATEWAY_ENCODING`,
  `SOCKET_TRANSPORT_BENCHMARK_*`, `PAYLOAD_FRAME_BENCHMARK_*`) nao entram no
  `E2EEnv` nem no `check_e2e_env.dart`. Runner e opt-ins em
  [e2e_odbc.md](e2e_odbc.md#benchmarks).
