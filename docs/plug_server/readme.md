# Orientacoes para `plug_server` — extensoes de performance (2026-06)

> **Audiencia.** Time do `plug_server` (hub). Este conjunto descreve o que o
> hub precisa fazer para alinhar com as melhorias ja entregues (ou em
> entrega) no `plug_agente` para performance Socket / relay / observabilidade.
>
> **Espelho.** O `plug_server` mantem orientacoes para o agente em
> `plug_server/docs/plug_agente/`. Esta pasta e o inverso: o que o **hub**
> deve implementar quando o agente anuncia as novas extensoes de transporte.
>
> **Fonte normativa do agente.** Schemas e OpenRPC em
> `docs/communication/schemas/` e `docs/communication/openrpc.json`;
> codigo em `lib/domain/protocol/transport_extension_negotiation.dart` e
> `lib/application/services/protocol_negotiator.dart`.

## Resumo executivo

O `plug_server` implementou o lado hub em
[`560ef2f`](https://github.com/cesar-carlos/plug_server/commit/560ef2f) (2026-06-24).
O agente anuncia as extensoes em
[`741b5677`](https://github.com/cesar-carlos/plug_agente/commit/741b5677).
Comportamento ativo apos **deploy coordenado** e handshake com intersecao
das tres chaves em `negotiatedExtensions`.

| Extensao | O hub precisa? | Sem hub | Com hub alinhado |
| -------- | -------------- | ------- | ---------------- |
| `clientRequestIdEcho: "v1"` | **Sim** (dispatch + forwarder) | Opcao B continua (rewrite `body.id` na resposta) | Opcao A: `body.id` do consumer end-to-end; bypass de re-encode |
| `agentPhaseTimings: "v1"` | **Sim** (anunciar extensao) | Agente nao anexa `meta.agent_phases` | Consumer com `requestServerTimings: true` recebe fases do agente |
| `healthPiggyback: { intervalRequests, freshnessThresholdMs }` | **Sim** (anunciar + consumir snapshot) | Agente nao piggybacka saude | `meta.health_snapshot` em respostas unary; metricas de poll vs piggyback |

Itens que **nao** exigem mudanca no hub (ja funcionam so no agente):

- Acks e replay guard por `meta.request_id` (wire id do hub)
- Coalescing `rpc:batch_ack`
- Migracao de prefs legadas (`enableSocketDeliveryGuarantees`, etc.)
- Pre-warm de schemas no agente

## Como ler

1. [`01_transport_extensions.md`](01_transport_extensions.md) — contrato,
   comportamento esperado e arquivos do hub a tocar.
2. [`02_implementation_checklist.md`](02_implementation_checklist.md) —
   checklist por arquivo, testes e validacao pos-deploy.
3. ADRs no repositorio irmao: `plug_server/docs/adrs/0009-*.md`,
   `0010-*.md`, `0011-*.md`.
4. Roadmap cross-repo: `plug_server/docs/plug_agente/03_performance_roadmap.md`.

## Politica de mudancas nesta pasta

- Atualize quando o agente passar a depender de comportamento novo no hub.
- Nao duplique o contrato normativo — aponte para schemas e ADRs.
- Mantenha paths relativos ao checkout lado-a-lado (`../plug_server/`).
