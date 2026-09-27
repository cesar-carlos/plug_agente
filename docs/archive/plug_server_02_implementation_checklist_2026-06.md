# Checklist de implementacao — `plug_server` (ARCHIVE)

Arquivado em 2026-07-22. A onda foi entregue em 2026-06-24
(hub [`560ef2f`](https://github.com/cesar-carlos/plug_server/commit/560ef2f),
agente [`741b5677`](https://github.com/cesar-carlos/plug_agente/commit/741b5677)).

Inclui o scheduler opcional de `agent.getHealth`
(`AGENT_HEALTH_POLL_ENABLED`, default `false`). Nao ha item de codigo
aberto nesta lista.

Nao use esta pagina como guia de PR. O texto anterior repetia arquivos,
testes e checkboxes `[x]` que ja estao nos ADRs.

- Resumo: [`docs/plug_server/readme.md`](../plug_server/readme.md)
- Contrato: [`docs/plug_server/01_transport_extensions.md`](../plug_server/01_transport_extensions.md)
- ADRs no hub: `0009` (`clientRequestIdEcho`), `0011` (health piggyback),
  `0012` (`agentPhaseTimings`). ADR `0010` e presenca Redis, nao esta onda.
- Aberto, fora deste checklist: compressao brotli (roadmap item 10 no hub).
