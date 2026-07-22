# Plano para Acoes Agendadas e Execucoes

## Objetivo

Area de acoes e execucoes locais no Plug Agente (comandos, processos, COM,
Data7, etc.), com agendamento enquanto o app esta aberto e execucao remota via
JSON-RPC `agent.action.*` no Hub — sem quebrar o contrato Socket.IO existente.

**Status oficial (2026-05-21):** MVP do agente **fechado** para CI/local
(`run_agent_actions_operational_gate.py`). Rollout de producao segue bloqueado
ate RA-01 (COM real), RA-02 (policy no Hub) e RA-05 (live Hub E2E assinado).

Codigo de dominio: `lib/domain/actions/` (e espelhos em `application` /
`infrastructure`), nao em `lib/domain/agent_actions/`.

Historico completo do MVP (fases, checklists `[x]`, decisoes fechadas):
[`docs/archive/plano_acoes_mvp_2026-05.md`](../archive/plano_acoes_mvp_2026-05.md).

## Ownership documental

| Assunto | Fonte de verdade |
| --- | --- |
| Contrato wire `agent.action.*` | [`docs/communication/socket_agent_actions.md`](../communication/socket_agent_actions.md) + OpenRPC/schemas |
| Entry-point RPC (paths, gates) | [`acoes/contrato_remoto.md`](acoes/contrato_remoto.md) |
| UI pagina Acoes | [`acoes/ui_acoes.md`](acoes/ui_acoes.md) |
| Flags, RA, live Hub ops | [`acoes/seguranca_acoes.md`](acoes/seguranca_acoes.md) |
| E2E local/CI / live | [`docs/testing/e2e_actions.md`](../testing/e2e_actions.md), [`docs/testing/e2e_hub.md`](../testing/e2e_hub.md) |
| Indice E2E | [`docs/testing/e2e_setup.md`](../testing/e2e_setup.md) |

Subdocs opcionais ainda nao criados (`runner_local`, `runner_elevado`,
`tipos_de_acao`): so abrir se o arquivo vivo voltar a crescer demais.

## Backlog pos-MVP (trabalho restante)

| Prioridade | ID | Entrega | Dono | Gate / referencia |
| --- | --- | --- | --- | --- |
| P0 | RA-05 | Live Hub E2E opt-in | QA + `.env` | `validate_live_hub_agent_actions_env.dart`; `homologate_hub_agent_actions.py --validate-live-env --run-live-tests`; [`e2e_hub.md`](../testing/e2e_hub.md) |
| P0 | RA-02 | Allowlist fina e rate limit no **Hub** | repositorio Hub | Policy alinhada a `AgentActionRemoteAuthorizationService` |
| P1 | RA-01 | Handlers **COM** de producao | agente | `com_object_production_registrations.dart` (ou stub + RA-01) |
| P1 | RA-06 | Elevado em campo (UAC, helper assinado) | ops | `homologate_elevated_runner.py` |
| P1 | RA-04 | Threat model + sign-off por tipo | PR humano | `agent_action_security_gate_checklist.dart <tipo>` |
| P2 | RA-03 | Contexto remoto inline no RPC | agente + Hub | Decisao de produto; hoje `supportsContext: false` |
| P2 | — | Homologacao **developer**/Data7 em campo | ops | Sem override remoto de paths |
| P3 | — | Refino kill/`replaceRunning`, dialogo app-close | agente | Opcional; nao bloqueia CI |

## Arquitetura implementada (resumo)

- Gate compartilhado: `AgentActionExecutionGateChain`
- Orquestracao pos-gate: `AgentActionExecutionOrchestrator`
- Lifecycle de processo: `AgentActionProcessLifecycle`
- RPC: handlers em `lib/application/rpc/` +
  `AgentActionRpcMethodHandlerOperations`
- Providers: controllers em `lib/presentation/providers/agent_actions/`
- Auditoria remota append-only: Drift `agent_action_remote_audit`
- Identidade de runtime: `AgentRuntimeIdentity` (`runtimeInstanceId` /
  `runtimeSessionId`)

Detalhe historico e checklist de arquivos: arquivo em
[`docs/archive/`](../archive/plano_acoes_mvp_2026-05.md).

## Threat model (baseline)

Superficie de alto risco (processo local, segredos, remoto). Revisar antes de
habilitar remoto, elevado, ad-hoc ou novo tipo.

Mitigacoes obrigatorias: scopes `agent_actions.*` + allowlist `action_ids`;
aprovacao/reaprovacao; feature flags; redacao; draining/maintenance;
idempotencia; auditoria append-only; runner elevado com request/nonce/ACL.

### Baseline por adapter (2026-05-20)

| Tipo | Superficie | Gate remoto/elevado |
| --- | --- | --- |
| `commandLine` | Shell | Remoto so acao salva + aprovacao; ad-hoc off; elevado opcional |
| `executable` | CreateProcess + snapshot/hash | Idem |
| `script` | Interpreter + script paths | Idem |
| `jar` | Java + JAR | Idem |
| `email` | SMTP + anexos | Remoto com aprovacao; anexos validados |
| `comObject` | COM local | Handlers de producao obrigatorios fora de homologacao |
| `developer` | Data7 / `.7Proj` | Remoto sem override de paths/conexao |

Checklist PR: `dart run tool/agent_actions/agent_action_security_gate_checklist.dart [tipo]`.

## Riscos aceitos (MVP agente)

| ID | Risco | Mitigacao atual | Quando reavaliar |
| --- | --- | --- | --- |
| RA-01 | COM sem handler de producao | Registry vazio; stub E2E; UI avisa | Registrar handlers por PR |
| RA-02 | Allowlist/rate limit no Hub | Agente valida scopes + rate limit local | Deploy Hub alinhado |
| RA-03 | Contexto remoto inline | Rejeitado (`supportsContext: false`) | Decisao de produto |
| RA-04 | Threat model nao e CI | Baseline + checklist humano | Cada PR remoto/elevado/ad-hoc |
| RA-05 | Live Hub E2E opt-in | Gate local/CI; live via `.env` | Antes de release Hub-dependent |
| RA-06 | Elevado sem UAC em campo | Nucleo + script homologacao | Helper assinado instalado |
| RA-07 | Multi-instancia | `runtimeInstanceId`; lock do scheduler | Incidente Drift compartilhado |
| RA-08 | Ad-hoc remoto off | `enableRemoteAdHocAgentActions` default false | Aprovacao explicita |

**Rollback rapido (agente)** — ver tambem [`seguranca_acoes.md`](acoes/seguranca_acoes.md):

1. `FeatureFlags.disableAgentActionsRemoteRollout()`
2. `enableAgentActionsMaintenanceMode`
3. `setEnableAgentActions(false)`

## Roteiro operacional

1. `python tool/agent_actions/run_agent_actions_operational_gate.py`
2. Por tipo: `dart run tool/agent_actions/agent_action_security_gate_checklist.dart <tipo>`
3. Live Hub: preparar `.env` e seguir [`e2e_hub.md`](../testing/e2e_hub.md)
4. `dart run tool/e2e/validate_live_hub_agent_actions_env.dart`
5. `python tool/agent_actions/homologate_hub_agent_actions.py --validate-live-env --run-live-tests`

Variaveis live: `RUN_LIVE_HUB_*`, `E2E_HUB_URL`, `E2E_HUB_TOKEN`,
`PAYLOAD_SIGNING_*` — detalhes em [`e2e_hub.md`](../testing/e2e_hub.md)
(secao **Onde obter os valores**).

## Politica de documentacao

- Atualizar este plano vivo (status, backlog RA, threat baseline) ao mudar
  feature relevante.
- Mudanca de wire: OpenRPC/schemas + `socket_agent_actions.md` no mesmo ciclo.
- Nao marcar Hub como pronto para producao antes de RA-01/02/05.
- Historico MVP nao volta para este arquivo; fica no archive.
