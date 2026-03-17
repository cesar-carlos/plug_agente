# Guia de Migracao: plug_agente para Namespaces no agente_server

Este documento descreve o que precisa ser ajustado no **plug_agente**
(ou em qualquer cliente agente) para operar de forma compativel com o
**agente_server** no modelo de namespaces `/agents` e `/consumers`.

Publico-alvo: equipes que mantem o plug_agente e integracoes Socket.IO de agentes.

---

## 1. Contexto

O agente_server separa os papeis em namespaces diferentes:

| Namespace | Papel | Roles aceitos (JWT) |
| --- | --- | --- |
| `/agents` | agente | configurado por `SOCKET_AGENT_ROLES` |
| `/consumers` | consumer | configurado por `SOCKET_CONSUMER_ROLES` |

Conexoes no namespace padrao `/` nao recebem o fluxo de registro/comandos do agente.
O agente deve conectar em `/agents`.

---

## 2. Resumo das mudancas obrigatorias

| # | Ajuste | Obrigatorio |
| --- | --- | --- |
| 1 | Conectar em `/agents` (nao em `/`) | Sim |
| 2 | Enviar token no handshake (`auth.token` ou `Authorization`) | Sim |
| 3 | Enviar `agentId` no `agent:register` | Sim |
| 4 | Se o token tiver `agent_id`, manter `agentId` identico no register | Sim |
| 5 | Usar transporte `PayloadFrame` binario para eventos de aplicacao | Sim (producao) |

---

## 3. Conexao Socket.IO

### 3.1 Namespace

No plug_agente atual, a URL passada para conexao e usada diretamente por `io.io(url, ...)`.
Isso significa que a URL deve apontar para o namespace correto.

Exemplo:

```text
wss://hub.example.com/agents
```

Se usar apenas `wss://hub.example.com`, o cliente pode conectar sem entrar no
fluxo esperado de agente.

### 3.2 Token no handshake

O servidor aceita token em:

1. `auth.token`
2. Header `Authorization: Bearer <token>`

No cliente atual (`plug_agente`), o envio padrao implementado e via `auth.token`.
Use header apenas se sua implementacao customizada suportar essa opcao.

Exemplo JavaScript:

```javascript
const socket = io("https://hub.example.com/agents", {
  path: "/socket.io",
  transports: ["websocket"],
  auth: { token: accessToken },
});
```

---

## 4. Autenticacao e endpoints

Para compatibilidade, o agente_server pode expor duas familias de endpoints:

| Metodo | Endpoint | Uso |
| --- | --- | --- |
| POST | `/auth/login` | fluxo usado hoje pelo plug_agente |
| POST | `/api/v1/auth/login` | variante versionada |
| POST | `/auth/agent-login` | recomendado quando o servidor exige role `agent` + `agent_id` |
| POST | `/api/v1/auth/agent-login` | variante versionada |
| POST | `/auth/refresh` | refresh (fluxo atual do plug_agente) |
| POST | `/api/v1/auth/refresh` | variante versionada |

### 4.1 Fluxo atual do plug_agente

Hoje o cliente usa `username` + `password` em `/auth/login` e `refreshToken` em `/auth/refresh`.

### 4.2 Fluxo recomendado para ambiente estrito de agente

Quando o agente_server estiver com policy estrita para `/agents`, prefira `agent-login`
enviando tambem `agentId`, para receber token com claims de agente.

---

## 5. Evento `agent:register`

Payload logico esperado:

| Campo | Tipo | Obrigatorio |
| --- | --- | --- |
| `agentId` | string | Sim |
| `capabilities` | object | Sim |
| `timestamp` | string ISO8601 | Recomendado |

Regra de consistencia:

- se o JWT tiver `agent_id`, o valor de `agent:register.agentId` deve ser o mesmo;
- em caso de divergencia, o servidor deve rejeitar o registro.

---

## 6. Transporte binario (PayloadFrame)

Para eventos de aplicacao do agente (`agent:register`, `rpc:*`, `agent:heartbeat`),
o contrato de producao usa `PayloadFrame` binario com JSON UTF-8 e compressao opcional.

Observacao de rollout:

- pode existir compatibilidade temporaria para JSON cru dependendo de feature flags;
- em producao, trate `PayloadFrame` como obrigatorio.

Referencia de contrato:

- `docs/communication/socket_communication_standard.md`
- `docs/communication/socketio_client_binary_transport.md`
- `docs/communication/schemas/`

---

## 7. Fluxo recomendado ponta a ponta

```text
1. Obter token (login ou agent-login, conforme policy do servidor)
2. Conectar Socket.IO em /agents com token no handshake
3. Emitir agent:register com { agentId, capabilities, timestamp }
4. Receber agent:capabilities
5. Processar rpc:request e responder via rpc:response
6. Manter heartbeat (agent:heartbeat / hub:heartbeat_ack)
7. Renovar token com refresh e reconectar quando necessario
```

---

## 8. Checklist de migracao

- [ ] URL de conexao do agente aponta para `/agents`
- [ ] Handshake envia token valido
- [ ] `agent:register` inclui `agentId` e `capabilities`
- [ ] `agentId` do register bate com claim `agent_id` (quando presente)
- [ ] Pipeline de `PayloadFrame` binario habilitado no cliente
- [ ] Fluxo de refresh/reconnect validado em staging

---

## 9. Erros comuns

| Erro | Causa comum | Acao recomendada |
| --- | --- | --- |
| Conecta, mas nao recebe eventos de agente | URL sem `/agents` | Corrigir URL para namespace do agente |
| `Role ... is not allowed to connect to /agents` | token com role fora de `SOCKET_AGENT_ROLES` | Ajustar policy de role ou usar endpoint de login apropriado |
| `agent:register agentId does not match token claim` | `agentId` diferente do claim `agent_id` | Usar o mesmo `agentId` no login/register |
| Falha de decode em eventos | cliente enviando/esperando JSON cru fora do contrato | Garantir encode/decode de `PayloadFrame` |

---

## 10. Referencias

- `docs/project_overview.md`
- `docs/communication/socket_communication_standard.md`
- `docs/communication/socketio_client_binary_transport.md`
- `docs/communication/openrpc.json`
- `docs/communication/schemas/`
