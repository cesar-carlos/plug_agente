# Socket Communication Roadmap (Planned Improvements)

## Objetivo

Este roadmap lista apenas evolucoes ainda pendentes.
Itens concluidos foram removidos para evitar ruido.

Estado implementado atual:
`docs/communication/socket_communication_standard.md`.

## Itens planejados (pendentes)

| Item | Status | Fase alvo |
| --- | --- | --- |
| `api_version` + `meta` obrigatorios por contrato | planned | Fase 1 |
| Semantica formal de notification JSON-RPC | planned | Fase 1 |
| Regras formais de batch (ordem, IDs, atomicidade) | planned | Fase 1 |
| Politica de versao e deprecacao | planned | Fase 1 |
| Limites negociados (`max_payload_bytes`, `max_rows`) | planned | Fase 5 |
| Assinatura opcional de payload | planned | Fase 5 |

## Fase 1 - Contrato e governanca

Objetivo:

- Formalizar requisitos de contrato que ainda estao opcionais.

Escopo:

- Tornar `api_version` + `meta` obrigatorios.
- Formalizar notification (request sem `id`) no contrato.
- Formalizar regras de batch (IDs unicos, ordenacao, limites).
- Publicar politica de versao e deprecacao.

## Fase 5 - Hardening residual

Objetivo:

- Completar hardening de seguranca/operacao ainda nao entregue.

Escopo:

- Definir limites negociados por transporte (`max_payload_bytes`, `max_rows`).
- Definir assinatura opcional de payload.

## Criterio de rollout

- Manter dual-stack durante migracao.
- Liberar por feature flag, quando aplicavel.
- Promover para default apenas apos compatibilidade validada com clientes.

## Checklist de prontidao para cada item pendente

- [ ] Contrato/documentacao atualizado.
- [ ] Testes unitarios adicionados.
- [ ] Testes de integracao executados.
- [ ] Feature flag criada (quando aplicavel) e validada.
- [ ] Metricas e logs de observabilidade adicionados.
