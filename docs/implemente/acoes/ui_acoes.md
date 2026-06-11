# UI operacional — pagina Acoes (Plug Agente)

Indice da superficie Fluent **Acoes** e gates de regressao. Plano completo:
[plano_acoes_agendadas_execucoes.md](../plano_acoes_agendadas_execucoes.md).

**Status (2026-05-21):** pagina operacional e gate UI fechado no manifesto
`tool/agent_actions_ui_test_paths.txt` (7 arquivos:
`agent_actions_page_test.dart` agora e shim que reexporta
`agent_actions_actions_tab_test.dart` (~73 cenarios) e
`agent_actions_settings_tab_test.dart` (~5 cenarios), alem de
`agent_actions_summary_card_test.dart`, `agent_action_risk_labels_test.dart`,
`agent_action_confirmations_test.dart` e
`agent_action_remote_audit_labels_test.dart`).
Rollout de producao da superficie completa ainda depende de `COM` real
aprovado + Hub com policy/live signing alinhados.

## Entrada e estado

| Item | Caminho / nota |
| --- | --- |
| Rota | `AppRoutes.agentActions` |
| Pagina | `lib/presentation/pages/agent_actions_page.dart` |
| Provider | `lib/presentation/providers/agent_actions_provider.dart` |
| Shell desktop | Fluent UI; estados loading / empty / error na propria pagina |

## Superficies principais

- **Toolbar:** export/import bundle JSON (`AgentActionsToolbarCard`).
- **Lista e editor** por tipo: `commandLine`, `executable`, `script`, `jar`,
  `email`, `comObject`, `developer` (Data7).
- **Gatilhos:** `AgentActionTriggerSaveDialog`, timezone IANA
  (`IanaTimezoneIdField`), resumo de proxima execucao.
- **Historico de execucoes:** filtro por id / trace / idempotency; diagnostico
  com stdout/stderr paginado (inline ou chunks via `onSliceCapturedOutput`).
- **Retencao:** `AgentActionsRetentionCard` + `AgentActionRetentionSettings`.
- **Auditoria remota:** `AgentActionsRemoteAuditPanel`, correlacao com historico
  (`focusExecutionFromRemoteAudit`).
- **Riscos e confirmacoes:** chips (`agent_action_risk_labels.dart`),
  dialogs (`agent_action_confirmations.dart`), reaprovacao remota.
- **Segredos:** `AgentActionSecretsSection`, placeholders `${secret:name}`.
- **Runtime / fila:** InfoBar `AgentActionRuntimeStateGuard`, metricas de fila,
  aviso scheduler lock / COM sem handlers, summary card.
- **Runner elevado:** `prepareElevatedRunner` + InfoBar de preparacao.

## Testes de regressao (obrigatorio ao mudar layout/fluxo)

Manifesto: `tool/agent_actions_ui_test_paths.txt`

```powershell
flutter test test/presentation/pages/agent_actions_page_test.dart
flutter test test/presentation/widgets/agent_actions/
```

Ou gate completo:

```powershell
python tool/run_agent_actions_operational_gate.py
```

Cenarios criticos cobertos nos testes (nao exaustivo):

- diagnostico + cancelamento de execucao em andamento;
- stdout em chunks on-demand;
- mismatch `runtime_instance_id` auditoria vs historico;
- lock do scheduler e COM handlers no summary;
- politicas de captura, fila, paths, encoding no editor `commandLine`;
- export JSON de suporte da execucao (clipboard).

## Localizacao

Strings via `AppLocalizations` (ARB em `lib/l10n/`). Evitar literais novos na
pagina sem entrada ARB quando a superficie ja estiver no fluxo localizado.

## Fora deste subdoc

- Contrato Hub: [`contrato_remoto.md`](contrato_remoto.md)
- Seguranca / flags / threat model: [`seguranca_acoes.md`](seguranca_acoes.md)
