# E2E - Hub Socket.IO

Smoke e homologacao do canal Socket.IO entre agente e hub. Cobre handshake
basico, `PayloadFrame` assinado e contrato `agent.action.*` quando o hub
emitir RPC.

Index geral: [e2e_setup.md](e2e_setup.md). Para `agent.action.*` local/CI sem
hub, ver tambem [e2e_actions.md](e2e_actions.md).

## Smoke (`hub_socket_live_e2e_test.dart`)

Abre WebSocket via `SocketDataSource` (mesmo codigo que o transporte),
namespace `/agents`, handshake com token, depois `disconnect`.

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `RUN_LIVE_HUB_TESTS` | Sim | `true` para executar este teste |
| `E2E_HUB_URL` | Sim | URL base do hub (`ensureAgentsNamespaceUrl` acrescenta `/agents` se faltar) |
| `E2E_HUB_TOKEN` | Sim | Token de agente enviado no auth do handshake Socket.IO |
| `E2E_HUB_AGENT_ID` | Nao | Agent id do register/capabilities assinado (default: `codex-live-agent`) |

## PayloadFrame assinado

O mesmo arquivo contem teste opt-in que faz `agent:register` com frame HMAC
e exige `agent:capabilities` assinado pelo hub:

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `RUN_LIVE_HUB_SIGNING_TESTS` | Sim | `true` para executar o handshake assinado |
| `PAYLOAD_SIGNING_KEY_ID` | Sim* | `key_id` ativo compartilhado com o hub |
| `PAYLOAD_SIGNING_ACTIVE_KEY_ID` | Sim* | Alternativa para selecionar o `key_id` ativo |
| `PAYLOAD_SIGNING_KEY` | Sim | Segredo HMAC compartilhado com o hub |
| `E2E_HUB_IS_LOCAL` | Nao | `true`: trata a URL como Hub local no preflight de assinatura |
| `E2E_HUB_ALLOW_E2E_DEV_ON_REMOTE` | Nao | `true`: desliga o bloqueio `e2e-dev` vs Hub remoto (so diagnostico; nao usar em CI) |

\* Defina `PAYLOAD_SIGNING_ACTIVE_KEY_ID` ou `PAYLOAD_SIGNING_KEY_ID`.

## Preflight: `validate_live_hub_agent_actions_env.dart`

```bash
dart run tool/validate_live_hub_agent_actions_env.dart
```

Imprime checklist `[ok]`/`[ ]` sem expor segredos.

| Codigo | Significado |
| ------ | ----------- |
| `0` | Variaveis obrigatorias presentes; sem bloqueios nem avisos (pronto para live). |
| `1` | Variaveis em falta **ou** preflight bloqueante (JWT expirado; `e2e-dev` + Hub remoto com `RUN_LIVE_HUB_SIGNING_TESTS=true`; etc.). |
| `2` | Variaveis ok; ha avisos nao bloqueantes (ex.: JWT expira em breve; `e2e-dev` + remoto quando assinatura live esta desligada). |

CI: o job principal (`flutter_ci.yml`, `release-preflight.yml`, `release.yml`)
roda `flutter test --exclude-tags "live || slow || perf"`. O job opcional
`live-hub-e2e` roda os testes live com secrets do repositorio.

Nao coloque o token em logs.

## Onde obter os valores (desenvolvimento local)

| Variavel | Fonte usual |
| -------- | ----------- |
| `E2E_HUB_URL` | Mesma URL do hub que o Plug Agente usa na UI (Socket.IO); o teste acrescenta `/agents` se faltar. Ex.: `wss://host/hub` ou `https://host:port`. |
| `E2E_HUB_TOKEN` | Token do agente no hub (login/registro do agente no painel ou API de agente do hub). |
| `PAYLOAD_SIGNING_KEY_ID` / `PAYLOAD_SIGNING_ACTIVE_KEY_ID` | `key_id` ativo configurado no servidor hub para `PayloadFrame`. |
| `PAYLOAD_SIGNING_KEY` | Segredo HMAC correspondente no hub (deve ser **identico** no agente e no hub). |

### Monorepo local

Se voce desenvolve o monorepo, alinhe a partir de `../plug_server/.env`:

```bash
dart run tool/promote_e2e_signing_from_monorepo_env.dart
```

### Hub sem chaves HMAC (dev local)

Gera um par de teste e replica no `plug_server/.env`:

```bash
dart run tool/generate_dev_e2e_signing.dart
dart run tool/generate_dev_e2e_signing.dart --write
```

Com `--write`, preenche chaves vazias em `plug_agente/.env` e, se existir
no monorepo, em `../plug_server/.env`.

> Nao use `e2e-dev` contra um Hub remoto de producao — o connect Socket.IO
> pode passar, mas `agent:capabilities` assinado estoura timeout ate o par
> HMAC coincidir com o servidor.

Se `validate_live_hub_agent_actions_env.dart` terminar com codigo `1` por
`e2e-dev` + URL remota com assinatura ligada, copie `PAYLOAD_SIGNING_*` do
`.env` do hub em deploy (`promote_e2e_signing_from_monorepo_env.dart` ou
painel **Config -> WebSocket** + `export_e2e_secrets_from_local.dart`). Com
codigo `2`, corrija avisos (renove o JWT) antes de uma corrida longa.

## Executar

```bash
# Smoke (so URL + token, sem assinatura PayloadFrame):
flutter test test/integration/hub_socket_live_e2e_test.dart \
  --name "should connect to agents namespace"

# Smoke assinatura (`agent:register` -> `agent:capabilities`, exige HMAC igual ao hub):
flutter test test/integration/hub_socket_live_e2e_test.dart \
  --name "signed PayloadFrame"
```

Alinhe o agent id do register assinado com o agente do token:

```bash
dart run tool/suggest_e2e_hub_from_local_config.dart --apply-agent-id
```

Se o smoke falhar com `jwt expired`, renove `E2E_HUB_TOKEN` (login no app
em **Config** ou token do admin do hub):

```bash
dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token --force
```

Alternativa sem abrir o app (credenciais de agente no `.env`):

```bash
# E2E_HUB_URL, E2E_HUB_AGENT_ID, E2E_HUB_USERNAME, E2E_HUB_PASSWORD
dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token --force
```

`sync_e2e_hub_env_from_local.dart` passa `--force` automaticamente para
`export_e2e_secrets_from_local.dart` quando o JWT em `.env` ja expirou ou
quando o preflight detecta `e2e-dev` + Hub remoto.

### Sugestoes a partir do app instalado (Windows)

Se o Plug Agente ja esta configurado na UI:

```bash
dart run tool/suggest_e2e_hub_from_local_config.dart
dart run tool/suggest_e2e_hub_from_local_config.dart --apply-url
```

Le `agent_config.db` em `PlugAgente` e sugere `E2E_HUB_URL` (com `/agents`
quando necessario). Com `--apply-url`, grava so `E2E_HUB_URL` no `.env` se
a linha estiver vazia. Indica se ha `auth_token` ou credenciais salvas, mas
**nao** imprime token nem chaves HMAC.

Para preencher `E2E_HUB_TOKEN` automaticamente:

```bash
dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token
```

Atalho (URL + token + validate):

```bash
dart run tool/sync_e2e_hub_env_from_local.dart
```

`PAYLOAD_SIGNING_KEY_ID` e `PAYLOAD_SIGNING_KEY` ainda precisam vir do hub
(ou da seccao de signing na UI), exceto export opt-in:

```bash
dart run tool/sync_e2e_hub_env_from_local.dart --export-secure
```

Requer login e signing configurados no app instalado (`plug_agente.exe`,
Windows). Le `%APPDATA%\com.se7esistemas\plug_agente\flutter_secure_storage.dat`
sem imprimir segredos. Se `payload_signing_keys_json` nao existir no
storage, configure signing na UI **Config** (WebSocket) ou copie
`PAYLOAD_SIGNING_*` do `.env` do hub.

## Hub `agent.action.*` (`hub_agent_action_rpc_live_e2e_test.dart`)

Homologacao opt-in do contrato remoto de acoes apos handshake assinado
(`agent:register` -> `agent:capabilities` -> `agent:ready`). Nao executa SQL
nem dispara execucao real no agente alem do que o hub enviar quando
`E2E_HUB_EXPECT_AGENT_ACTION_RPC` estiver ligado.

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS` | Sim | `true` para nao ignorar este ficheiro (tag `live`) |
| `RUN_LIVE_HUB_TESTS` | Sim | Mesmo requisito da seccao smoke acima |
| `RUN_LIVE_HUB_SIGNING_TESTS` | Sim | Handshake com `PayloadFrame` assinado |
| `E2E_HUB_URL` / `E2E_HUB_TOKEN` | Sim | URL e token do agente no hub |
| `PAYLOAD_SIGNING_KEY_ID` / `PAYLOAD_SIGNING_KEY` | Sim* | Chaves HMAC partilhadas com o hub |
| `E2E_HUB_EXPECT_AGENT_ACTIONS_CAPABILITY` | Nao | `true`: exige `extensions.agentActions` em `agent:capabilities` |
| `E2E_HUB_EXPECT_AGENT_ACTION_RPC` | Nao | `true`: apos `agent:ready`, aguarda ate 25s por um `rpc:request` com metodo `agent.action.*` |

```bash
flutter test test/integration/hub_agent_action_rpc_live_e2e_test.dart --tags live
```

### Runners PowerShell

```powershell
.\tool\run_agent_actions_operational_gate.ps1
.\tool\preflight_agent_actions_production.ps1
.\tool\preflight_agent_actions_production.ps1 -RunContractTests
.\tool\homologate_hub_agent_actions.ps1 -RunContractTests
.\tool\homologate_hub_agent_actions.ps1 -ValidateLiveEnv
.\tool\homologate_hub_agent_actions.ps1 -RunContractTests -RunLiveTests
.\tool\homologate_hub_agent_actions.ps1 -PrepareLiveEnv -ValidateLiveEnv -RunContractTests -RunLiveTests
```

- `preflight_agent_actions_production.ps1` roda checks estaticos de
  producao (COM handler registry, consistencia live `.env` quando
  `RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS=true`). Use `-StrictCom` antes de
  deploy quando `comObject` nao deve depender do stub.
- `-RunContractTests` roda o manifesto de contrato
  (`tool/agent_actions_contract_test_paths.txt`) e o manifesto UI
  (`tool/agent_actions_ui_test_paths.txt`) sem hub. Validacao dos
  manifestos: `agent_action_test_manifest_test.dart` e
  `agent_actions_ci_gate_paths_sync_test.dart`.
- `run_agent_actions_operational_gate.ps1` encadeia preflight + homologate
  com `-RunContractTests`.
- `-PrepareLiveEnv` executa, em sequencia:
  `sync_e2e_hub_env_from_local.dart --export-secure`,
  `promote_e2e_signing_from_monorepo_env.dart --force` (ou
  `generate_dev_e2e_signing.dart --write`), e
  `fetch_e2e_hub_token_from_local_config.dart --apply-token --force` (JWT
  expirado exige login na Config, credenciais salvas ou
  `E2E_HUB_USERNAME`/`E2E_HUB_PASSWORD` no `.env`).
- `-ValidateLiveEnv` roda `validate_live_hub_agent_actions_env.dart` antes
  de `-RunLiveTests`.

CI: os mesmos arquivos rodam no **Agent actions homologation gate**
(`.github/workflows/flutter_ci.yml`). Live Hub `agent.action.*` rodam apenas
em manual `workflow_dispatch` de `live-hub-e2e` quando os secrets do
repositorio estao configurados.

### Rollback operacional

`Operational rollback (agent only, not .env):` desligar rollout remoto via
`FeatureFlags` (`disableAgentActionsRemoteRollout()` ou toggles na UI),
depois maintenance mode, depois `enableAgentActions=false`. Ver
[plano_acoes_agendadas_execucoes.md](../implemente/plano_acoes_agendadas_execucoes.md#riscos-aceitos-mvp-agente)
e
[Roteiro operacional pos-MVP](../implemente/plano_acoes_agendadas_execucoes.md#roteiro-operacional-pos-mvp-agente).

### PR security checklist por tipo

```bash
dart run tool/agent_action_security_gate_checklist.dart
dart run tool/agent_action_security_gate_checklist.dart commandLine
```
