# Auto-Update Threat Model

## Escopo

Este documento descreve o modelo de ameacas do pipeline de auto-update do
Plug Agente: probe do appcast, download do installer, validacao e
instalacao via helper nativo. Cobre:

- ator de rede passivo (sniffing TLS, downgrade, replay)
- ator de rede ativo (MITM com CA controlada, BGP hijack)
- ator local sem admin (engenharia social, ransomware)
- ator com acesso a infra de release (CI, GH Secrets, GitHub Pages)
- atacante interno (developer com acesso a repositorio)

Nao cobre: vulnerabilidades no Inno Setup, malware no usuario antes da
instalacao, ataques fisicos a maquina.

## Defesas em camadas

| ID | Defesa | Implementacao | Cobertura |
| --- | --- | --- | --- |
| D1 | TLS obrigatorio para feed | `isSparkleFeedUrl` rejeita HTTP nao-loopback | Sniffing rede passivo |
| D2 | TLS obrigatorio para asset | `isAutoUpdateInstallerUrl` mesmo padrao | idem |
| D3 | SHA-256 do asset publicado | `plug:sha256` no appcast (obrigatorio) | Substituicao do asset entre publicacao e download |
| D4 | Validacao tripla do SHA-256 | Stream de download (Dart) + rename (Dart) + helper antes de executar (C++) | Race condition entre download e launch |
| D5 | Tamanho exato do asset | `length` no appcast, validado em 2 pontos | Asset substituido por arquivo maior (e.g., wormable) |
| D6 | Nome do asset validado | Regex de extensao `.exe` + nome esperado | Substituicao por extensao alternativa |
| D7 | Authenticode no installer | `signtool verify /pa` no CI gate + helper C++ verifica antes de executar | Asset assinado por chave roubada (parcial — depende da chave nao vazar) |
| D8 | Authenticode no helper | `IHelperSignatureProbe` (PowerShell) gate antes de spawnar | Helper local substituido por atacante com perm de escrita no dir de instalacao |
| D9 | Ed25519 do feed | `plug:edSignature` + `Ed25519AppcastSignatureVerifier` | Substituicao do item no feed publicado (GitHub Pages comprometido) |
| D10 | Multi-chave Ed25519 | CSV em `AUTO_UPDATE_FEED_PUBLIC_KEY` para rotacao sem outage | Rotacao apos suspeita de comprometimento |
| D11 | Rollout gradual | `plug:rolloutPercentage` + bucket persistente | Limitar blast radius de release com regressao |
| D12 | Cooldown automatico | 3 falhas em sequencia => 6h de pausa | DoS via release maliciosa que causa falhas em loop |
| D13 | Circuit breaker manual | 3 timeouts => 15min de pausa | DoS via probe trigado por usuario |
| D14 | Mutex global do helper | `Global\PlugAgenteUpdateHelper` | Race com dois helpers concorrentes |
| D15 | icacls hardening | Restringe ACLs do `ProgramData\Plug\updates` | Tampering por outro processo local sem admin |
| D16 | Drain window de listener WinSparkle | 30s | Estado tardio do WinSparkle confundindo background |
| D17 | Cancellation token | Coordinator e installer respondem a cancel | Estado consistente quando user muda preferencia mid-flight |
| D18 | UAC gate (currentUserThenElevated) | Estratrgia documentada em `auto_update_setup.md` | Tentativa de privilege escalation por atacante local |
| D19 | Helper SHA-256 capturado | Diagnostic-only `helperSha256` | Detectar drift do helper entre installs (audit, nao bloqueio) |
| D20 | TLS pinning de GitHub Pages | Implicito (Windows root store) | Atacante que controla CA root no sistema (improvavel sem admin) |

## Atores e ameacas

### A1. Atacante de rede passivo (sniffing)

**Capacidade**: ve trafego mas nao injeta. Cafes publicos, ISPs sem TLS.

**O que pode**:
- Saber que cliente fez probe ao feed (URL, timestamp).
- Saber tamanho do asset baixado.

**O que nao pode** (defesa):
- Ler conteudo do appcast (D1 TLS).
- Modificar payload em transito (D1 + D2 TLS + integridade TCP).
- Substituir asset (D3 + D4 SHA).

**Residual**: metadados de uso (probe rates, tamanhos).

### A2. Atacante de rede ativo (MITM)

**Capacidade**: injeta no fio. Wifi spoofado, ISP malicioso, BGP hijack do
GitHub Pages.

**O que pode**:
- Servir resposta TLS valida se controlar CA confiavel pelo sistema
  (improvavel sem admin no cliente).
- Servir asset diferente do publicado (mesmo URL, conteudo diferente).

**Defesa**:
- D1 + D2 TLS rejeita certificados nao confiaveis pelo Windows root store.
- D3 + D4 SHA-256 publicado no appcast rejeita asset modificado.
- D9 Ed25519 do feed: quando `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true`,
  atacante MITM precisa tambem comprometer a chave privada para forjar
  um feed valido (ataque exige A4, nao apenas A2).

**Residual**: se cliente confia em CA controlada por atacante (corp proxy
mau, malware previo), TLS nao protege; D3/D4/D9 ainda protegem. Cliente
fica preso em `automaticDownloadFailure` ate atacante parar.

### A3. Atacante local sem admin

**Capacidade**: executa codigo na sessao do usuario. Ransomware, drive-by,
malware previo.

**O que pode**:
- Reescrever arquivos em `%USERPROFILE%`, `%APPDATA%`, `%TEMP%`.
- Substituir o helper em `<install_dir>/plug_update_helper.exe` se o
  install foi feito sob a conta do usuario (`HKCU` / sem admin).
- Reescrever `appcast.xml` baixado em cache local (se houver).
- Modificar settings do app (`SharedPreferences`).

**Defesa**:
- D15 icacls restringe ACLs do diretorio de updates global
  (`ProgramData\Plug\updates`).
- D8 + D19: Authenticode do helper + SHA-256 capturado. Quando
  `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true`, helper modificado e
  rejeitado pelo gate antes do spawn.
- D4 + D5 SHA + tamanho: instalador modificado nao passa pelo helper
  (re-hash final antes de executar).
- D11 Rollout pode limitar impacto se ataque for direcionado.

**Residual**: se o ataque modificou `installedHelperPath` no local error
e o `signtool` / probe falhar de forma sutil, helper malicioso pode
rodar. Mitigacoes:
- `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true` (default).
- Instalacao em diretorio nao-gravable pelo usuario (`Program Files`).

### A4. Atacante com acesso a infra de release

**Capacidade**: workflow do GitHub Actions, GH Secrets, branch `main`.

**O que pode**:
- Publicar release com codigo modificado (compromete pipeline de build).
- Modificar `appcast.xml` para apontar para asset malicioso.
- Modificar pubkey configurada em GH Secrets para uma sob seu controle.
- Vazar `APPCAST_SIGNING_PRIVATE_KEY`.

**Defesa**:
- D7 Authenticode no installer: cliente verifica assinatura antes de
  executar. Para forjar, atacante precisa tambem da chave do certificado
  EV/OV (HSM-protected, separada do GH Secrets).
- D9 Ed25519 do feed: chave privada armazenada como `APPCAST_SIGNING_PRIVATE_KEY`
  no GH Secrets. Comprometer apenas o feed sem o cert Authenticode nao
  permite RCE (cliente rejeita asset sem Authenticode quando
  `REQUIRE_VALID_SIGNATURE=true`).
- D10 Multi-chave: rotacao rapida quando comprometimento e suspeitado;
  builds antigos aceitam ambas as chaves durante a transicao.

**Residual**: atacante com **ambos** os tokens (Authenticode + Ed25519)
pode publicar release maliciosa que passa por todos os gates do cliente.
Mitigacoes operacionais:
- Cert EV em HSM hardware (nao acessivel por workflow GitHub).
- Chave Ed25519 em vault corporativo (nao GH Secrets) — decisao 1 do
  plano de evolucao.
- Rollout gradual (D11) limita blast radius mesmo no pior caso.
- Audit log de quem disparou o workflow `Publish Windows Release`.

### A5. Atacante interno (developer)

**Capacidade**: commit em `main`, disparar workflow.

**O que pode**:
- Submeter PR com codigo malicioso (passa por review).
- Bypassar PR criando branch protegido (depende da config de branch
  protection).

**Defesa**:
- Branch protection: `main` requer review (pelo menos 1 aprovador).
- `signtool` gate (D7) e Ed25519 (D9): se atacante interno publica direto
  pelo workflow, ainda precisa dos secrets.
- Audit do GitHub Actions: workflows nao podem rodar sem trigger humano
  (`workflow_dispatch`).

**Residual**: developer com PR aprovado pode introduzir backdoor sutil
que passa review. Mitigacao = code review serio + threat model como
input para checklist de PR sensiveis (este documento + secao 2.3 do
plano).

## Matriz what-if

Tabela cruzando atores e ativos comprometidos. Coluna = ativo perdido,
linha = ator. Resultado = severidade + defesa que ainda mitiga.

| Ator \ Ativo perdido | TLS root store | Cert Authenticode (Windows code signing) | Ed25519 (`APPCAST_SIGNING_PRIVATE_KEY`) | Ambos certs | Helper instalado local |
| --- | --- | --- | --- | --- | --- |
| A1 passivo | irrelevante | irrelevante | irrelevante | irrelevante | irrelevante |
| A2 MITM ativo | **alto**: precisa de A4 para asset valido | medio: D9 ainda mitiga quando REQUIRE=true | medio: D7 ainda mitiga | **critico**: RCE possivel | irrelevante |
| A3 local | n/a | n/a | n/a | **critico via local**: helper modificado executa instalador modificado | medio: D8/D15 mitigam quando REQUIRE=true |
| A4 release infra | n/a | medio: precisa de cert tambem | medio: precisa de cert tambem | **critico**: RCE em toda frota; rollback exige rotacao + manual override | n/a |
| A5 interno | n/a | medio (precisa de cert) | medio (precisa de cert) | **critico**: idem A4 | medio |

## Gaps conhecidos

1. **Sem TLS pinning explicito**: confianca no Windows root store. Ataque
   por CA root malicioso e mitigado por D3/D4/D9 mas em cliente sem
   `REQUIRE_FEED_SIGNATURE=true`, MITM com CA controlada serve um
   appcast valido com asset cujo SHA bate. Mitigacao planejada: completar
   Fase 1E.2 (REQUIRE=true em producao).

2. **Sem assinatura do diretorio de release**: nao validamos que a soma
   total de arquivos em `installer/dist/` corresponde a um manifesto
   assinado. Apenas o `.exe` final e validado. Atacante com A4 pode
   substituir DLLs antes do build sem detectar.

3. **Rollback de versao com regressao depende de operador**: nao ha
   restore automatico (planejado em Fase 8 do plano de evolucao).

4. **Helper Authenticode probe e best-effort**: PowerShell pode falhar
   por motivos operacionais (timeout, ausencia, politicas). Quando
   `unknown`, mode `REQUIRE` bloqueia (correto); mode `false` segue
   (intencional para nao quebrar instalacao em maquinas com PowerShell
   degradado).

5. **Sem auditoria centralizada de telemetria**: status de update e
   visivel apenas localmente. Operador nao sabe se 10% da frota esta
   em `feedSignatureStatus: invalid` sem coletar diagnostics manualmente.
   Planejado em Fase 7 do plano de evolucao.

## Checklist de revisao de PR sensiveis

Use ao revisar PR que toca os componentes abaixo:

- [ ] `lib/application/services/silent_update_coordinator.dart`: novo path
  altera state machine? testes do ciclo silent atualizados?
- [ ] `lib/infrastructure/services/http_silent_update_installer.dart`:
  novo argumento ao helper? configs de Inno Setup atualizadas?
- [ ] `windows/update_helper/main.cpp`: mudanca no comportamento de
  validacao do installer? schema do `status.json` atualizado?
- [ ] `lib/core/security/*.dart`: cripto/probe alterado? threat model
  atualizado?
- [ ] `tool/appcast_manager.py`, `tool/appcast_signing.py`: contrato com
  o cliente alterado? Round-trip cross-platform ainda passa?
- [ ] `.github/workflows/*.yml`: novo secret necessario? Documentado no
  runbook (`docs/install/auto_update_setup.md` ou
  `docs/implemente/plano_auto_update_evolution.md`)?

## Referencias cruzadas

- Implementacao geral: [docs/install/auto_update_setup.md](../install/auto_update_setup.md)
- Plano de evolucao: [docs/implemente/plano_auto_update_evolution.md](../implemente/plano_auto_update_evolution.md)
- Schema do helper status:
  `docs/communication/schemas/silent_update_launcher_status.schema.json`
  (planejado em Fase 6B)
