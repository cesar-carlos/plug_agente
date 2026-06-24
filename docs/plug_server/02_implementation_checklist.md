# Checklist de implementacao — `plug_server`

Checklist para o time do hub alinhar com a onda de performance do
`plug_agente` (extensoes ADR 0009/0010/0011). Use como guia de PR e
homologacao.

## Pre-requisitos no agente (ja entregues neste repo)

- [x] Anunciar extensoes em `ProtocolCapabilities.defaultCapabilities()`
- [x] Negociar intersecao em `ProtocolNegotiator`
- [x] Wire ack / replay por `meta.request_id` (`rpc_wire_ack_id.dart`)
- [x] `meta.agent_phases` quando `requestServerTimings: true`
- [x] `meta.health_snapshot` via `RpcHealthPiggybackSampler`
- [x] Schemas `rpc.request.schema.json` / `rpc.response.schema.json`
- [x] Testes: `protocol_negotiator_test`, `rpc_inbound_response_enricher_test`, etc.

## Checklist no `plug_server`

### Contrato e negociacao

- [ ] `HUB_TRANSPORT_EXTENSIONS` inclui `clientRequestIdEcho`, `agentPhaseTimings`, `healthPiggyback`
- [ ] `transport_extension_negotiation.ts` com helpers de intersecao
- [ ] Testes unitarios do contrato e negociacao

**Arquivos:**

| Arquivo | Acao |
| ------- | ---- |
| `src/shared/constants/agent_transport_contract.ts` | Adicionar 3 extensoes |
| `src/shared/constants/transport_extension_negotiation.ts` | Criar helpers |
| `tests/unit/shared/constants/agent_transport_contract.test.ts` | Assert extensoes |
| `tests/unit/shared/constants/transport_extension_negotiation.test.ts` | Criar |

### ADR 0009 — client request id echo

- [ ] Dispatch relay usa `client_request_id` como `body.id` quando negociado
- [ ] `meta.request_id` permanece UUID do hub
- [ ] Forwarder compara `body.id` da resposta com `clientRequestId` (nao hub UUID)
- [ ] Teste e2e cross-module fast-path + Opcao A

**Arquivos:**

| Arquivo | Acao |
| ------- | ---- |
| `src/presentation/socket/hub/relay/rpc_bridge_dispatch_relay.ts` | Gate `rpcBodyId` |
| `src/presentation/socket/hub/relay/relay_route_response_forwarder.ts` | Fix `shouldEchoClientBodyId` |
| `tests/unit/presentation/socket/hub/relay_fast_path_body_id_echo.e2e.test.ts` | Caso Opcao A |

### ADR 0010 — agent phase timings

- [ ] Hub anuncia `agentPhaseTimings: "v1"`
- [ ] Forwarder/bridge nao remove `meta.agent_phases` das respostas
- [ ] (Opcional) Documentar em `communication_sync_plug_agente.md`

**Arquivos:** principalmente `agent_transport_contract.ts`; revisar forwarder se houver mutacao de `meta`.

### ADR 0011 — health piggyback

- [ ] Servico para validar frescor e registrar snapshot
- [ ] Hook no forwarder relay (respostas unary que nao sao `agent.getHealth`)
- [ ] Metricas `plug_agent_health_poll_total` e `plug_agent_health_piggyback_used_total`
- [ ] `agentRegistry.shouldSkipScheduledHealthPoll()` + limpeza no disconnect
- [ ] Testes do servico de piggyback

**Arquivos:**

| Arquivo | Acao |
| ------- | ---- |
| `src/application/services/agent_health_piggyback.service.ts` | Criar |
| `src/presentation/socket/hub/relay/relay_route_response_forwarder.ts` | Chamar `maybeRecordAgentHealthPiggyback` |
| `src/presentation/socket/hub/registries/agent_registry.ts` | Skip hook + clear |
| `src/shared/metrics/socket_agent.metrics.ts` | Contadores poll/piggyback |
| `src/presentation/http/controllers/metrics_renderer.ts` | Expor metricas |
| `tests/unit/application/services/agent_health_piggyback.service.test.ts` | Criar |

### Opcional / futuro

- [ ] Scheduler de `agent.getHealth` que chama `shouldSkipScheduledHealthPoll` antes de poll
- [ ] Brotli alinhado hub + agente (roadmap item 10)
- [ ] Atualizar `plug_server/docs/plug_agente/04_agent_implementation_status.md` apos release

## Comandos de teste (hub)

```bash
cd plug_server
npm test -- tests/unit/shared/constants/agent_transport_contract.test.ts \
  tests/unit/shared/constants/transport_extension_negotiation.test.ts \
  tests/unit/application/services/agent_health_piggyback.service.test.ts \
  tests/unit/presentation/socket/hub/relay_fast_path_body_id_echo.e2e.test.ts \
  tests/unit/presentation/socket/hub/rpc_bridge_agent_inbound.test.ts
```

## Validacao pos-deploy (E2E)

1. Handshake agente: inspecionar log ou estado de `negotiatedExtensions` —
   deve conter `clientRequestIdEcho`, `agentPhaseTimings`, `healthPiggyback`.
2. Relay fast-path com `id` do consumer:
   - Com Opcao A: agente recebe `body.id == client_id`; consumer recebe o mesmo sem rewrite.
3. Request com `meta.requestServerTimings: true`:
   - Resposta relay inclui `meta.agent_phases` (mapa de fases em ms).
4. Apos ~50 respostas unary em agente ativo:
   - Resposta inclui `meta.health_snapshot` com `captured_at_ms` recente.
5. Metricas hub:
   - `plug_agent_health_piggyback_used_total` cresce em agentes negociados.
   - `plug_socket_relay_body_id_echo_total` ~0 com Opcao A ativa.

## Referencias cruzadas

| Documento | Repositorio |
| --------- | ----------- |
| `docs/plug_server/readme.md` | `plug_agente` (esta pasta) |
| `docs/plug_agente/README.md` | `plug_server` |
| `docs/plug_agente/03_performance_roadmap.md` | `plug_server` |
| `docs/adrs/0009-*.md` | `plug_server` |
| `docs/communication/socket_communication_standard.md` | `plug_agente` |
