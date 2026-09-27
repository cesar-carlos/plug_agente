# Orientacoes para `plug_server` — extensoes de transporte

> **Audiencia.** Time do `plug_server`. Espelho inverso de
> `plug_server/docs/plug_agente/`.
>
> **Fonte normativa do agente.** `docs/communication/`.
> **Fonte normativa do hub.** ADRs `0009`, `0011` e `0012`.

## Status

Hub [`560ef2f`](https://github.com/cesar-carlos/plug_server/commit/560ef2f)
e agente [`741b5677`](https://github.com/cesar-carlos/plug_agente/commit/741b5677)
(2026-06-24). As tres extensoes so valem depois do deploy coordenado, quando
o handshake coloca a intersecao em `negotiatedExtensions`.

| Extensao | Sem negociacao | Com hub alinhado |
| -------- | -------------- | ---------------- |
| `clientRequestIdEcho: "v1"` | Opcao B (rewrite de `body.id`) | `body.id` end-to-end |
| `agentPhaseTimings: "v1"` | Sem `meta.agent_phases` | Fases quando `requestServerTimings: true` |
| `healthPiggyback` | Sem piggyback | `meta.health_snapshot` em respostas unary |

Poll agendado de `agent.getHealth` existe e fica desligado por defeito.
Itens so no agente: ack/replay por `meta.request_id`, coalescing
`rpc:batch_ack`, prefs legadas, pre-warm de schemas.

ADR **0010** nao faz parte desta tabela: e presenca Redis no hub.

## Como ler

1. [`01_transport_extensions.md`](01_transport_extensions.md) — efeito no fio e validacao.
2. ADRs no hub: `0009`, `0011`, `0012`.
3. Nota de arquivo (onda concluida):
   [`archive/...checklist...`](../archive/plug_server_02_implementation_checklist_2026-06.md).
4. Status cross-repo: `plug_server/docs/plug_agente/README.md`.

## Politica

- Atualize quando o agente passar a depender de comportamento novo no hub.
- Nao duplique o contrato — aponte para schemas e ADRs.
- Paths relativos assumem checkout lado a lado (`../plug_server/`).
