# Plano de Evolucao do Auto-Update

## Objetivo

Evoluir o auto-update silencioso em fases independentes (assinatura do feed,
Authenticode, resiliencia de download, observabilidade, UX, contratos,
diagnostics no hub, rollback), mantendo o repositorio funcional ao fim de cada
fase — sem big-bang.

Este documento guarda apenas o que falta fazer e as decisoes pendentes. O
comportamento ja entregue esta descrito em
[auto_update_setup.md](../install/auto_update_setup.md) e a analise de
seguranca em [auto_update_threat_model.md](../security/auto_update_threat_model.md).

## Status oficial

**2026-09-25**: `[x]` entregue; `[~]` em andamento/diferido; `[ ]` pendente.
Fases 1A-1D, 2A, 2B (doc), 3, 4A, 5, 6A, 9A e 9C entregues. Pendentes:
operacao do feed assinado (1E), review de seguranca (2B), testes de
histograma (4B), 6B/6C, integracao com o hub (7), rollback (8) e chaos tests
(9B).

## Backlog

| Prioridade | ID | Entrega | Status | Bloqueador externo |
| --- | --- | --- | --- | --- |
| P0 | 1A | CI instala `cryptography` e roda `tool.appcast.test_appcast_signing` sem skip | [x] | - |
| P0 | 1B | `AUTO_UPDATE_FEED_PUBLIC_KEY` aceita CSV (rotacao multi-chave) | [x] | - |
| P0 | 1C | Gate `signtool verify /pa` no `release.yml` (installer + helper), pulado sem certificado ou via `skip_authenticode_check` | [x] | - |
| P0 | 1D | `release_preflight.py --feed-public-key` valida pubkey embutida | [x] | - |
| P0 | 1E.1 | Configurar secrets de assinatura e publicar release assinada | [ ] | Decisao 1 |
| P0 | 1E.2 | Ativar `REQUIRE_FEED_SIGNATURE` e `require_valid_update_signature` em producao | [ ] | observacao em campo |
| P0 | 2A | `IHelperSignatureProbe` (Authenticode do helper) antes do spawn | [x] | - |
| P0 | 2B | Threat model documentado; falta review de seguranca | [~] | - |
| P1 | 3A | Pre-flight de espaco em disco (`insufficient_disk_space`) | [x] | - |
| P1 | 3B | Download resumivel HTTP Range (`AUTO_UPDATE_DOWNLOAD_RESUME`) | [x] | - |
| P1 | 4A | Correlation ID UUIDv7 (`checkId`) nas diagnostics | [x] | - |
| P1 | 4B | Histogramas de duracao de probe/download; faltam testes | [~] | - |
| P1 | 5A | Aviso pre-close configuravel (`AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS`) | [x] | - |
| P1 | 5B | Release notes na UI | [x] | - |
| P1 | 5C | Quiet hours (`skippedByQuietHours`) | [x] | - |
| P2 | 6A | `Result<ManualCheckOutcome>` em `checkManual()` | [x] | - |
| P2 | 6B | Schema do launcher status + validacao no CI; falta `json_serializable` | [~] | - |
| P2 | 6C | Extrair `ManualUpdateOrchestrator` | [~] diferido | - |
| P2 | 7A-7C | Push `agent.autoUpdate.diagnostics.push` ao hub | [~] | Decisao 3 |
| P3 | 8A-8B | Backup pre-install + heartbeat/auto-restore no helper | [~] diferido | Decisao 2 |
| Cont. | 9A | Tests de jitter com `package:fake_async` | [x] | - |
| Cont. | 9B | Chaos tests no download | [ ] | - |
| Cont. | 9C | Workflow agendado `feed-smoke.yml` | [x] | - |

## Decisoes operacionais externas

Bloqueiam apenas as fases listadas; o resto continua.

1. **Custodia da chave privada Ed25519** (afeta 1E.1, 1E.2):
   - Opcao A: GitHub Actions Secrets do repo `plug_agente` com rotacao anual.
   - Opcao B: vault corporativo (1Password, HashiCorp Vault).
   - **Status**: pendente decisao.

2. **Pipeline Authenticode** (afeta 1E.2, 8):
   - Existe certificado EV/OV configurado em `WINDOWS_CODE_SIGNING_CERT_BASE64`?
   - **Status**: pendente verificacao.

3. **Evolucao do protocolo Plug** (afeta 7):
   - Time do hub aceita o metodo RPC `agent.autoUpdate.diagnostics.push`?
   - Schema + privacy review feita?
   - **Status**: pendente coordenacao.

## Pendencias por fase

### Fase 1E - Feed assinado em producao

O codigo esta pronto: `update-appcast.yml` assina com
`APPCAST_SIGNING_PRIVATE_KEY`; `release.yml` e `release-preflight.yml` injetam
`AUTO_UPDATE_FEED_PUBLIC_KEY` via `--dart-define` e leem
`vars.AUTO_UPDATE_REQUIRE_FEED_SIGNATURE`. Configuracao em
[auto_update_setup.md](../install/auto_update_setup.md).

#### 1E.1 Onboard signing

- [~] Decisao 1 (custodia da chave).
- [ ] Gerar keypair com `python tool/appcast/generate_appcast_signing_key.py`.
- [ ] Configurar os secrets `APPCAST_SIGNING_PRIVATE_KEY` e
  `AUTO_UPDATE_FEED_PUBLIC_KEY` no repositorio.
- [ ] Publicar release e verificar: step `Validate generated installer` sem
  erro, step `Update appcast.xml` reporta `(signed)`, item com
  `plug:edSignature`.
- [ ] Em cliente em campo: diagnostico copiado mostra
  `feedSignatureStatus: valid`.

#### 1E.2 Ativar REQUIRE

- [ ] Aguardar 2 releases consecutivas com `feedSignatureStatus: valid` em
  campo (nenhum cliente com `missing`/`publicKeyUnavailable`/`invalid`).
- [ ] Criar a variable `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true` no repositorio.
- [ ] Atualizar `.env.example` para `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true`.
- [ ] Apos 2 releases com Authenticode valido em helper, runner elevado e
  installer, publicar com `require_valid_update_signature=true`.
- [ ] Monitorar 48h: `automaticValidationFailure` com
  `validation_code=feed_signature_*` ou `helper_signature_*` indica regressao.
  Rollback: voltar a variable/input para `false` e gerar novo build.

#### Criterio de aceite da Fase 1

- [ ] Release publica com `plug:edSignature` valido.
- [ ] Cliente em campo reporta `feedSignatureStatus: valid`.
- [ ] Rotacao testada via builds que aceitam 2 chaves.

### Fase 2B - Review do threat model

- [ ] Review por alguem de seguranca de
  [auto_update_threat_model.md](../security/auto_update_threat_model.md).

### Fase 4B - Testes dos histogramas

- [ ] Tests em `test/infrastructure/metrics/metrics_collector_test.dart`
  cobrindo as chaves de duracao de probe/download no snapshot.

### Fase 6 - Contratos

- [ ] 6B: gerar `SilentUpdateLauncherStatus`
  (`lib/domain/entities/pending_silent_update.dart`) com `json_serializable`.
- [~] 6C diferido: extrair `ManualUpdateOrchestrator` exige mover a logica
  WinSparkle (gateway, listeners, drain window, circuit breaker manual) do
  `AutoUpdateOrchestrator` e testes de integracao que so rodam no Windows. O
  6A ja desacoplou o contrato manual; `IAutoUpdateOrchestrator` deve continuar
  como fachada por composicao e a DI permanecer igual.
- [ ] Criterio: `flutter analyze` zero, cobertura igual ou superior,
  comportamento identico.

### Fase 7 - Push de diagnostics ao hub

Entregue no agente: schema
`docs/communication/schemas/auto_update_diagnostics.schema.json`, rascunho em
`docs/communication/socket_communication_backlog.md`,
`ThrottledAutoUpdateDiagnosticsGateway` (1 push/minuto) chamado apos cada
check e teste live `test/live/auto_update_diagnostics_push_e2e_test.dart`. O
transporte registrado no DI ainda e no-op.

- [ ] Decisao 3 aceita pelo time do hub; privacy review.
- [ ] Trocar o transporte no-op por um sender RPC real.
- [ ] Entrada em `docs/communication/openrpc.json` / `rpc.discover`.
- [ ] Implementacao hub-side no `plug_server`; E2E passa contra hub de
  homologacao.

### Fase 8 - Rollback automatico (diferido)

Requer modificar o helper C++ (`windows/update_helper/main.cpp`) com risco
alto de regressao nao coberta por testes Dart. Antes de comecar:

1. Pipeline Authenticode estavel (Decisao 2): o helper modificado precisa ser
   assinado e validado a cada release.
2. Orcamento de disco para backups em `ProgramData\PlugAgente\updates`.
3. Politica de retencao (quantidade e criterio).
4. Heartbeat: chave de settings ou arquivo separado; janela antes do
   auto-restore.

#### 8A. Backup pre-install

- [ ] `CreateRollbackBackup(version)` no helper antes de spawnar o Inno.
- [ ] Copiar `plug_agente.exe` + DLLs criticas e plugins para
  `updates/backup-<versao>/`; limpar backups antigos apos copia.
- [ ] Status JSON ganha `backupVersion`; atualizar
  `docs/communication/schemas/silent_update_launcher_status.schema.json`.

#### 8B. Heartbeat + auto-restore

- [ ] App grava heartbeat da versao apos boot bem-sucedido.
- [ ] Helper restaura o backup anterior quando nao ha heartbeat dentro da
  janela configurada.
- [ ] UI mostra "Versao restaurada automaticamente" no boot seguinte.
- [ ] Telemetria via Fase 7 (`rollback_restored=true`).

#### Criterio de aceite da Fase 8

- [ ] Teste manual: instalar versao quebrada -> proximo ciclo restaura.
- [ ] Doc cobre o mecanismo, como desligar e custo de disco.
- [ ] CI assina o helper modificado e roda `signtool verify`.

### Fase 9B - Chaos tests

- [ ] Server HTTP de teste que encerra a conexao em pontos aleatorios.
- [ ] Verificar a reconciliacao do pending em todos os estados.
- [ ] Criterio: nenhum teste novo flaky em 10 runs.

## Riscos aceitos

- **R1**: 1E.2 so apos 2 releases assinadas validadas em campo. Qualquer
  `feedSignatureStatus: invalid` em 1E.1 pausa o rollout.
- **R2**: Fase 8 muda o helper C++ e aumenta a responsabilidade de
  assinatura/teste; so executar com o pipeline Authenticode estavel.
- **R3**: Fase 7 muda contrato; habilitar o transporte real so quando o hub
  estiver pronto (acoplamento de release).

## Sucesso global

1. 100% das releases com `plug:edSignature` valido + Authenticode no installer
   e helper.
2. `automaticInstallFailure rate` < 1% por semana em frota > 100 clientes.
3. p95 do ciclo silent (probe -> installer start) < 60s.
4. Operador responde "X% da frota esta em versao N" em < 1 minuto.
5. Nenhuma release que quebra o app deixa cliente preso > 24h.

## Referencias cruzadas

- Fonte de verdade do auto-update:
  [docs/install/auto_update_setup.md](../install/auto_update_setup.md)
- Threat model:
  [docs/security/auto_update_threat_model.md](../security/auto_update_threat_model.md)
- Padrao deste plano:
  [plano_acoes_agendadas_execucoes.md](./plano_acoes_agendadas_execucoes.md)
