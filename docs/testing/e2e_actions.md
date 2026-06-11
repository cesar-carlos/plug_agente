# E2E - Actions (`agent.action.*`)

Cobre setup local de homologacao para acoes agendadas: stub COM, retencao de
historico/auditoria e runner elevado Windows. Para o canal Hub Socket.IO
(handshake assinado, contrato remoto), ver [e2e_hub.md](e2e_hub.md).

Index geral: [e2e_setup.md](e2e_setup.md).

## COM actions (homologation stub)

Execucao COM local exige handlers em `ComObjectInvocationRegistry`. Sem
handlers de producao, use o stub opt-in (refletido em
`agent.getHealth -> com_object_invocation_ready` e no aviso da pagina
**Acoes** quando o count e zero).

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `AGENT_ACTION_COM_STUB_ENABLED` | Sim | `true` para registrar `ComObjectStubInvocationHandler` no startup |
| `AGENT_ACTION_COM_STUB_PROG_ID` | Sim | ProgID permitido pelo stub (ex.: `AgentAction.Test`) |
| `AGENT_ACTION_COM_STUB_MEMBER_NAME` | Sim | Nome do membro (ex.: `Ping`) |

Reinicie o agente apos mudar essas variaveis. O InfoBar da UI desaparece
quando `com_object_handlers_registered_count > 0`.

`dart run tool/check_e2e_env.dart` reporta se as variaveis do stub estao
completas.

## Retencao de acoes (purge local)

Os timers de purge no bootstrap usam `AgentActionRetentionSettings`
(precedencia: valores salvos na UI **Acoes -> Retencao de dados** > variaveis
de ambiente > defaults).

| Variavel | Default | Descricao |
| -------- | ------- | --------- |
| `AGENT_ACTION_EXECUTION_RETENTION_DAYS` | `3` | Historico de execucoes terminais (`CleanupAgentActionExecutions`) |
| `AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS` | `90` | Auditoria remota append-only (`CleanupExpiredAgentActionRemoteAudit`) |
| `AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS` | `24` | Limpeza de stdout/stderr em linhas antigas (`CleanupAgentActionCapturedOutput`; maximo = retencao de execucao em horas) |
| `AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS` | `min(execucao, 24h)` | TTL do cache Drift para `agent.action.run` / `validateRun` |

Chaves persistidas na instalacao (via `IAppSettingsStore`):
`agent_action_execution_retention_days`,
`agent_action_remote_audit_retention_days`,
`agent_action_captured_output_retention_hours`.

**Timestamps (wire):** `agent.action.getExecution` expoe `requested_at`,
`trigger.scheduled_at` / `triggered_at` e `timestamps.*` em UTC (`...Z`). A
UI local formata com `toLocal()`.

## Elevated action runner (Windows, homologacao manual)

O helper elevado **nao** usa `E2EEnv` nem testes `live` automatizados neste
ciclo. Valide em maquina Windows com UAC.

| Passo | Comando / configuracao |
| ----- | ---------------------- |
| Pre-flight (script) | `python tool/homologate_elevated_runner.py --build` (opcional: `--run-unit-tests` para testes Dart sem UAC) |
| Build do helper | `python tool/build_elevated_runner.py` -> `build\elevated_runner\plug_agente_elevated_runner.exe` (copia tambem para `build\windows\x64\runner\Release` se existir) |
| Path opcional | `ELEVATED_ACTION_RUNNER_EXE=C:\caminho\plug_agente_elevated_runner.exe` no `.env` quando o exe nao estiver ao lado do `plug_agente.exe` |
| Habilitar na app | Feature flag **Elevated agent actions** (`FeatureFlags.enableElevatedAgentActions` / preferencias) |
| Preparar na UI | Pagina **Acoes** -> InfoBar "Preparar executor elevado" (registra tarefa `PlugAgente\ElevatedActionRunner`) |
| Teste unitario (sem UAC) | `flutter test test/infrastructure/actions/elevated_action_runner_installer_test.dart test/application/actions/elevated_agent_action_execution_service_test.dart` |

Artefatos bridge sob o diretorio de dados do app:
`agent_actions/elevated/{requests,status,cancel,materialized}`.

## Cross-references

- Contrato remoto e capability: `docs/implemente/acoes/contrato_remoto.md`
- Threat model + flags + RA: `docs/implemente/acoes/seguranca_acoes.md`
- UI: `docs/implemente/acoes/ui_acoes.md`
- Plano canonico: `docs/implemente/plano_acoes_agendadas_execucoes.md`
