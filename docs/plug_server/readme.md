# Orientacoes para `plug_server` — extensoes de performance (2026-06)

> **Audiencia.** Time do `plug_server` (hub). O que o hub precisa fazer para
> alinhar com as extensoes de transporte ja entregues no `plug_agente`.
>
> **Espelho.** O hub mantem orientacoes para o agente em
> `plug_server/docs/plug_agente/`. Esta pasta e o inverso.
>
> **Fonte normativa do agente.** Schemas/OpenRPC em `docs/communication/`;
> codigo em `lib/domain/protocol/transport_extension_negotiation.dart` e
> `lib/application/services/protocol_negotiator.dart`.

## Status

Hub implementado em
[`560ef2f`](https://github.com/cesar-carlos/plug_server/commit/560ef2f)
(2026-06-24); agente em
[`741b5677`](https://github.com/cesar-carlos/plug_agente/commit/741b5677).
Comportamento ativo apos **deploy coordenado** e handshake com intersecao das
tres chaves em `negotiatedExtensions`.

Checklist detalhado (historico, quase todo `[x]`):
[`docs/archive/plug_server_02_implementation_checklist_2026-06.md`](../archive/plug_server_02_implementation_checklist_2026-06.md).

| Extensao | O hub precisa? | Sem hub | Com hub alinhado |
| -------- | -------------- | ------- | ---------------- |
| `clientRequestIdEcho: "v1"` | **Sim** | Opcao B (rewrite `body.id`) | Opcao A: `body.id` end-to-end |
| `agentPhaseTimings: "v1"` | **Sim** | Sem `meta.agent_phases` | Fases quando `requestServerTimings: true` |
| `healthPiggyback: { ... }` | **Sim** | Sem piggyback | `meta.health_snapshot` em respostas unary |

Itens so no agente (sem mudanca de hub): acks/replay por `meta.request_id`,
coalescing `rpc:batch_ack`, migracao de prefs legadas, pre-warm de schemas.

## Como ler

1. [`01_transport_extensions.md`](01_transport_extensions.md) — contrato e
   arquivos do hub a tocar.
2. Checklist historico arquivado (validacao pos-deploy ainda util):
   [`archive/...checklist...`](../archive/plug_server_02_implementation_checklist_2026-06.md).
3. ADRs no hub: `plug_server/docs/adrs/0009-*.md`, `0010-*.md`, `0011-*.md`.
4. Roadmap cross-repo: `plug_server/docs/plug_agente/03_performance_roadmap.md`.

## Politica

- Atualize quando o agente depender de comportamento novo no hub.
- Nao duplique o contrato normativo — aponte para schemas e ADRs.
- Paths relativos assumem checkout lado-a-lado (`../plug_server/`).
