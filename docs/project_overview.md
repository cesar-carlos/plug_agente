# Plug Agente - Visao Geral do Projeto

## Objetivo

O `plug_agente` e uma aplicacao desktop Windows que executa operacoes locais
(SQL via ODBC, acoes agendadas, comandos do sistema) em nome de consumidores
remotos, sem que esses consumidores precisem alcancar o ambiente local
diretamente.

O agente nao escuta porta publica nem expoe servico ao exterior. Em vez disso,
ele inicia uma conexao Socket.IO **de saida** para um hub central
(`plug_server`), recebe requisicoes JSON-RPC autenticadas pelo hub, executa
localmente e devolve a resposta pelo mesmo canal.

## Papel no ecossistema

```text
[ consumer ] --REST/Socket.IO--> [ plug_server (hub) ] --Socket.IO--> [ plug_agente ]
                                                                          |
                                                                          v
                                                                    [ ODBC / OS ]
```

- O **consumer** (web app, painel, sistema interno) fala com o hub.
- O **hub** autentica, autoriza, roteia, correlaciona request/response e
  registra observabilidade.
- O **agente** executa o trabalho real: queries ODBC, acoes agendadas,
  comandos locais. Mantem conexao persistente, heartbeat e reconexao
  automatica.

Detalhes do hub (autenticacao, namespaces, persistencia central) ficam fora do
escopo deste repositorio. Esta visao geral cobre o que o `plug_agente` faz e
quais contratos ele honra.

## Responsabilidades do agente

- Conectar ao hub via Socket.IO no namespace `/agents`, normalizando a URL
  base se necessario.
- Autenticar no handshake com JWT (`role: agent`, claim `agent_id`).
- Registrar identidade e capacidades (`agent:register`, `agent:capabilities`).
- Sinalizar prontidao (`agent:ready`) apos o protocolo efetivo.
- Manter heartbeat de sessao (`agent:heartbeat` / `hub:heartbeat_ack`).
- Receber `rpc:request` e responder com `rpc:response` em `PayloadFrame`.
- Suportar streaming chunked, backpressure e ack de entrega quando o hub
  habilitar.
- Executar SQL via ODBC com fila bounded, pool, circuit breaker e
  cancelamento.
- Executar acoes agendadas locais (`agent.action.*`) com auditoria, retencao
  e isolamento (commandLine, executable, script, jar, email, comObject,
  developer Data7).
- Auto-update silencioso assinado com appcast.

## Metodos JSON-RPC publicados

| Metodo | Side effect | Observacao |
| --- | --- | --- |
| `sql.execute` | Sim | Query parametrizada, paginacao por page/cursor |
| `sql.executeBatch` | Sim | Multiplos comandos, opcionalmente transacional |
| `sql.bulkInsert` | Sim | Bulk insert nativo do `odbc_fast` |
| `sql.cancel` | Sim | Cancela request em execucao (feature flag) |
| `agent.getProfile` | Nao | Profile do agente |
| `agent.getHealth` | Nao | Pool, fila, runtime tuning, scheduler, retention |
| `agent.action.run` | Sim | Enfileira acao salva e aprovada (idempotency_key obrigatorio) |
| `agent.action.validateRun` | Nao | Preflight remoto (sem persistir nem iniciar) |
| `agent.action.cancel` | Sim | Cancela fila ou processo principal |
| `agent.action.getExecution` | Nao | Leitura redigida da execucao |
| `client_token.getPolicy` | Nao | Politica de autorizacao do token |
| `rpc.discover` | Nao | OpenRPC do agente |

Contrato canonico em `docs/communication/socket_communication_standard.md`.
OpenRPC em `docs/communication/openrpc.json`. Schemas em
`docs/communication/schemas/`.

## Camadas

```text
lib/
|- domain/         # entidades, contratos, failures, protocolo
|- application/    # use cases, fila SQL, agendador, mapeamentos
|- infrastructure/ # ODBC, transporte, datasources, repositories, codecs
|- presentation/   # boot, pages, providers, controllers, widgets
|- core/           # config, DI, routes, theme, logger, runtime, utils
|- l10n/           # localizacao gerada (en/pt) e ARB
\- shared/         # componentes e widgets compartilhados
```

Direcao de dependencias: `presentation -> application -> domain`,
`infrastructure` implementa contratos do `domain`. Ports (interfaces) vivem em
`lib/domain/repositories/`; `infrastructure` implementa esses contratos.
Enforcement automatizado: `test/architecture/layer_boundaries_test.dart`.
Detalhes em `.cursor/rules/clean_architecture.mdc`.

### Sql RPC (mapa para maintainers)

Handlers SQL foram modularizados em `lib/application/rpc/`:

| Modulo | Responsabilidade |
| --- | --- |
| `sql_rpc_method_handler_operations.dart` | Facade que compoe os handlers abaixo |
| `sql_execute_handler.dart` | `sql.execute` (materializado e streaming) |
| `sql_batch_handler.dart` | `sql.executeBatch` |
| `sql_bulk_insert_handler.dart` | `sql.bulkInsert` |
| `sql_cancel_handler.dart` | `sql.cancel` |
| `sql_rpc_db_streaming_executor.dart` / `sql_rpc_materialized_streaming_executor.dart` | Caminhos de streaming DB vs materializado |
| `sql_streaming_coordinator.dart` | Orquestracao de stream terminal/chunks |
| `sql_rpc_client_token_gate.dart` / `sql_authorization_fingerprint.dart` | Autorizacao e fingerprint de policy |
| `sql_rpc_handler_support.dart` | Helpers compartilhados entre handlers |

## Persistencia e estado

- `drift` (schema **v30**) para historico de execucoes, auditoria de RPC,
  idempotencia, cache de tokens, `agent_action_remote_audit`.
- **Drift v29–v30 — ODBC credential externalization:** senhas ODBC saem de
  `config_table` para `flutter_secure_storage` via `OdbcCredentialStore`
  (`IOdbcCredentialStore` / `IOdbcCredentialSecretStore`). v29 introduziu o
  fluxo de lazy migration on read; **v30 remove a coluna plaintext `password`**
  apos copiar stragglers remanescentes para o secure store na migration.
- `flutter_secure_storage` particionado por dominio:
  - **ODBC** — credenciais de conexao (`FlutterSecureOdbcCredentialSecretStore`)
  - **Hub auth** — tokens/sessao do hub (`FlutterSecureHubAuthSecretStore`)
  - **Client tokens** — politicas de autorizacao local
    (`FlutterSecureTokenSecretStore`)
  - Payload signing keys e segredos de acoes agendadas usam stores dedicados no
    mesmo mecanismo.
- `shared_preferences` para flags leves.
- **Backup local:** por padrao o export omite segredos (`includeSecureStorageSecrets:
  false` na UI e no servico); o manifest ZIP declara `odbcSecretsIncluded` conforme
  a escolha do operador. Opt-in explicito inclui entradas elegiveis de
  `flutter_secure_storage` — ver `LocalAppDataBackupService` e
  `BackupConfigSection`.

## Seguranca

- JWT obrigatorio no handshake (`role: agent`).
- Token claim `agent_id` validado contra o `agentId` do payload de register.
- `PayloadFrame` opcional com HMAC-SHA256; ativado por `enablePayloadSigning`.
- Auditoria append-only para RPC remoto (`agent_action_remote_audit`).
- Allowlist por escopo + `action_ids` para `agent.action.*`.
- Threat model do auto-update em `docs/security/auto_update_threat_model.md`.

## Runtime desktop

- Janela controlada por `window_manager`; tray por `tray_manager`.
- Single-instance por mutex global (uma instancia por maquina).
- Auto-update silencioso com helper assinado.

## Funcionalidades alvo

- Execucao remota de SQL (com pool ODBC, fila bounded e circuit breaker).
- Execucao agendada e remota de acoes locais.
- Streaming chunked com backpressure.
- Auto-update assinado com appcast.
- Observabilidade via `agent.getHealth`.

## Estado atual

Implementado e em homologacao:

- API HTTP do hub consumida (auth, refresh).
- Socket.IO `/agents` com handshake, register, capabilities, ready, heartbeat.
- JSON-RPC com `PayloadFrame` binario obrigatorio (compressao GZIP por
  threshold).
- Pool ODBC lease-based + adaptativo (drivers elegiveis), circuit breaker,
  warm-up, fila SQL com backpressure.
- `agent.action.*` com auditoria, idempotencia, fila, scheduler IANA.
- Auto-update silencioso (`Sparkle`-like) com assinatura Ed25519 do feed em
  rollout.

Detalhes vivos em:

- `docs/communication/socket_communication_standard.md`
- `docs/communication/socket_communication_roadmap.md` (changelog)
- `docs/communication/socket_communication_backlog.md` (pendencias)
- `docs/architecture/performance_reliability_improvements.md`
- `docs/implemente/plano_acoes_agendadas_execucoes.md`
- `docs/implemente/plano_auto_update_evolution.md`
