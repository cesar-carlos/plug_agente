# Socket Communication Backlog (Execution Plan)

## Objetivo

Este backlog agora lista apenas itens pendentes de evolucao.
Itens concluidos foram removidos para manter foco no trabalho restante.

Referencia de implementacao atual:
`docs/communication/socket_communication_standard.md`.

## Status atual

- Todos os tickets do plano incremental original (`01` a `06`) foram concluidos.
- Contratos formais (notifications, batch, api_version/meta, schemas, versionamento) publicados.
- Limites de transporte negociados via `TransportLimits` no handshake.
- Assinatura de payload implementada (`PayloadSigner`, HMAC-SHA256) com feature flag `enablePayloadSigning`.
- Feature flags estaveis promovidas para default `true`: `enableClientTokenAuthorization`, `enableSocketApiVersionMeta`, `enableSocketNotificationsContract`, `enableSocketBatchStrictValidation`, `enableSocketSchemaValidation`, `enableSocketCancelMethod`.
- Transporte binario com `PayloadFrame` implementado para todos os eventos de aplicacao.
- Compressao GZIP movida para a borda de transporte com fallback por threshold.

## Politica futura: execution_mode em sql.executeBatch

- Em v2.5, `sql.executeBatch` nao suporta `execution_mode`; todos os comandos rodam
  em modo managed implicito.
- Opcoes para evolucao futura: (A) manter assim; (B) adicionar
  `options.execution_mode` no batch (aplicado a todos os comandos); (C) adicionar
  `commands[*].execution_mode` por comando.
- Decisao a ser tomada quando houver demanda ou requisito de passthrough por
  comando.

## Proximos itens (quando priorizado)

- Homologacao do guia de cliente para encode/compress/decode/decompress.
- Testes de integracao end-to-end para limites negociados e assinatura.
- Rotacao automatica de chaves de assinatura sem downtime.
- Monitoramento/alertas de payload signing failures.

## Regra de manutencao deste backlog

- Registrar apenas itens ainda pendentes.
- Nao reintroduzir itens concluidos.
- Promover um item para `standard` assim que estiver implementado.
