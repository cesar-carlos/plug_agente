# Extensoes de transporte — estado no hub

Entregue em 2026-06-24
(hub [`560ef2f`](https://github.com/cesar-carlos/plug_server/commit/560ef2f),
agente [`741b5677`](https://github.com/cesar-carlos/plug_agente/commit/741b5677)).
O agente so liga cada feature quando `ProtocolNegotiator` ve intersecao com
`agent:capabilities`.

Contrato normativo: ADRs no `plug_server`. Esta pagina nao e guia de
implementacao.

| Extensao | ADR | Quando negociada |
| -------- | --- | ---------------- |
| `clientRequestIdEcho: "v1"` | [0009](../../../plug_server/docs/adrs/0009-client-request-id-echo.md) | `body.id` permanece o id do consumer. `meta.request_id` e `PayloadFrame.requestId` continuam o UUID do hub. Sem a extensao, o hub reescreve `body.id` na volta (Opcao B). |
| `agentPhaseTimings: "v1"` | [0012](../../../plug_server/docs/adrs/0012-agent-phase-timings.md) | `meta.agent_phases` so se o consumer pediu `requestServerTimings: true`. O hub descarta o campo se a extensao nao foi negociada. |
| `healthPiggyback` | [0011](../../../plug_server/docs/adrs/0011-health-piggyback.md) | `meta.health_snapshot` em respostas unary. Nao autoriza nada. |

ADR **0010** e presenca Redis do hub
([`0010-agent-hub-presence-redis.md`](../../../plug_server/docs/adrs/0010-agent-hub-presence-redis.md)),
nao phase timings.

## Health poll

O scheduler existe (`agent_health_poll_scheduler.ts`). Fica **desligado**
por defeito (`AGENT_HEALTH_POLL_ENABLED=false`) e, quando ligado, pula o
poll se o piggyback ainda esta fresco (`shouldSkipScheduledHealthPoll`).
Nao e o probe HTTP `GET /health` do reconnect L0–L2 — esse fluxo esta no
[standard](../communication/socket_communication_standard.md).

## O que o hub nao muda por causa destas extensoes

| Topico | Motivo |
| ------ | ------ |
| Ack / replay por `meta.request_id` | O hub ja envia esse id em todo `rpc:request` |
| `rpc:batch_ack` | Coalescing e so no agente |
| Defaults de ack e streaming chunks | Prefs locais do agente |
| Brotli | Fora desta onda; ver o study no hub |

## Validacao apos deploy coordenado

1. `negotiatedExtensions` contem as tres chaves.
2. Com Opcao A, consumer e agente veem o mesmo `body.id`.
3. `requestServerTimings: true` devolve `meta.agent_phases`.
4. `plug_socket_relay_body_id_echo_total` fica ~0 com a extensao ativa.
5. `plug_agent_health_piggyback_used_total` sobe em agente negociado.

Checklist de implementacao de 2026-06:
[`docs/archive/plug_server_02_implementation_checklist_2026-06.md`](../archive/plug_server_02_implementation_checklist_2026-06.md).
