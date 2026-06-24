# Extensoes de transporte — ajustes no `plug_server`

Contrato negociado via `extensions` em `agent:register` / `agent:capabilities`.
O agente so habilita cada feature quando `ProtocolNegotiator` encontra
intersecao com as capabilities ecoadas pelo hub.

## 1. Anunciar extensoes no contrato do hub

**Arquivo dono:** `plug_server/src/shared/constants/agent_transport_contract.ts`

Incluir em `HUB_TRANSPORT_EXTENSIONS` (valores alinhados ao agente):

```typescript
clientRequestIdEcho: "v1",
agentPhaseTimings: "v1",
healthPiggyback: {
  intervalRequests: 50,
  freshnessThresholdMs: 5000,
},
```

`buildHubServerCapabilities()` ja copia `HUB_TRANSPORT_EXTENSIONS` para o
payload de `agent:capabilities` — nao e necessario codigo extra ai.

**Teste:** `tests/unit/shared/constants/agent_transport_contract.test.ts`

**Helpers de negociacao (recomendado):**
`plug_server/src/shared/constants/transport_extension_negotiation.ts`

```typescript
isClientRequestIdEchoNegotiated(agentCapabilities)
isAgentPhaseTimingsNegotiated(agentCapabilities)
isHealthPiggybackNegotiated(agentCapabilities)
```

Comparacao: valor em `capabilities.extensions.<key>` deve ser **igual** ao
hub para `clientRequestIdEcho` / `agentPhaseTimings`; para
`healthPiggyback`, ambos devem ser objetos.

---

## 2. ADR 0009 — `clientRequestIdEcho` (Opcao A)

**Referencias:** `plug_server/docs/adrs/0009-client-request-id-echo.md`,
`plug_server/docs/plug_agente/01_relay_body_id_echo.md`

### Problema (Opcao B, legado)

O hub sobrescreve `body.id` com o UUID interno antes de despachar ao
agente e reescreve de volta para o `client_request_id` na resposta relay.
Funciona, mas forca re-encode e metricas `plug_socket_relay_body_id_echo_*`.

### Comportamento negociado (Opcao A)

Quando o agente registrou `extensions.clientRequestIdEcho === "v1"`:

| Campo | Valor no dispatch relay |
| ----- | ------------------------ |
| `body.id` | `client_request_id` do consumer |
| `meta.request_id` | UUID interno do hub (inalterado) |
| `PayloadFrame.requestId` | UUID interno do hub |

**Arquivo:** `plug_server/src/presentation/socket/hub/relay/rpc_bridge_dispatch_relay.ts`

```typescript
const registeredAgent = agentRegistry.findByAgentId(conversation.agentId);
const echoClientRequestId =
  clientRequestId != null &&
  registeredAgent != null &&
  isClientRequestIdEchoNegotiated(registeredAgent.capabilities);
const rpcBodyId = echoClientRequestId ? clientRequestId : requestId;
// commandPayload.id = rpcBodyId; meta.request_id = requestId;
```

### Forwarder — nao reescrever `body.id` quando o agente ja ecoou

**Arquivo:** `plug_server/src/presentation/socket/hub/relay/relay_route_response_forwarder.ts`

`shouldEchoClientBodyId` deve comparar o **`id` do JSON-RPC decodificado**
com `relayRoute.clientRequestId`, nao com `relayRoute.requestId`:

```typescript
const decodedBodyId = toRequestId(decodedResponseRecord?.id);
const shouldEchoClientBodyId =
  relayRoute.clientRequestId !== undefined &&
  decodedBodyId !== relayRoute.clientRequestId;
```

Efeito: com Opcao A, `canBypassReencode` volta a ser true e
`plug_socket_relay_body_id_echo_total` permanece ~0.

**Teste:** `tests/unit/presentation/socket/hub/relay_fast_path_body_id_echo.e2e.test.ts`
(caso `clientRequestIdEcho` negociado).

---

## 3. ADR 0010 — `agentPhaseTimings`

**Referencia:** `plug_server/docs/adrs/0010-agent-phase-timings.md`

### No agente

Quando a extensao esta negociada **e** o consumer envia
`meta.requestServerTimings: true`, o agente anexa `meta.agent_phases` na
resposta unary (sub-fases ODBC, fila SQL, preparacao, etc.).

### No hub

1. **Anunciar** `agentPhaseTimings: "v1"` em `HUB_TRANSPORT_EXTENSIONS`
   (secao 1).
2. **Pass-through:** o forwarder relay ja re-encoda quando
   `requestServerTimings` esta ativo (`meta.serverTimings` do hub). Nao
   remover nem sobrescrever `meta.agent_phases` ao encaminhar a resposta
   do agente ao consumer.
3. **Schema:** campo opcional em `plug_agente/docs/communication/schemas/rpc.response.schema.json`
   (`agent_phases` / `health_snapshot` em `meta`).

Nao e necessario logica extra no dispatch — apenas negociacao + preservar
meta na cadeia relay/bridge.

---

## 4. ADR 0011 — `healthPiggyback`

**Referencia:** `plug_server/docs/adrs/0011-health-piggyback.md`

### Forma no wire (resposta do agente)

```json
{
  "meta": {
    "health_snapshot": {
      "captured_at_ms": 1719234567890,
      "freshness_threshold_ms": 5000,
      "sql_queue_pressure": 0.42,
      "active_streams": 2,
      "circuit_state": "closed",
      "status": "healthy"
    }
  }
}
```

O agente amostra a cada `intervalRequests` respostas unary (default 50).

### Ajustes no hub

| Responsabilidade | Arquivo sugerido |
| ---------------- | ---------------- |
| Ler snapshot fresco e atualizar metricas | `src/application/services/agent_health_piggyback.service.ts` |
| Hook no forwarder relay (nao-`agent.getHealth`) | `relay_route_response_forwarder.ts` |
| `shouldSkipScheduledHealthPoll(agentId)` | `agent_registry.ts` (delegacao) |
| Metricas Prometheus | `src/shared/metrics/socket_agent.metrics.ts`, `metrics_renderer.ts` |

Metricas ADR:

- `plug_agent_health_poll_total` — cada `agent.getHealth` explicito
- `plug_agent_health_piggyback_used_total` — snapshot aceito dentro da janela de frescor

Regras:

- Ignorar snapshot quando `now - captured_at_ms > freshnessThresholdMs`
- So processar quando `isHealthPiggybackNegotiated(capabilities)`
- **Nunca** usar piggyback para autorizacao — somente observabilidade
- Limpar estado por agente em `agentRegistry.removeBySocketId`

### Pendente opcional no hub

O ADR prevê **pular polls agendados** de `agent.getHealth` quando o
piggyback esta fresco. O hook `shouldSkipScheduledHealthPoll` existe; um
**scheduler/timer** de poll ainda nao esta implementado no hub (gate de
prod: so vale a pena se o volume de poll for material).

---

## 5. O que o hub nao precisa mudar

| Topico | Motivo |
| ------ | ------ |
| `meta.request_id` no ack do agente | Agente usa wire id; hub ja envia em todo `rpc:request` |
| Replay / idempotency relay | Agente indexa por `meta.request_id` |
| `rpc:batch_ack` coalescing | Lado agente apenas |
| Defaults de delivery guarantees / streaming chunks | Prefs locais do agente + migrator no boot |
| Brotli (roadmap item 10) | Coordenacao futura; nenhum dos dois lados shippou |

---

## 6. Deploy coordenado

Ordem recomendada:

1. Deploy hub com extensoes em `HUB_TRANSPORT_EXTENSIONS` + dispatch Opcao A
   + consumo de piggyback.
2. Deploy agente com capabilities + enricher + migrator de prefs.
3. Validar handshake: `negotiatedExtensions` contem as tres chaves.
4. Monitorar:
   - `plug_socket_bridge_ack_retry_attempts_total` → ~0
   - `plug_socket_relay_body_id_echo_total` → ~0 com Opcao A
   - `plug_agent_health_piggyback_used_total` vs `plug_agent_health_poll_total`

Ver checklist detalhado em [`02_implementation_checklist.md`](02_implementation_checklist.md).
