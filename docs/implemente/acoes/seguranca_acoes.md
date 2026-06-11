# Seguranca e operacao — acoes agendadas (Plug Agente)

Indice de flags, riscos aceitos, threat model e rollback. Plano completo:
[plano_acoes_agendadas_execucoes.md](../plano_acoes_agendadas_execucoes.md)
(secoes Threat model, Riscos aceitos, Politica de superficie remota).

## Feature flags (`FeatureFlags`)

| Flag | Default conservador | Efeito resumido |
| --- | --- | --- |
| `enableAgentActions` | **true** | Habilita UI, scheduler, fila e RPC `agent.action.*`; desligar so via rollback explicito |
| `enableRemoteAgentActions` | off | RPC `agent.action.*` + capability |
| `enableRemoteAdHocAgentActions` | **false** (RA-08) | Comando livre remoto |
| `enableElevatedAgentActions` | false | Pipeline elevado |
| `enableAgentActionsMaintenanceMode` | **false** | Bloqueia remoto/agendado |
| `enableAgentActionRemoteAudit` | **true** | Auditoria append-only |

**Status oficial (2026-05-21):** local/CI fechado no `plug_agente`; producao
segue bloqueada por `COM` real aprovado (RA-01), policy fina no Hub (RA-02) e
homologacao live assinada contra Hub real (RA-05).

Rollback rapido (ordem sugerida no plano §4195 / RA-08):

1. `disableAgentActionsRemoteRollout()`
2. `enableAgentActionsMaintenanceMode`
3. `setEnableAgentActions(false)`

## Riscos aceitos (homologacao local/CI)

| ID | Resumo | Acao antes de producao |
| --- | --- | --- |
| RA-01 | COM sem handler de producao | Registrar `ProgID/member` aprovado em `com_object_production_registrations.dart`; nao inventar handler generico |
| RA-02 | Allowlist/rate limit no Hub | Alinhar policy no `plug_server` e manter paridade com scopes + `action_ids` do agente |
| RA-03 | Sem contexto remoto inline | Decisao de produto + contrato |
| RA-04 | Threat model nao e CI | Sign-off humano por tipo |
| RA-05 | Live Hub opt-in | `.env`, `PAYLOAD_SIGNING_*` reais e `--run-live-tests` |
| RA-06 | Elevado sem campo UAC | Homologar helper assinado |
| RA-07 | Multi-instancia app | Correlacao `runtimeInstanceId` |
| RA-08 | Ad-hoc remoto off | So com aprovacao explicita |

## Checklist de PR (por tipo)

```powershell
dart run tool/agent_action_security_gate_checklist.dart
dart run tool/agent_action_security_gate_checklist.dart commandLine
```

Nao substitui revisao humana da matriz
[Threat model baseline por adapter](../plano_acoes_agendadas_execucoes.md#threat-model-baseline-por-adapter-agente-2026-05-20)
no plano mestre.

## Controles no agente

- **Segredos:** `flutter_secure_storage` via `IAgentActionSecretStore`;
  placeholders `${secret:name}`; falha `action_secret_unavailable` se ausente.
- **Remoto:** acao salva + aprovada; `riskFingerprint` + reaprovacao em mudanca;
  scopes `agent_actions.*` + allowlist `action_ids` no token.
- **Redacao:** export/backup/suporte via `AgentActionBackupSanitizer`,
  `AgentActionExecutionSupportExport`; RPC `getExecution` com
  `sanitizeForRemoteHub`.
- **Auditoria:** Drift `agent_action_remote_audit` append-only; purge por
  retencao configuravel.
- **Paths:** `ActionPathValidator`, allowlists, snapshot/hash no cadastro.

## Live Hub — pre-requisitos (RA-05)

```powershell
dart run tool/validate_live_hub_agent_actions_env.dart
```

Bloqueios comuns:

- **JWT expirado** — login no app (Config) ou
  `fetch_e2e_hub_token_from_local_config.dart --apply-token --force` (requer
  token no DB ou `E2E_HUB_USERNAME`/`PASSWORD` no `.env`).
- **HMAC divergente** — `promote_e2e_signing_from_monorepo_env.dart` copia de
  `plug_server/.env` quando layout monorepo existe; senao chaves do Hub em deploy.
- **`sync_e2e_hub_env_from_local.dart --export-secure`** depende de Flutter
  (`dart:ui`); use app instalado + export manual ou credenciais no `.env` se o
  script falhar fora do contexto Flutter.

Sugestao URL/agent id sem segredos:

```powershell
dart run tool/suggest_e2e_hub_from_local_config.dart --apply-url --apply-agent-id
```

## Referencias

- Contrato remoto: [`contrato_remoto.md`](contrato_remoto.md)
- UI: [`ui_acoes.md`](ui_acoes.md)
- E2E: `docs/testing/e2e_setup.md`
