# UI operacional — pagina Acoes (Plug Agente)

Indice da superficie Fluent **Acoes do Sistema** e gates de regressao. Plano
completo: [plano_acoes_agendadas_execucoes.md](../plano_acoes_agendadas_execucoes.md).

**Status (2026-08-22):** pagina operacional; gate UI no manifesto
`tool/agent_actions/manifests/agent_actions_ui_test_paths.txt`.
`agent_actions_page_test.dart` e shim que reexporta
`agent_actions_actions_tab_test.dart` e `agent_actions_settings_tab_test.dart`.
Rollout de producao da superficie completa ainda depende de `COM` real
aprovado + Hub com policy/live signing alinhados.

## Entrada e estado

| Item | Caminho / nota |
| --- | --- |
| Rota | `AppRoutes.agentActions` (`/agent-actions`) |
| Pagina | `lib/presentation/pages/agent_actions/agent_actions_page.dart` |
| Provider | `lib/presentation/providers/agent_actions_provider.dart` (fachada; controllers em `providers/agent_actions/`) |
| Shell desktop | Fluent UI; loading / empty / error na propria pagina; abas Acoes, Historico, Preferencias, Auditoria remota (flag) |

## Superficies principais

- **Toolbar:** `AgentActionsToolbarCard` — nova, atualizar, export/import
  bundle JSON, executar, testar, modo de manutencao. Run / test / bundle
  transfer sao mutuamente exclusivos (`hasBlockingLocalOperation`). Falha ao
  ligar manutencao nao e engolida. Refresh fica desabilitado enquanto uma
  operacao local estiver em curso.
- **Empty state:** lista todos os `AgentActionDraftKind` do editor (nao so
  linha de comando / executavel / script).
- **Lista e editor** por tipo persistido: `commandLine`, `executable`,
  `script`, `jar`, `email`, `comObject`, `developer` (Data7). PowerShell e
  kind de editor (`AgentActionDraftKind.powerShell`) e persiste como
  `commandLine` (inline) ou `script`.
- **Rebuilds:** abas e dialogs usam `AgentActionsSelectBuilder` para nao
  reconstruir o grid/formulario a cada tick da fila.
- **Gatilhos:** `AgentActionTriggerSaveDialog`, timezone IANA
  (`IanaTimezoneIdField`), resumo de proxima execucao. Save/delete de
  gatilho ressincroniza o scheduler.
- **Historico de execucoes:** filtro por id / trace / idempotency; diagnostico
  com stdout/stderr paginado (`pagingIdentity`; ignora `onSlice` por
  identidade e fatias stale).
- **Retencao:** `AgentActionsRetentionCard` + `AgentActionRetentionSettings`.
- **Auditoria remota:** `AgentActionsRemoteAuditPanel` escuta loading/erro/
  linhas do provider; correlacao com historico
  (`focusExecutionFromRemoteAudit`).
- **Riscos e confirmacoes:** chips (`agent_action_risk_labels.dart`),
  dialogs (`agent_action_confirmations.dart`), reaprovacao remota. Run/delete
  revalidam a acao selecionada depois do confirm.
- **Atalhos:** `Ctrl+N` / Enter / Delete / `Ctrl+T` / `Ctrl+R` so na aba
  Acoes; `F5` na pagina. Bloqueados com modal aberto ou operacao local
  bloqueante.
- **Segredos:** `AgentActionSecretsSection`, placeholders `${secret:name}`.
- **Runtime / fila:** InfoBar `AgentActionRuntimeStateGuard`, metricas de fila,
  aviso scheduler lock / COM sem handlers, summary card.
- **Runner elevado:** `prepareElevatedRunner` + InfoBar de preparacao.

## Testes de regressao (obrigatorio ao mudar layout/fluxo)

Manifesto: `tool/agent_actions/manifests/agent_actions_ui_test_paths.txt`

```powershell
flutter test test/presentation/pages/agent_actions_page_test.dart
flutter test test/presentation/widgets/agent_actions/
```

Ou gate completo:

```powershell
python tool/agent_actions/run_agent_actions_operational_gate.py
```

Cenarios criticos cobertos nos testes (nao exaustivo):

- diagnostico + cancelamento de execucao em andamento;
- stdout em chunks on-demand (paginacao estavel se o parent rebuildar);
- empty state com todos os kinds do editor;
- run/test/import nao se sobrepoem;
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
