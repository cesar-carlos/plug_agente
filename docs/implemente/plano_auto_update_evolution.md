# Plano de Evolucao do Auto-Update

## Estado atual — 2026-10-15

A implementação das cinco etapas de correção está integrada. A homologação do
fluxo privilegiado continua pendente. Esta seção substitui as pendências de
implementação registradas nas revisões históricas de 04 e 06 de outubro.
`kApplicationContractImplemented=false` e `applicationContractValidated=false`
permanecem desabilitados; nenhuma destas evidências autoriza sua ativação.

| Etapa | Implementação e evidência local |
| --- | --- |
| 1. Contrato e compatibilidade | Pending `windowsService` independente do helper, com identidade, versão, datas e intenção de cancelamento; registros antigos exigem nova preparação. IPC aditivo com contrato de recuperação e comando restrito ao aplicativo registrado. Testes de parsing, compatibilidade, persistência e proprietário. |
| 2. Manutenção e falha de despacho | Admissão na aplicação para SQL, ações, configurações, sessões, credenciais e caches; bloqueio da interface; pausa dos purges, gatilhos, renovação de token e retry periódico. Efeitos de saída autorizados por operação, uma vez; segredos capturados depois dos efeitos e antes de fechar recursos. Falha de `start` consulta o serviço, sem segundo despacho; rejeição confirmada solicita reinício e resultado desconhecido consulta a cada 15 segundos por cinco minutos, preservando recuperação manual. Teste integrado com SQLite real, pending persistido, coordenador de manutenção e adaptador IPC. |
| 3. Finalização resistente a interrupções | Resultado da atualização separado da finalização; reconciliação de estados terminais, guarda vinculada à operação e identidade do relançamento gravada enquanto suspenso. Sessão indisponível preserva finalização pendente. Finalização comum a conclusão, rollback e reinício de recuperação; processo criado e perdido exige recuperação explícita. CTest interrompe sete checkpoints usando journal em disco e processos reais suspensos. |
| 4. Cancelamento, expiração e limpeza | Coordenador compartilhado persiste intenção antes do IPC, confirma cancelamento antes de remover pending, reconcilia preparações órfãs do mesmo proprietário e preserva operações ativas ou desconhecidas. Cancelamento idempotente; limpeza nativa apenas de preparação cancelada e inativa. Adiamento/cancelamento não contabilizam falha de instalação. Teste lê a intenção em disco durante o IPC e cobre resposta perdida, expiração e proprietário distinto. |
| 5. Reinstalação, reparo e supervisor | `PrepareToInstall` usa o cliente extraído do próprio instalador; política residual passa por validação de ACL/journal/identidade. Cliente ausente pode ser reparado; supervisor incompatível exige transição administrativa explícita `/UPGRADEUPDATERHOST=1`, revogação, confirmação de inatividade, parada, substituição, enrollment e reinício. Falha mantém autorização desligada e diagnóstico. Fixtures Pascal executam o mesmo helper de preparação usado pelo instalador. |

Reinício de recuperação não instala, migra ou restaura dados. O serviço valida
SID, sessão, PID e criação do processo, espera o original terminar e permite uma
tentativa por operação. Cooldown durável impede reaplicação imediata da mesma
versão. Após fechar recursos, o aplicativo não reabre SQLite/pool no processo
original; shutdown não repete efeitos de saída confirmados.

Ed25519, SHA-256, ACLs, identidade IPC e autorização administrativa foram
preservados. Authenticode continua dependente do provedor configurado. Instalação
manual e contratos RPC do hub permanecem compatíveis.

### Evidências de execução

- Suíte Flutter/Dart do CI (`--exclude-tags "live || slow || perf"`): 4.851 testes aprovados e 5 ignorados; `build/update-full-tests-final.log`. Os skips não homologam recursos externos.
- Regressões dos writers: 72 testes aprovados; `build/update-writer-regressions.log`.
- Regressões finais de ciclo de vida: 98 testes aprovados; `build/update-lifecycle-regressions-final.log`. Incluem o scheduler real após restauração da manutenção, binding do provider e ausência de repetição dos efeitos no shutdown.
- Python/Inno: 45 testes aprovados, incluindo fixtures Pascal compiladas e executadas; `build/update-python-final.log`.
- C++: build Release e 3/3 testes CTest aprovados, incluindo manifesto criptográfico e interrupções da finalização; `build/update-native-final.log`.
- Análise estática Flutter/Dart: sem diagnósticos; `build/update-analyze-final.log`.
- Sintaxe Inno Setup: `ISCC /DCOMPILE_SCRIPT_ONLY` aprovado; `build/update-inno-syntax-final.log`.
- Build Windows Release: compilação local com Ed25519 obrigatório e chave pública de fixture; `build/update-windows-build-final.log`. O payload não foi instalado, assinado para distribuição ou publicado.

Os testes de aplicação usam transportes controlados para IPC; os testes nativos
locais não executam enrollment nem instalação como serviço SYSTEM. O build de
validação usa a chave pública da fixture e não é um artefato de distribuição.

## Isolated lifecycle runner correction (2026-10-22)

The namespaced runner now compares only operational Windows registration
metadata. It no longer opens the installed configuration database, user vault,
updater policy or application binaries, and works on hosts with no operational
agent. `operationalStateInspection=registration_metadata_only` identifies scope;
`operationalRegistrationsPreserved` replaces the broader historical field.
Unavailable final verification records failure with a null preservation result;
changed registrations fail, and unchanged metadata never promotes a failed install.
SQLite/DPAPI retention checks remain restricted to fixture data.

The provisioner now requires a new direct `build/homologation/windows-lifecycle-*`
child before creation. The loader validates ownership and reparse points before
opening `fixture.json`; it checks a 256 KiB limit, format 1, disabled activation
and contained installer/historical-service artifacts before hashing. It refuses
existing/external output roots without building. These checks do not authenticate
arbitrary packages or replace private fixture provenance and elevated acceptance.

The original clean-VM validator and explicitly invoked existing-installation
repair tool keep their distinct contracts. Historical evidence below is not
revalidated by this correction. Current tests cover isolated runner behavior and
compiled Pascal installer repair/manual-upgrade orchestration; they do not rerun
elevated SCM installation or certify newer application builds, logon or rollback.
Automatic apply and production release remain blocked.

### Fresh bootstrap application builder (2026-10-23)

`py -3.13 -m tool.updater.build_isolated_application` accepts explicit
`--output`, full `--revision`, `--flutter` and `--native-cache`. Output must be a
new owned `build/homologation/windows-lifecycle-*` child. Sources are exported
from that exact local ancestor into a new short `build/a<identity suffix>` root;
neither the original checkout nor its DLL/output directory is built or replaced.
The pinned bootstrap entrypoint is reviewed independently of production main.

Git blobs are checked before compilation. Only exact PowerShell CRLF-to-LF
reconstruction and declared native identity derivations are accepted. Mutex,
window class, updater control path and title use the fixture identity. The native
entrypoint requires bootstrap context before any single-instance/control access;
Dart still enforces its private temporary root and loopback hub contract. Automatic
crash restart is disabled in this derived runner only. Production activation stays
false. Operational environment variables are excluded from build subprocesses.

The builder uses offline locked dependencies and validates the published native
cache and complete output. Its `application-build.json` verifier rechecks source
and payload inventories instead of trusting stored hashes. This is application
build scope, not proof of installed lifecycle, full installer provenance, or
production readiness. The lifecycle packager accepts this proof only through explicit
`--application-build <owned application-build.json>`. It verifies the proof before
creating output, adopts the same identity and private source/payload roots, and
rechecks the binding after packaging/historical compilation. It never falls back
to stock Release when an explicit proof is invalid. Existing bytes_only packages
remain distinguishable; their origin is not inferred or upgraded.

Local validation passed 102 updater tests and 14 workflow regressions without
skips. The actual build attempt passed export and offline dependency resolution,
then failed the existing CMake guard: compiler 14.43 versus the Visual Studio
redistributable 14.42.34438.0. No successful application receipt was produced.
System32 runtime 14.50 is not substituted for the redistributable bundle. The
required toolchain component must be corrected before repeating the full build;
this task did not install or update Visual Studio. An earlier compiler probe
confirmed SYSTEMDRIVE is required by MSBuild FileTracker; it is now retained in
the otherwise restricted toolchain environment. Paths with spaces and executable
shell arguments have regression coverage. No installer/service was launched.

### Private compatible C++ runtime (2026-10-23)

`py -3.13 -m tool.updater.isolated_runtime --output <new owned fixture> --msi
<explicit cached Microsoft MSI> --cab <explicit cabinet>` extracts only the eight
named AMD64 runtime DLLs with expand.exe. It never invokes MSI installation,
repairs Visual Studio, writes System32 or copies installed System32 binaries.
Inputs have size/reparse/hard-link checks and the MSI must have valid Microsoft
Authenticode. Each output must have a valid Microsoft signature, AMD64 PE header,
version at least 14.43 and stable hash; mixed versions are refused. The manifest
binds package/cabinet hashes and all DLL metadata. Its loader repeats validation.

The application builder accepts `--runtime-manifest <owned runtime.json>`.
A generated private CMake toolchain sets only MSVC_REDIST_DIR; its exact contents
and contained path are revalidated. The production CMake compatibility guard is
unchanged. The application proof binds the runtime reference and requires those
exact DLL hashes in the output. Inherited arbitrary toolchain settings remain
excluded from the filtered environment. Missing/changed input fails without
using an older runtime or modifying the host.

A local cached Microsoft package supplied version 14.50.35719.0 with valid
signatures; extraction/readback succeeded and the new CMake cache points at the
private redist. The fresh application build then completed (Flutter Release in
179.5 s), produced a reverified receipt, and the explicit source-bound lifecycle
package completed. Its read-only inspector reports applicationSourceVerified:true,
buildSourceVerified:false and installedState:not_checked. This resolves the local
build mismatch without changing host components; installed acceptance is pending.

Current private roots under build/homologation:
windows-lifecycle-runtime-d055394996ca, windows-lifecycle-app-d0742b655205 and
windows-lifecycle-sb-2b6a102aab41. The selected application commit is
c1f21e992eb82ef1843fea007d671a972f371b6b; identity is
PlugAgenteHomologacao_5f9733521924. Both application/package inventories contain
93 files. The native executable refused absent bootstrap context with exit 1 in
133 ms. No installer/service phase was executed. Final tooling regression:
114 tests plus 14 workflow tests passed without skips. Positive compiled bootstrap was subsequently verified against the persistent
fixture Hub below; installed update/recovery remains pending. These are private
test artifacts.

Microsoft compatibility/redistribution references:
[latest supported runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170)
and [redistributable files](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170).
Private fixture tooling does not authorize public distribution or production.

### Compiled positive bootstrap with persistent Hub (2026-10-23)

`tool.updater.bootstrap_fixture_input --proof <owned application-build.json>`
reuses the double proof verification before allocating a protected direct
system-temp child named sql-operation-bootstrap-*. Its output contains only
workspace/executable paths, revision, fixture identity and proof hash. Invalid
proofs cannot create a workspace. No operational profile or registration is read.

The MCP native-desktop operator controller exercised the compiled source-qualified
application with its private configured profile and a real Prisma/PostgreSQL Hub
fixture. Cold start and restart passed first-frame, SQLite quick_check, DPAPI
roundtrip, no plaintext config credentials, automatic session refresh, stable
config/instance identity and a new runtime session. Each phase completed real
REST-to-agent rpc.discover and cooperative clean shutdown. The REST normalized
single/item envelope is verified, including explicit success flags; HTTP 200
alone does not count as success. The first controller attempt used the raw RPC
shape and failed; that parser was corrected and the successful repetition used
fresh infrastructure. Three regression tests preserve the normalized contract.

Final checks: 116 updater tests, 14 workflow regressions, three MCP contract tests,
MCP lint/types and stable before/after source inventories. Private infrastructure
and DPAPI workspace were removed only after confirmed process closure; metadata
was retained. This is unpacked compiled bootstrap, not installed/SCM acceptance.
No business SQL or production credentials were used; installed update/recovery
and production gates remain pending.

### Explicit application proof in lifecycle packages (2026-10-23)

`applicationBuild` records the exact owned proof path/hash, commit, source tree
and original application payload tree. All application files must remain equal
to that proof; only the three named updater tools are rebuilt with the lifecycle
public key. The loader rechecks both original proof and packaged application at
every existing phase boundary. Missing/altered proofs, mismatched identities and
changed application files fail instead of falling back or qualifying old bytes.

Reports expose `applicationSourceVerified` separately. `buildSourceVerified`
remains false: this does not attest the entire installer, its historical
supervisor, all toolchain inputs, or installed recovery. `payloadQualification`
remains bytes_only for package integrity. The private runtime/build
round above subsequently exercised source-bound packaging successfully. This
still does not prove positive bootstrap, installed recovery or production.

All 107 updater tests and 14 workflow regressions passed locally without skips.
The previous 98-file bytes_only package was inspected again without modification
or installation; its hashes and false source-verification flags were preserved.

### Payload binding for newly provisioned fixtures

New lifecycle manifests use format 2 and bind every payload file plus a canonical
SHA-256 tree digest. Capture occurs before packaging; rechecks after packaging
and historical-supervisor compilation refuse drift. The loader checks the same
inventory, executable completeness and path ownership before a phase can run.
Reports include fixtureFormat, payloadTreeSha256 and payloadQualification.
Inputs are reverified at phase entry/exit; failed or inconclusive verification
invalidates the report and does not authorize retry or claim rollback.

Qualification is deliberately bytes_only: binding an existing Release bundle
does not attest which Dart sources built it, certify the corrected vault, or
prove an upgrade between different builds. Fresh source-qualified application
builds and installed elevated recovery still need their own evidence. Existing
format-1 manifests/reports are not rewritten; reprovision a new owned fixture.
Private fixture compilation/packaging is not installation or production release.

The current provisioner copies an existing Release bundle and rewrites installer
and updater identities. It does not rewrite the default Dart storage namespace
(PlugAgente). Do not treat that copy as an isolated desktop/profile build or use
it to qualify app startup/logon. A fresh source-qualified build with explicit
isolated storage/bootstrap remains required for that acceptance.


### Repeating the installed fixture safely

The historical supervisor source now requires `--legacy-revision` with an exact
40-character local ancestor commit containing disabled recovery contract 1.
It no longer follows HEAD, whose contract is already version 2. Missing,
unrelated or incompatible history fails before creating the fixture; the chosen
commit remains in `legacySourceCommit`. The documented commit below was checked
against local history; there is no automatic fetch, checkout or source migration.


Use a complete private candidate Release payload, including the corrected vault;
an old bundle is not proof of a newer app build. From the agent checkout, create
a new owned directory (never reuse an earlier fixture):

```powershell
python -m tool.updater.isolated_windows_fixture --output build/homologation/windows-lifecycle-new-id --legacy-revision fdb44d86b2a36df85c0133cf72167217fc1bd16e
```

First inspect the new fixture from a non-elevated terminal, without granting
machine changes:

```powershell
python -m tool.updater.validate_isolated_windows_lifecycle --fixture build/homologation/windows-lifecycle-new-id/fixture.json --phase inspect
```

Inspection verifies only owned fixture files. Its output uses
installationPerformed:false, installedState:not_checked and buildSourceVerified:false;
it does not inspect the operational installation or claim that no installation
exists. Do not pass --allow-machine-changes to inspection. A byte-valid package
still needs source-qualified build evidence before installed acceptance.

In an elevated Windows terminal run the administrator phase with that exact
`fixture.json`. It refuses existing namespaces, verifies its bound artifacts and
waits for the separate non-elevated phase. After `standard-phase-ready` exists,
run the second command from the original standard-user terminal:

```powershell
python -m tool.updater.validate_isolated_windows_lifecycle --fixture build/homologation/windows-lifecycle-new-id/fixture.json --phase administrator --allow-machine-changes
python -m tool.updater.validate_isolated_windows_lifecycle --fixture build/homologation/windows-lifecycle-new-id/fixture.json --phase standard-user --allow-machine-changes
```

These are two different terminals/tokens, not a sequential script. The explicit
flag authorizes only the owned fixture namespace; it does not authorize an
operational-installation repair. Preserve failed/uncertain state for inspection;
do not reuse the namespace or blindly rerun an installer. Keep fixture evidence
private and distinguish successful uninstall from complete application recovery.

### Bound two-token handoff (2026-10-23)

Before any installer call, the administrator runner refuses previous standard
phase markers, claims, results or partial result files, including dangling
junction entries. It generates a one-attempt handoff bound to the owned manifest,
fixture identity, installer and payload. The non-elevated phase requires that
handoff, claims it exclusively before IPC, and cannot start after the admin
phase has already terminated. Claims never expire into automatic retries.

The administrator accepts only a result matching its handoff, with literal
non-elevated status and the exact nine expected checks without omissions or
duplicates. A copied {status:passed} cannot approve a phase. Final JSON is flushed
and published by non-overwriting Windows rename; partial bytes are never exposed
as a terminal result. Evidence cannot be overwritten. This coordinates fixture
evidence only; native SCM/PID/SID checks, signatures and ACLs still authorize the
actual operations. A nonce is not an authentication substitute.

A regression reproduced the old problem (installer dispatch despite a stale
standard result) before correction. Final local checks passed 126 tooling tests
and 14 workflow tests without skips. A real-package negative probe, with IPC
blocked by the test, refused absent handoff without claim/result creation. No
installer or Windows service was started. The current process was checked and
has no Windows administrative token; elevated/standard real phases remain
pending an explicitly selected authorized environment and UAC/admin access.

## Qualified Windows lifecycle and IPC delivery (2026-10-15)

Windows 11 build 26300 passed a namespaced, real-machine lifecycle derived from
production installer and C++ sources. Product identity, AppId, SCM service/pipe,
registry and folders were rewritten into one exclusive fixture; activation gates,
ACLs, hashes, Ed25519 and PID/SID/SCM checks were preserved. The existing Release
payload remains 1.8.7+1. These packages are private acceptance artifacts, never
production installers or evidence of an upgrade to a newer app build.

The run exposed a real IPC defect: DisconnectNamedPipe discarded buffered replies
before the client consumed them; byte-pipe reads also incorrectly required a full
buffer in one read. Transfers now collect partial bytes under one deadline. Replies
wait for a bounded delivery receipt or legacy-client close before disconnecting,
avoiding unbounded FlushFileBuffers. Receipts do not authorize an operation, prove
installation success or permit redispatch. Five native pipe cases cover delayed
readers, legacy close, fragmented input, stalled readers and total timeout.

Native recovery contract 2 requires this delivery behavior. The installer rejects
contract-1 hosts and offers its existing manual/default or explicit host-upgrade
path; Dart refuses old hosts before maintenance. Protocol/framing remains IPC v1;
app version remains 1.8.7. kApplicationContractImplemented and
applicationContractValidated remain false. No automatic apply gate was enabled.

The final fixture passed clean install/enrollment, non-elevated IPC, optional repair
without updater mutations, missing-client repair, actual historical supervisor
replacement (source fdb44d86b2a36df85c0133cf72167217fc1bd16e, contract 1), explicit
migration to contract 2, same-version manual reinstall, uninstall, reinstall with
residual policy and final uninstall. SQLite retention data and encrypted fixture
vault persisted while download cache, protocol, Run and service were removed.
A separate non-elevated phase proved DPAPI, protected policy/control ACLs, registered
client binding, refusal of administrative commands, replay/channel/capability/bad
signature refusal, idempotent signed staging and cancellation. Twenty prepare/cancel
cycles passed; these are not twenty install/apply/rollback cycles.

Native desktop cold/restart also passed real NotificationService registration,
show/cancel APIs and temporary AppUserModelId/activator binding, alongside the hub
RPC harness. An optional WindowsInitializationSettings injection isolates identity;
production defaults are unchanged. This does not certify notification clicks,
visual banner delivery, logon or ShellExecute activation. Temporary notification
keys and application profiles were removed. Fixture machine directories were
removed only after completed uninstall; private evidence remains under build/.

Validation: 59 Python tests, four CTest targets, 76 Dart lifecycle/shell regressions,
36 final updater regressions including the contract-1 guard, native notification
cold/restart, full Flutter analysis plus final changed-file analysis, hub lint and
test type checking passed. The operational profile/vault, app EXEs, updater
binaries/policy and captured startup/protocol/authorization values were identical
before/after the lifecycle and cleanup. The original updater remains registered;
no operational installation was uninstalled or migrated in this fixture run.

Still pending: real service apply/probation/rollback with original-user data/schema
and crash recovery, twenty complete apply cycles/handle and snapshot retention,
distinct Windows user/admin, actual logon/protocol/notification activation, supported
Windows 10/Server targets, newer-build upgrades and distribution gates. The original
clean-VM validator remains unchanged. This partial evidence does not promote any
production installer/appcast or coordinated persona gate.

## Histórico — revisão de 2026-10-06: serviço sem certificado comercial

Decisão: atualizações comuns devem ocorrer sem intervenção após a primeira
instalação global autorizada. Authenticode deixa de ser requisito no provedor
`manifest`; Ed25519 do feed/manifesto, SHA-256, ACLs, identidade IPC, versão e
permissões registradas continuam obrigatórios. A recusa da SignPath não bloqueia
esse provedor. As exigências de certificado nas seções históricas abaixo se
aplicam somente a `pfx`/`signpath`.

Implementado nesta revisão, ainda sem homologação de instalação real:

- Build `--manifest-only` e publicação `signing_provider=manifest`, com chaves
  obrigatórias e política nativa consistente com o Dart.
- Enrollment administrativo registra hashes do app, supervisor, cliente, worker
  e baseline. Políticas antigas continuam exigindo Authenticode por padrão.
- Adaptador Windows prepara e inicia pelo serviço, sem fallback com UAC.
- Launcher nativo cria processo suspenso no usuário original, verifica token
  não elevado e registra identidade antes de executar.
- Bootstrap isolado `--update-validation` verifica assets, versão, SQLite e
  acesso aos segredos sem DI normal, hub ou gatilhos de startup. Restauração
  DPAPI e confirmação de saúde usam operação, nonce, PID e criação do processo.
- Guarda de boot durante a troca; recuperação supervisionada aguarda o mesmo
  usuário e o término comprovado do setup, preservando snapshot e política.
- Retenção dos dois snapshots de operações confirmadas mais recentes; tentativas
  ativas ou sem confirmação não são removidas.

**Estado histórico, substituído pela implementação de 2026-10-07:** a revisão
identificou pendências de admissão, gatilhos internos, recuperação após falha de
despacho e cancelamento/reconciliação. Essas pendências foram implementadas nas
cinco etapas acima; os controles de ativação continuam desabilitados por falta
de homologação, não por dependência do helper legado.

O usuário informou não possuir VM descartável. Esta sessão não é administrativa.
Não foram executados enrollment/upgrade/rollback reais, reboot durante instalação
ou matriz de Windows/Server. Não habilitar os gates nem anunciar ausência de UAC
homologada somente com testes unitários e compilação. Instalação manual continua
separada desse bloqueio. Nenhum commit, push ou release foi feito nesta revisão.

Validação local desta revisão: suíte de CI com 4.819 testes aprovados e 5 skips;
38 testes direcionados após ajustes finais (incluindo nova identidade de processo
na validação); ferramentas Python do updater, release e feed aprovadas; análise
Dart sem diagnósticos; actionlint dos três workflows e sintaxe Inno aprovados.
Build Windows Release sem Authenticode compilado com chaves públicas e exigência
Ed25519. Build nativo independente no modo manifest passou os dois testes CTest,
incluindo vetor criptográfico compartilhado com Dart/Python. O executável gerado
não foi instalado nem publicado; compilação não comprova execução privilegiada.



## Objetivo

Entregar atualizacao automatica por servico Windows, autorizada na primeira
instalacao, com encerramento seguro, recuperacao de binarios e dados locais e
revisao de requisitos a cada release. Preservar instalacao global, pasta
personalizada, atualizacao manual por usuario e contratos RPC existentes.

Este documento guarda o estado atual, as evidências e as decisões históricas. O
comportamento ja entregue esta descrito em
[auto_update_setup.md](../install/auto_update_setup.md) e a analise de
seguranca em [auto_update_threat_model.md](../security/auto_update_threat_model.md).

## Histórico — estado em 2026-10-04

**2026-10-04 — implementação do plano de serviço:** estado verificável:

| Etapa do novo plano | Estado verificável |
| --- | --- |
| Correções imediatas | Schema/gates, canal, deduplicação, reassinatura, asset exato, cache removido, relançamento legado e supervisão corrigidos; testes locais. |
| Contratos e confiança | Manifesto Python/Dart/C++ e fixture criptográfica comum; cliente valida binding, baixa manifesto por HTTPS com limite de 128 KiB e verifica hash/assinatura/identidade antes do download do setup. IPC/DACL/PID/SCM, consulta de capacidades e staging protegido implementados. Naquela data, o apply privilegiado ainda estava pendente. |
| Serviço e instalador | Binários compilados; autorização interativa/silenciosa e revogação implementadas; supervisor separado de workers por versão completa; SID e sessão ativa conferidos. Enrollment ainda não homologado em instalação real. |
| Manutenção segura | Filas SQL/ações congeláveis, coordenador reversível, checkpoint SQLite e testes. Naquela data faltavam admissão de configuração, inspeção integrada de recursos nativos e conexão ao apply. |
| Recuperação | Snapshot de segredos exato/DPAPI e checkpoint testados; worker experimental. Naquela data faltavam launcher não elevado, saúde autenticada, restauração no usuário original, retenção/reconciliação completas e migrações em rollback. |
| Homologação e entrega | Gates locais e build Windows disponíveis. VMs Windows 10/11/Server, 20 ciclos, certificado de teste/distribuição e rollout em campo ainda não executados. |

A aplicação pelo serviço é **bloqueada no código**, com
`kApplicationContractImplemented=false`, e na política com
`applicationContractValidated=false`. Enrollment não é homologação. Naquela revisão, o caminho
operacional do aplicativo ainda usava o helper legado. Não afirmar atualização sem
UAC, rollback automático completo ou aprovação da matriz antes dos itens acima.
Não há novos métodos RPC do hub nesta mudança.

Validação da integração do manifesto: 4.774 testes Dart aprovados e 5 ignorados
na suíte completa, 62 testes Python de tooling, 46 testes afetados do feed/
manifesto e 26 de contrato/instalador após o ajuste de `recoveryRequired`.
Também passaram 47 testes Python de scripts, os dois alvos CTest e o
`actionlint` dos quatro workflows alterados. Logs locais em `build/updater`.
`recoveryRequired` exige atenção, sem provar término do setup ou liberar ownership.
`dart analyze` sem diagnósticos; build Windows e empacotamento Inno com payload
compilados localmente. O setup gerado em `build/installer-payload` é **unsigned de
desenvolvimento**, não foi executado nem distribuído. Testes locais não comprovam
instalação real, ausência de UAC ou rollback entre schemas em máquinas cliente/Server.

O protocolo nativo não permite novo prepare sobre fases ativas, desconhecidas ou
de recuperação, mesmo se o worker já tiver terminado. Revogação mantém status,
cancelamento seguro e confirmação de saúde acessíveis; não autoriza novo start. Fontes e baseline são fixados
por handles durante validação/cópia; worker ativo nunca é substituído pelo setup.

Bloqueios externos observados: módulo Hyper-V presente, mas `Get-VM` negou
acesso ao processo atual; nenhum certificado de code signing encontrado nos
stores `CurrentUser/My` e `LocalMachine/My`, nem PFX configurado para build local.
Acesso a ambiente descartável administrativo continua necessário; certificado
é necessário apenas para os provedores Authenticode opcionais. As integrações que estavam
pendentes nessa data foram tratadas posteriormente; o estado atual é o registro
de 2026-10-07 no início deste documento.

## Trabalho restante — homologação e liberação

- Homologar enrollment, revogação, atualização, rollback, desinstalação seguida
  de reinstalação, reparo sem cliente e transição de supervisor antigo em Windows
  descartável, com usuário padrão e administrador distinto.
- Executar a matriz abaixo, incluindo falha de despacho/resposta perdida,
  recuperação sem reinstalação, manutenção sem gravações, cancelamento
  interrompido, pending perdido, logout, reboot e interrupções da finalização.
- Executar 20 ciclos medindo instâncias, handles e retenção de snapshots;
  verificar restauração de binários, SQLite/schema e segredos na conta original.
- Depois da homologação, preparar a transição administrativa e a liberação
  gradual de 5%, 25% e 100%, com evidências e procedimentos de recuperação.
  Ativar os dois controles somente mediante aprovação dessa homologação.
- Commit, publicação, distribuição e execução de instaladores reais não fazem
  parte desta execução. A ausência de ambiente descartável impede declarar o
  fluxo aprovado; não impede concluir as correções de implementação.

## Homologacao e criterios de conclusao

- Executar matriz em VMs descartaveis Windows 10/11 e Server suportado, com
  administrador e usuario padrao: instalacao nova/upgrade/silenciosa/manual,
  credenciais administrativas distintas, pasta personalizada e desinstalacao.
- Cobrir ACL/assinatura/publicador invalidos, reparse points, substituicao de
  arquivos, IPC remoto, replay, requisitos novos, cancelamento e revogacao.
- Cobrir SQL/acoes/transacoes ativos, recurso pendente e resultado incerto;
  logout/RDP/ausencia de sessao; setup travado; interrupcao em cada fase/reboot;
  falta de espaco; snapshot invalido; falha de boot e de rollback.
- Executar migracoes SQLite/WAL e restauracao exata de configuracoes/segredos,
  sem efeitos externos no modo de validacao, e 20 ciclos de update sem crescimento
  de processos, locks ou handles. Testes ignorados nao aprovam a matriz.
- Publicar primeiro a transicao assinada; promover em 5%, 25% e 100%, com pelo
  menos 48 horas de observacao por etapa. Integridade, permissoes, perda de dados,
  relancamento elevado ou rollback incorreto interrompem a promocao.
- Concluir a homologação somente com updates comuns sem UAC/confirmacao, novas permissoes
  bloqueadas ate aprovacao, rollback de schema testado e feed validado.
  Entregar evidencias e procedimentos de revogacao e recuperacao para o ultimo
  build homologado. Nao desabilitar validacao de assinatura como recuperacao.

## Referencias cruzadas

- Operacao: [auto_update_setup.md](../install/auto_update_setup.md).
- Instalacao: [installation_guide.md](../install/installation_guide.md).
- Publicacao: [release_guide.md](../install/release_guide.md).
- Seguranca: [auto_update_threat_model.md](../security/auto_update_threat_model.md).

### Isolamento complementar do helper na fixture

A derivação privada isola também `PlugAgenteUpdateHelper` e exige a transformação
nativa mesmo quando o arquivo sem alteração corresponde ao Git original. O
instalador privado fixa `CloseApplications=no`, sem mudar o instalador operacional.
Pacotes anteriores não comprovam essa revisão; gerar novo aplicativo e novo
namespace antes do teste instalado. O responsável autorizou UAC nesta máquina
para a fixture exclusiva; isso não autoriza deploy ou uso de perfis operacionais.

### Rodada instalada privada aprovada em 2026-10-23

Após corrigir o bootstrap derivado para executar a checagem real de assets com
`--installation-check`, a fixture `PlugAgenteHomologacao_4bb659210098` passou as
nove etapas administrativas e os nove grupos sem elevação, incluindo vinte
prepare/cancel, reparos, migração explícita do supervisor antigo, reinstalação
com retenção privada e desinstalação final. A primeira tentativa permaneceu
registrada como falha e foi desinstalada; não houve retry desse namespace.

Os 30 arquivos Python do operador permaneceram estáveis; inputs e registros
operacionais observados foram reconferidos. Resíduos dos dois namespaces foram
limpos por alvos exatos, sem links/serviços existentes. Evidências ficam em
`build/homologation/windows-lifecycle-sb-df087f694ab2`, protegidas e privadas.
Fonte do aplicativo: c1f21e992eb82ef1843fea007d671a972f371b6b, com derivações
explícitas do bootstrap e identidades. Instalador SHA-256:
`92cb42761d4ca63818187d3d03dd20d0e3aec711d82d81b40ca9a552bf193772`.

129 regressões de tooling passaram sem omissões. Essa prova não certifica o
aplicativo operacional nem todas as alterações atuais: o pacote inteiro conserva
buildSourceVerified:false. Apply/probation/rollback automático, perfil instalado
integrado à cadeia e aceite de produção continuam separados e bloqueados.
