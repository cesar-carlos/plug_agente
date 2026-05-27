# Plano de Evolucao do Auto-Update

## Objetivo

Aplicar 9 fases de melhorias do auto-update levantadas em auditoria de 5
rodadas, organizadas por dependencia tecnica, risco e valor por dia de
trabalho. Cada fase tem critério de aceite e o repositorio permanece
funcional ao fim de cada uma — sem big-bang.

O backlog cobre 5 itens onde a feature existe mas nao esta ativa
(assinatura Ed25519, Authenticode helper, gates CI) e 4 onde ha melhoria
significativa de produto (download resilience, observabilidade, UX,
refactors de API).

Este documento e a fonte de verdade do plano. A cada PR mergeado, atualize
o status dos itens e a data. O resumo executivo via `Plan` mode do Cursor
(`c:/Users/cesar/.cursor/plans/auto-update_evolution_plan_*.plan.md`) e
sincronizado a partir deste arquivo.

## Status oficial

**2026-05-26**: Execucao em andamento. Itens marcados como `[x]` foram
mergeados; `[~]` indica em PR aberto; `[ ]` permanece pendente.

## Backlog (atalho)

Resumo executivo. Detalhes na secao de cada fase mais abaixo.

| Prioridade | ID | Entrega | Bloqueador externo | Gate / referencia |
| --- | --- | --- | --- | --- |
| P0 | 1A | CI instala `cryptography` + roda `tool/test_appcast_signing` sem skip | nao | `.github/workflows/*.yml` |
| P0 | 1B | `AUTO_UPDATE_FEED_PUBLIC_KEY` aceita CSV (multi-key rotacao) | nao | `lib/core/security/appcast_signature_verifier.dart` |
| P0 | 1C | `signtool verify /pa` gate no `release.yml` para installer e helper | Decisao Authenticode | `.github/workflows/release.yml` |
| P0 | 1D | `release_preflight.py` valida pubkey embutida no binario | nao | `tool/release_preflight.py` |
| P0 | 1E.1 | Configurar `APPCAST_SIGNING_PRIVATE_KEY` no GH Secrets + publicar release assinada | Decisao chave | operacional |
| P0 | 1E.2 | Ativar `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true` apos 2 releases verde | observacao em campo | `.env.example`, build CI |
| P0 | 2A | `IHelperSignatureProbe` + PowerShell Authenticode gate pre-launch | Decisao Authenticode | `lib/infrastructure/services/http_silent_update_installer.dart` |
| P0 | 2B | Threat model documentado | nao | `docs/security/auto_update_threat_model.md` |
| P1 | 3A | Pre-flight de espaco em disco | nao | `lib/infrastructure/services/http_silent_update_installer.dart` |
| P1 | 3B | Download resumivel HTTP Range com flag opt-out | nao | idem |
| P1 | 4A | Correlation ID UUIDv7 nas diagnostics | nao | `lib/core/services/update_check_diagnostics.dart` |
| P1 | 4B | Histogramas de duracao no `MetricsCollector` | nao | `lib/infrastructure/metrics/metrics_collector.dart` |
| P1 | 5A | Notificacao pre-close configuravel | nao | `lib/core/di/plug_dependency_registrar.dart` |
| P1 | 5B | Release notes na UI Settings | nao | `lib/presentation/pages/config/widgets/updates_about_config_section.dart` |
| P1 | 5C | Quiet hours configuraveis | nao | `lib/application/services/silent_update_coordinator.dart` |
| P2 | 6A | `Result<ManualCheckOutcome>` para `checkManual()` | nao | `lib/core/services/i_auto_update_orchestrator.dart` |
| P2 | 6B | Schema JSON do launcher status + `json_serializable` | nao | `docs/communication/schemas/silent_update_launcher_status.schema.json` |
| P2 | 6C | Extrair `ManualUpdateOrchestrator` | nao | `lib/application/services/manual_update_orchestrator.dart` |
| P2 | 7A | Spec RPC `agent.autoUpdate.diagnostics.push` | Decisao hub | `docs/communication/socket_communication_standard.md` |
| P2 | 7B | Gateway cliente push | dep 7A | novo gateway |
| P2 | 7C | E2E test gated `RUN_LIVE_HUB_TESTS` | dep 7B | `test/live/` |
| P3 | 8A | Backup pre-install no helper C++ | dep 1C | `windows/update_helper/main.cpp` |
| P3 | 8B | Heartbeat + auto-restore | dep 8A | helper C++ + Dart |
| Cont. | 9A | Migrar tests de jitter para `package:fake_async` | nao | tests |
| Cont. | 9B | Chaos tests no installer | nao | tests |
| Cont. | 9C | Workflow `feed-smoke.yml` agendado | nao | `.github/workflows/feed-smoke.yml` |

## Decisoes operacionais externas

Tres decisoes afetam fases especificas. Bloqueiam apenas as fases listadas;
o resto continua.

1. **Custodia da chave privada Ed25519** (afeta 1E.1, 1E.2):
   - Opcao A: GitHub Actions Secrets do repo `plug_agente` com rotacao
     anual.
   - Opcao B: vault corporativo (1Password, HashiCorp Vault).
   - **Status**: pendente decisao.

2. **Pipeline Authenticode** (afeta 1C, 2A, 8A):
   - Existe certificado EV/OV?
   - `signtool` configurado para installer e helper no CI?
   - **Status**: pendente verificacao.

3. **Evolucao do protocolo Plug** (afeta 7A, 7B, 7C):
   - Time do hub aceita novo metodo RPC `agent.autoUpdate.diagnostics.push`?
   - Schema + privacy review feita?
   - **Status**: pendente coordenacao.

## Detalhe por fase

### Fase 1 - Fechar o loop de assinatura do feed

Goal: tirar a feature Ed25519 do dormente e operar em producao sem
incidentes.

#### 1A. CI executa `tool/test_appcast_signing` sem skip

- [ ] Adicionar `pip install cryptography>=42.0.0` aos workflows
  `.github/workflows/release.yml`, `.github/workflows/update-appcast.yml`,
  `.github/workflows/release-preflight.yml`.
- [ ] Step novo: `python -m unittest tool.test_appcast_signing -v` (falha
  o workflow se algum skip).
- [ ] Documentar requisito de Python 3.10+ nos workflows.

#### 1B. Multi-key support (rotacao segura)

- [ ] `AUTO_UPDATE_FEED_PUBLIC_KEY` aceita CSV de chaves base64 em
  `lib/core/config/auto_update_feed_config.dart`.
- [ ] `Ed25519AppcastSignatureVerifier.verifyEnclosure` em
  `lib/core/security/appcast_signature_verifier.dart` itera as chaves e
  retorna `valid` se qualquer uma aceita.
- [ ] Tests no `test/core/security/appcast_signature_verifier_test.dart`
  cobrindo: 1 chave (compat), 2 chaves uma valida, 2 chaves nenhuma
  valida, CSV malformado.
- [ ] `tool/appcast_signing.py` ganha `verify_with_any_key`.

#### 1C. Authenticode gate no CI

- [ ] Step em `.github/workflows/release.yml` rodando
  `signtool verify /pa /v` no installer e no helper.
- [ ] Falha o workflow se nao for `Verified successfully`.
- [ ] Flag de override (`SKIP_AUTHENTICODE_CHECK=1`) para builds manuais.

#### 1D. Preflight valida pubkey embutida

- [ ] Estender `tool/release_preflight.py`: checar string base64 da pubkey
  configurada presente no binario.
- [ ] Falha o preflight se ausente.
- [ ] Documentar como rodar localmente.

#### 1E. Faseamento de producao

Itens 1E.1 e 1E.2 sao operacionais (configurar GitHub Secrets + observar
campo). O codigo ja esta pronto: `update-appcast.yml` passa
`APPCAST_SIGNING_PRIVATE_KEY` para o `tool/appcast_manager.py update`, e
`release.yml` + `release-preflight.yml` ja injetam `AUTO_UPDATE_FEED_PUBLIC_KEY`
no build via `--dart-define`.

##### 1E.1: Onboard signing (runbook)

- [~] Decisao 1 (custodia da chave): GitHub Secrets vs vault. Pendente.
- [ ] Gerar keypair: `python tool/generate_appcast_signing_key.py` (saida
  e o par base64).
- [ ] Configurar no repositorio `cesar-carlos/plug_agente` em
  `Settings -> Secrets and variables -> Actions`:
  - Secret `APPCAST_SIGNING_PRIVATE_KEY` = base64 da chave privada.
  - Secret `AUTO_UPDATE_FEED_PUBLIC_KEY` = base64 da chave publica (CSV
    suportado para rotacao).
- [ ] Disparar release pelo workflow `Publish Windows Release`. Verificar:
  - Step `Validate generated installer` reporta pubkey embutida sem erro.
  - Step `Update appcast.xml` reporta `(signed)` no output.
  - Item publicado em `appcast.xml` contem `plug:edSignature`.
- [ ] Em cliente em campo: abrir Configuracoes -> Atualizacoes,
  disparar `Tentar atualizacao automatica agora`, copiar diagnostico e
  verificar `feedSignatureStatus: valid`.
- [ ] `REQUIRE` permanece `false` ate 1E.2.

##### 1E.2: Ativar REQUIRE

- [ ] Aguardar 2 releases consecutivas reportando `feedSignatureStatus:
  valid` em campo (criterio: nenhum cliente reportou
  `missing`/`publicKeyUnavailable`/`invalid` na frota observada).
- [ ] No repositorio, criar variable de actions
  `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true` em `Settings -> Secrets and
  variables -> Actions -> Variables`. Ja consumido em `release.yml` e
  `release-preflight.yml` via `vars.AUTO_UPDATE_REQUIRE_FEED_SIGNATURE`.
- [ ] Atualizar `.env.example` para refletir o novo default (linha
  `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true`).
- [ ] Disparar release. Verificar que builds embutem o requisito ativo:
  `feedSignatureRequired: true` no diagnostico.
- [ ] Monitorar nas proximas 48h: qualquer cliente reportando
  `automaticValidationFailure` com `validation_code:
  feed_signature_<status>` indica regressao. Rollback: setar a variable
  para `false` e gerar novo build.

#### Criterio de aceite da Fase 1

- [ ] `python -m unittest tool.test_appcast_signing` sem skip no CI.
- [ ] Release publica com `plug:edSignature` valido.
- [ ] Cliente em campo reporta `feedSignatureStatus: valid`.
- [ ] Rotacao testada via builds que aceitam 2 chaves.

### Fase 2 - Seguranca da fronteira do helper

Goal: cadeia de confianca nao depende mais so de filesystem ACL.

#### 2A. Helper Authenticode antes de spawnar

- [ ] Nova interface `IHelperSignatureProbe` em `lib/core/security/`.
- [ ] Default impl roda `Process.run('powershell', ['-NoProfile',
  '-Command', "(Get-AuthenticodeSignature '<path>').Status"])` com
  timeout 5s.
- [ ] Cache do resultado por sessao.
- [ ] `HttpSilentUpdateInstaller` recusa launch se
  `requireValidSignature=true` e status != `Valid`.
- [ ] Tests cobrem 3 status (Valid -> ok, Invalid + REQUIRE=true ->
  ValidationFailure, timeout -> best-effort).

#### 2B. Threat model documentado

- [ ] Novo doc `docs/security/auto_update_threat_model.md`.
- [ ] Estrutura: atores, defesas em camadas, matriz what-if.
- [ ] Review por alguem de seguranca antes de publicar.

#### Criterio de aceite da Fase 2

- [ ] Tests de helper signature passam.
- [ ] Doc reviewada.

### Fase 3 - Resiliencia do download

Goal: download silent completa em redes ruins.

#### 3A. Pre-flight de disco

- [ ] FFI para `GetDiskFreeSpaceExW` via `package:win32` ja em deps
  transitivas.
- [ ] Falha curta com `ValidationFailure(code: 'insufficient_disk_space')`
  quando livre < `assetSize * 2`.
- [ ] Test cobre disco cheio.

#### 3B. Download resumivel (HTTP Range)

- [ ] `_download` aceita `.part` parcial: envia `Range: bytes=<offset>-`,
  valida `Content-Range` e `206 Partial Content`.
- [ ] Fallback para baixar do zero quando server retorna `200`.
- [ ] Flag `AUTO_UPDATE_DOWNLOAD_RESUME=true|false` (default `true`).
- [ ] Tests: resume com `.part` parcial de 2 bytes / 5; server sem Range;
  disco cheio durante resume.

#### Criterio de aceite da Fase 3

- [ ] Tests dos cenarios acima verdes.
- [ ] Doc explica o opt-out.

### Fase 4 - Observabilidade local

Goal: cada check correlacionavel e mensuravel.

#### 4A. Correlation ID

- [ ] `UpdateCheckDiagnostics.checkId` (UUIDv7 time-ordered).
- [ ] Coordinator e orchestrator geram no inicio de cada ciclo.
- [ ] Logs estruturados incluem o ID.
- [ ] Ring buffer das ultimas 20 IDs em settings para correlacao offline.

#### 4B. Histograma de duracoes

- [ ] `MetricsCollector._autoUpdateProbeTimes` e `_autoUpdateDownloadTimes`
  (`ListQueue<Duration>` capped a 1000).
- [ ] Reusar `_durationStatsSnapshot('auto_update_probe', ...)`.
- [ ] `getSnapshot()` expoe novas chaves p95, max recente.
- [ ] Tests em `metrics_collector_test.dart`.

#### Criterio de aceite da Fase 4

- [ ] Diagnostics copiavel mostra `Check ID: 01923abc-...`.
- [ ] Snapshot retorna chaves novas.

### Fase 5 - UX visivel ao usuario

Goal: usuario nao e surpreendido pelo fechamento do app.

#### 5A. Notificacao pre-close

- [ ] `_closeApplicationForSilentUpdate` aguarda
  `AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS` (default 30).
- [ ] Emite toast Fluent ou notificacao quando
  `INotificationService.isSupported`.
- [ ] Server (notif desligada): pular aviso.
- [ ] Min 0, max 120 via env.

#### 5B. Release notes na UI

- [ ] `AppcastProbeResult.releaseNotes` extraido de `<description>` ou
  `<sparkle:releaseNotesLink>`.
- [ ] UI mostra em expander.
- [ ] Sanitizacao markdown basica (so links + paragrafos).
- [ ] Widget test cobre o expander.

#### 5C. Quiet hours

- [ ] Novo `SilentUpdateOutcome.skippedByQuietHours`.
- [ ] Env `AUTO_UPDATE_QUIET_HOURS_START=22:00` e `_END=06:00`.
- [ ] Settings UI editavel.
- [ ] Coordinator pula `checkSilently()` durante janela, mantem pending.
- [ ] Sem incremento de cooldown.
- [ ] Tests cobrem dentro/fora da janela.

#### Criterio de aceite da Fase 5

- [ ] Widget test cobre release notes.
- [ ] Coordinator test cobre `skippedByQuietHours`.
- [ ] Doc explica interacao quiet hours x pending update.

### Fase 6 - Refactor de API

Goal: contratos tipados em todas as fronteiras.

#### 6A. `Result<ManualCheckOutcome>` para `checkManual`

- [ ] Enum `ManualCheckOutcome` em
  `lib/application/services/manual_check_outcome.dart`.
- [ ] `IAutoUpdateOrchestrator.checkManual()` retorna
  `Future<Result<ManualCheckOutcome>>`.
- [ ] Atualizar ~30 assertions de teste.
- [ ] UI mantem leitura por `completionSource`.

#### 6B. Schema do launcher status

- [ ] `lib/application/services/silent_update_launcher_status.dart` gerado
  por `json_serializable`.
- [ ] Schema em
  `docs/communication/schemas/silent_update_launcher_status.schema.json`.
- [ ] CI valida outputs do helper smoke test contra o schema.

#### 6C. Separar manual e silent em orchestrators

Status: **diferido**. A separacao requer movimentar ~500 linhas de logica
de WinSparkle (gateway + listeners + drain window + circuit breaker
manual) do `AutoUpdateOrchestrator` para uma classe nova
`ManualUpdateOrchestrator`. A fronteira certa entre os dois orchestrators
exige testes adicionais de integracao com WinSparkle (que so rodam no
Windows, fora do CI atual). Acompanhar como tarefa standalone.

- [~] Extrair `ManualUpdateOrchestrator`. **Diferido** por escopo.
- [ ] `IAutoUpdateOrchestrator` continua sendo fachada por composicao.
- [ ] DI permanece igual.

Substituto entregue: o refactor da Fase 6A (`Result<ManualCheckOutcome>`)
ja tornou o contrato manual independente do silent no nivel de API. Isso
abre caminho para a extracao classe quando houver banda.

#### Criterio de aceite da Fase 6

- [ ] `flutter analyze` zero.
- [ ] Cobertura igual ou superior.
- [ ] Comportamento identico.

### Fase 7 - Push de diagnostics ao hub

Goal: operador ve estado da frota inteira. Bloqueado por decisao 3.

#### 7A. Novo metodo RPC

- [ ] Spec em `docs/communication/socket_communication_standard.md`.
- [ ] Schema em
  `docs/communication/schemas/auto_update_diagnostics.schema.json`.
- [ ] Atualizar `docs/communication/openrpc.json`.

#### 7B. Cliente envia apos cada check

- [ ] Novo gateway que envia subset nao-sensivel.
- [ ] Throttle 1 push/minuto por cliente.
- [ ] Coordinator e orchestrator chamam apos terminal.

#### 7C. E2E test

- [ ] Novo test em `test/live/` gated por `RUN_LIVE_HUB_TESTS=true`.
- [ ] Hub-side: assume implementacao separada no `plug_server`.

#### Criterio de aceite da Fase 7

- [ ] Spec aceito pelo time do hub.
- [ ] E2E passa contra hub de homologacao.
- [ ] Privacy review confirma nada sensivel viaja.

### Fase 8 - Rollback automatico

Goal: nova versao quebrada nao deixa cliente preso.

Status: **diferido**. Requer modificacao do helper C++
(`windows/update_helper/main.cpp`, ~900 linhas) com risco alto de
regressao critica nao coberta por testes Dart automatizados. Decisoes
operacionais necessarias antes de comecar:

1. Confirmar que o pipeline Authenticode (Fase 1C) esta estavel - o
   helper modificado precisa ser assinado e validado a cada release.
2. Definir orcamento de disco (3 backups ~ 90 MB; precisa ficar abaixo
   da pasta `ProgramData\Plug\updates`).
3. Definir politica de retencao (manter 3? 5? Por versao ou por dia?).
4. Definir heartbeat: chave settings ou arquivo separado? Janela default
   antes do auto-restore?

Plano de execucao quando retomar:

#### 8A. Backup pre-install

- [ ] Adicionar funcao `CreateRollbackBackup(version)` em `main.cpp`
  antes de spawnar o installer Inno.
- [ ] Copiar `plug_agente.exe` + DLLs criticas (`flutter_windows.dll`,
  `odbc_engine.dll`, plugins) para `updates/backup-<versao>/`.
- [ ] `CleanupOldBackups(maxRetained=3)` apos copia bem-sucedida.
- [ ] Status JSON ganha campo `backupVersion`.
- [ ] Schema atualizado em
  `docs/communication/schemas/silent_update_launcher_status.schema.json`.

#### 8B. Heartbeat + auto-restore

- [ ] Settings store ganha key `auto_update.heartbeat_<versao>` gravada
  no boot bem-sucedido do app (apos splash screen).
- [ ] Helper C++ le settings na proxima execucao via API existente.
- [ ] Se versao anterior nao tem heartbeat apos `RESTORE_WINDOW_HOURS`
  (default 24h), copiar `updates/backup-<versao-anterior>/*` por cima
  do install.
- [ ] UI mostra "Versao restaurada automaticamente: <antiga>" no boot
  seguinte (banner persistente ate o usuario fechar).
- [ ] Telemetria via Fase 7 push (`rollback_restored=true`).

#### Criterio de aceite da Fase 8

- [ ] Teste manual: instalar versao quebrada -> proximo ciclo restaura.
- [ ] Doc cobre o mecanismo + como desligar
  (`AUTO_UPDATE_ROLLBACK_DISABLED=true`).
- [ ] Custo de disco documentado.
- [ ] Pipeline CI assina o helper modificado e roda `signtool verify`.

### Fase 9 - Robustez de testes (continua)

#### 9A. FakeAsync para timers

- [ ] Migrar tests de jitter em
  `test/application/services/silent_update_coordinator_test.dart` para
  `package:fake_async`.

#### 9B. Chaos tests

- [ ] Server HTTP de teste que termina conexao em pontos aleatorios.
- [ ] Verifica `_isPendingStale` em todos os estados.

#### 9C. Smoke contra appcast real

- [ ] Workflow agendado `.github/workflows/feed-smoke.yml` (cron diario).
- [ ] Probe contra
  `https://cesar-carlos.github.io/plug_agente/appcast.xml`, valida shape +
  assinatura.

#### Criterio de aceite da Fase 9

- [ ] Nenhum teste novo flaky em 10 runs.
- [ ] Workflow smoke passa.

## Riscos aceitos

- **R1**: Fase 1E.2 (ativar `REQUIRE`) so apos 2 releases assinadas
  validadas em campo. Se Fase 1E.1 der `feedSignatureStatus: invalid` em
  qualquer cliente, pausar e investigar.
- **R2**: Fase 8 muda helper C++ - cria responsabilidade maior de
  assinatura/teste. So executar apos pipeline Authenticode (Fase 2)
  estabilizado.
- **R3**: Fase 7 muda contrato - PR no `plug_agente` so quando hub
  estiver pronto para receber o metodo (acoplamento de release).

## Sucesso global

Ao fim do plano:

1. 100% das releases publicadas com `plug:edSignature` valido +
   Authenticode no installer e helper.
2. `automaticInstallFailure rate` < 1% por semana em frota > 100 clientes.
3. p95 do ciclo silent (probe -> installer start) < 60s.
4. Operador responde "X% da frota esta em versao N" em < 1 minuto.
5. Nenhuma release que quebra app deixa cliente preso > 24h.

## Referencias cruzadas

- Documento "fonte de verdade" do auto-update:
  [docs/install/auto_update_setup.md](../install/auto_update_setup.md)
- Padrao deste plano (estrutura, status oficial, riscos aceitos):
  [plano_acoes_agendadas_execucoes.md](./plano_acoes_agendadas_execucoes.md)
- Auditoria que gerou este plano: 5 rodadas em 2026-05-26, registradas
  no historico de chats do Cursor.
