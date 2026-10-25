# Auto-Update

## Modo oficial manifest e suporte — 2026-10-25

O build local e os workflows oficiais usam somente `manifest`, sem Authenticode.
`--manifest-only` permanece como alias compatível. Configure
`AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false`, `WINDOWS_CODE_SIGNING_REQUIRED=false`
e `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true`, com chave pública Ed25519 válida.
Configurações conflitantes falham antes do build. Não é necessário certificado,
PFX, SignPath ou secrets de certificado. Assinaturas Ed25519, hash, tamanho,
versão, canal e vínculo feed/manifesto continuam obrigatórios.

Uma política antiga sem `requireAuthenticode` continua exigindo Authenticode.
A simples leitura ou atualização silenciosa não altera essa confiança. O
instalador manual elevado oferece consentimento específico para migrar; o cliente
valida identidade, caminhos protegidos, hashes e chave, suspende o supervisor,
reconfere o journal e persiste a política atomicamente, preservando sua DACL,
canal e capabilities. A migração não habilita aplicação automática nem produção.

O suporte deve distinguir: espera por operações, fechamento iniciado, versão
antiga sem canal, bloqueio e recuperação necessária. O canal usa uma operação
única por processo; consultas não repetem efeitos. Um solicitante elevado pode
usar outra conta administradora. Um cliente não elevado precisa ser o cliente da
mesma instalação/conta; um instalador por usuário sem esse cliente exige fechamento
manual. Se a operação ficou incerta, preserve `manifest-migration.json`, journal,
pending, logs e snapshots. Não reabra SQLite/pool no processo parcialmente fechado.

A conclusão da preparação não substitui a confirmação de saída dos processos.
O aplicativo tem prazo total de 60 segundos para manutenção; timeout de um efeito
não confirma cancelamento. Após efeitos irreversíveis, encerrar o instalador não
restaura a admissão nem autoriza nova instalação. Hub diagnostics permanece no-op.

## Estados e suporte — revisao de 2026-10-25

- **Pronta:** instalador preparado e estado confirmado; a interface pode oferecer aplicacao.
- **Cancelada:** solicitacao do operador; nao e contabilizada como falha de instalacao.
- **Adiada:** restricao temporaria de horario, cooldown ou manutencao, conforme diagnostico.
- **Em andamento:** operacao ativa confirmada pelo servico/helper.
- **Exige recuperacao:** registro inconsistente, resultado desconhecido ou pendencia
  que exige reconciliacao; nao tratar como autorizacao para instalar novamente.

Se a gravacao falhar antes do envio, a operacao so volta a pronta apos restauracao
confirmada. Verifique o armazenamento quando a mensagem informar falha de
persistencia. Nao apague pending/journal nem altere flags para forcar nova tentativa
quando o resultado for desconhecido. A mensagem tecnica para suporte permanece
separada do texto seguro apresentado na tela.

Arquivo de configuracoes corrompido agora permanece no local e bloqueia gravacoes,
inclusive de preferencias e diagnosticos, para nao perder evidencia do updater.
Preserve uma copia para suporte e recupere o armazenamento fora do processo, com
backup validado e reconciliacao do journal/servico antes de liberar nova operacao.
Nao apague o arquivo para restaurar defaults. Reiniciar sozinho nao corrige a
corrupcao. Status legado sem timestamp e resposta perdida no cancelamento tambem
exigem confirmacao antes de descartar pendencias.

Desativar/reagendar verificacoes cancela tambem o atraso inicial. Os novos estados
nao habilitam aplicacao automatica em producao; permanecem os requisitos de
homologacao e autorizacao descritos neste guia.


> Revisão de 2026-10-06: `signing_provider=manifest` (padrão no publish) e
> `build_installer.py` (ou o alias `--manifest-only`) exigem Ed25519 do feed/manifesto e SHA-256,
> sem certificado Authenticode. Exigências de certificado neste guia se aplicam
> aos provedores opcionais `pfx`/`signpath`. As chaves do feed continuam obrigatórias.
> O novo adaptador Windows usa o serviço sem fallback com UAC, mas a aplicação
> automática permanece bloqueada até concluir e homologar a transição. Consulte
> o [estado atual](../implemente/plano_auto_update_evolution.md) antes de publicar.


Configuracao, publicacao e diagnostico do update automatico do Plug Agente no
Windows.

## Local supervisor compatibility — 2026-10-15

Recovery contract 2 fixes incomplete IPC replies and bounded partial reads.
Existing contract-1 supervisors require an explicit administrative host transition;
the installer still defaults to continuing manually when offering that choice.
Dart refuses the old contract before maintenance. App version stays 1.8.7; IPC
framing stays v1. The production automatic-apply gates remain disabled.

The qualified Windows 11 lifecycle, standard-user service tests, twenty signed
prepare/cancel cycles and temporary notification integration passed. Scope,
evidence and remaining release blockers belong to the
[current plan](../implemente/plano_auto_update_evolution.md#qualified-windows-lifecycle-and-ipc-delivery-2026-10-15).
This does not authorize production distribution or claim automatic rollback.

## Transição para serviço Windows — 2026-10-04

A implementação do serviço está em andamento. O instalador oferece **Atualizar
automaticamente** em instalação global interativa e registra autorização
administrativa separadamente das preferências do aplicativo. Em instalação
silenciosa nova, use `/AUTOUPDATE=1` explicitamente; sem esse argumento, o
serviço não é instalado. Upgrades silenciosos preservam o registro protegido.
Instalação por usuário continua manual. Inicie o setup normalmente e deixe o
próprio instalador solicitar UAC, preservando o usuário original.

Os componentes de controle ficam em `%ProgramFiles%\PlugAgenteUpdater`,
fora do bundle; somente SYSTEM/administradores podem modificá-los. Usuários
comuns têm leitura/execução do cliente. Política, journal e staging ficam em
`%ProgramData%\PlugAgenteUpdater`, sem permissão de acesso comum. Esses
arquivos não recebem a ACL compartilhada de `%ProgramData%\PlugAgente`.
Workers ficam em `%ProgramFiles%\PlugAgenteUpdater\workers\<versão+build>`.
O instalador recebe essa versão compilada de `pubspec.yaml`, separada do protocolo
do worker. A promoção do próximo worker depende de saúde confirmada; o supervisor
e o worker que executa a tentativa permanecem fora do bundle substituído.

**A aplicação automática pelo serviço permanece bloqueada** por
`kApplicationContractImplemented=false` no código e
`applicationContractValidated=false` na política. Enrollment não comprova recuperação.
Implementation progress and remaining installed-lifecycle acceptance are tracked
in the updater plan; isolated bootstrap and recovery evidence do not unlock release.
Windows bootstrap registers `PrivilegedSilentUpdateInstaller`. Service failure
never falls back to the legacy helper or a UAC prompt.
Não distribuir esta implementação como automação concluída; veja o status em
[plano_auto_update_evolution.md](../implemente/plano_auto_update_evolution.md).

Enclosures novos incluem `manifestUrl`, `manifestSha256` e `manifestSignature`.
O cliente verifica o binding assinado, limita a resposta a 128 KiB, rejeita
redirecionamento para HTTP e confere assinatura e identidade do manifesto antes
de baixar o instalador. Binding parcial ou inválido bloqueia esse caminho mesmo
se assinaturas opcionais do formato legado estiverem desabilitadas. A leitura do
feed legado continua disponível; ela não habilita aplicação privilegiada.

Para revogar a autorização administrativa do serviço, execute em terminal
administrativo:

```powershell
& "$env:ProgramFiles\PlugAgenteUpdater\plug_update_client.exe" --revoke
```

Isso impede novas aplicações. Não encerre um setup ativo. Preserve journal,
staging e snapshots em `recoveryRequired`; a recuperação automática completa
não está integrada. Não transforme resultado desconhecido em sucesso ou
repita uma instalação cuja conclusão ainda não foi confirmada.

## Visao Geral

The app exposes manual update checks and a background coordinator. On Windows,
preparation/application uses the privileged service adapter. It checks service
readiness before downloading/staging through that adapter and refuses an
unready service. Automatic application remains disabled by the native contract
and protected policy gates; enabling a UI preference does not override them.

The helper remains packaged for legacy compatibility and isolated tests.
Its behavior below must not be read as the current Windows application path.

O recurso fica ativo quando:

- o runtime suporta auto-update;
- a URL final do feed termina em `.xml`.

Resolucao da URL do feed:

1. `--dart-define=AUTO_UPDATE_FEED_URL=...`
2. `.env` em runtime
3. feed oficial embutido no app

Feed oficial:

```text
https://cesar-carlos.github.io/plug_agente/appcast.xml
```

Se um override invalido for informado em `AUTO_UPDATE_FEED_URL`, o auto-update
fica indisponivel e a UI orienta remover o override para voltar ao feed oficial.

## Configuracao Padrao

O `.env.example` versionado deve refletir os defaults de producao:

```text
AUTO_UPDATE_FEED_URL=https://cesar-carlos.github.io/plug_agente/appcast.xml
AUTO_UPDATE_CHECK_INTERVAL_SECONDS=3600
AUTO_UPDATE_CHANNEL=stable
AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true
# Opcionais (ver "Variaveis adicionais" abaixo)
# AUTO_UPDATE_FEED_PUBLIC_KEY=<base64-32-bytes>[,<base64-32-bytes-novo>]
# AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=false
# AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS=300
# AUTO_UPDATE_DOWNLOAD_RESUME=true
# AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS=30
# AUTO_UPDATE_QUIET_HOURS_START=22:00
# AUTO_UPDATE_QUIET_HOURS_END=06:00
# AUTO_UPDATE_HELPER_WAIT_MINUTES=30
# AUTO_UPDATE_AUTO_APPLY=true
```

### Variaveis adicionais

| Variavel | Default | Faixa / efeito |
| --- | --- | --- |
| `AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS` | `300` | minimo 60. Timeout de inatividade (stall) do download do instalador: aborta quando nenhum byte chega nesse intervalo, nao pelo tempo total. |
| `AUTO_UPDATE_DOWNLOAD_RESUME` | `true` | quando `false` desliga `HTTP Range`; use apenas em proxies que nao honram `Range`. |
| `AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS` | `30` | 0 desliga o aviso pre-fechamento; max 120. Tempo de espera apos a notificacao "fechando para atualizar" antes do `exit`. O helper espera o PID do app por no minimo **70 s** (`resolveAutoUpdateWaitPidTimeoutSeconds` = pre-close + 25 s de grace de exit + 15 s de buffer, teto 180 s), alinhado a essa janela. |
| `AUTO_UPDATE_QUIET_HOURS_START` / `_END` | desligado | formato `HH:MM`; ambos obrigatorios para ativar. Janela que bloqueia novos downloads automáticos e a aplicação de updates já baixados, inclusive no shutdown; o staging é preservado. `Instalar agora` (user-initiated) nao espera essa janela. Suporta janelas que cruzam meia-noite. |
| `AUTO_UPDATE_HELPER_WAIT_MINUTES` | `30` | min 5, max 120. Prazo de supervisão do helper. Expiração não comprova término: registros lançados e artefatos permanecem bloqueados até status terminal confirmado ou recuperação administrativa. |
| `AUTO_UPDATE_AUTO_APPLY` | `true` | quando `false`/`0`, o fluxo silencioso faz apenas download e *staging*; o apply exige banner ou shutdown. Opt-out por deploy. |
| `AUTO_UPDATE_FEED_PUBLIC_KEY` | nao definido | CSV base64 de chaves Ed25519 (ver secao de assinatura). |
| `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE` | `false` | quando `true`, items sem `plug:edSignature` valido sao rejeitados. |

O default seguro em `resolveAutoUpdateRequireValidSignature` e `true` e essa
era a configuracao histórica. O `.env.example` e os builds oficiais agora
fixam `false`. Quando explicitamente ligado em ferramentas históricas, o gate atua em dois pontos:

- Lado Dart (`DioSilentUpdateInstaller`): bloqueia antes de spawnar o helper
  se `plug_update_helper.exe` nao retornar Authenticode `valid` no
  `IHelperSignatureProbe` (`helperSignatureStatus`).
- Helper nativo (`windows/update_helper/main.cpp`): bloqueia antes de executar
  `setup.exe` quando a Authenticode do instalador nao for `valid`
  (`signatureStatus`).

A protecao em camadas inclui ainda o `plug:sha256` validado em Dart durante o
download e novamente no helper antes de elevar privilegios.

`signing_provider=manifest` compiles with Authenticode enforcement disabled,
while requiring Ed25519 feed/manifest signatures. The `pfx` and `signpath`
providers are historical tools, disabled in official workflows. See the
[release guide](release_guide.md) for provider inputs and secrets.
The legacy helper checks above describe that component, not a service fallback.

## Assinatura Ed25519 do Feed (opt-in)

The heading describes legacy runtime configurability. Current production release
workflows require signed feeds and manifests for every signing provider.

Alem do `plug:sha256` por asset, o feed pode trazer assinatura Ed25519 por
item via atributo `plug:edSignature`. O cliente verifica a assinatura sobre a
representacao canonica dos campos da enclosure (`asset_size`, `asset_url`,
`channel`, `os`, `rollout_percentage`, `sha256`, `version`) usando a chave
publica em `AUTO_UPDATE_FEED_PUBLIC_KEY`. Quando
`AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true`, items sem assinatura valida sao
rejeitados pelo fluxo silencioso.

Estado:

- `valid` — assinatura confere com a chave publica configurada.
- `invalid` — bytes nao batem (item adulterado ou chave rodada).
- `missing` — `plug:edSignature` ausente no item.
- `publicKeyUnavailable` — `AUTO_UPDATE_FEED_PUBLIC_KEY` nao configurado.
- `malformed` — `plug:edSignature` ou chave publica em formato invalido.

Geracao de keypair:

```bash
pip install cryptography>=42.0.0
python tool/appcast/generate_appcast_signing_key.py
```

A saida traz `APPCAST_SIGNING_PRIVATE_KEY` (guarde em GitHub Actions
Secrets) e `AUTO_UPDATE_FEED_PUBLIC_KEY` (distribua nos builds de release
via `--dart-define` ou `.env`).

Configuracao no GitHub Actions:

| Nome | Tipo | Consumido por |
| --- | --- | --- |
| `APPCAST_SIGNING_PRIVATE_KEY` | secret | `update-appcast.yml` (assina o item) |
| `AUTO_UPDATE_FEED_PUBLIC_KEY` | secret | `release.yml` / `release-preflight.yml` (`--dart-define` + `--feed-public-key` do preflight) e `feed-smoke.yml` |
| `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE` | variable | `release.yml` / `release-preflight.yml` (default `false`) |

Assinatura durante a publicacao:

```bash
python tool/appcast/appcast_manager.py update \
  --appcast appcast.xml \
  --version-short 1.7.0 \
  --full-version 1.7.0+1 \
  --asset-url https://github.com/.../PlugAgente-Setup-1.7.0.exe \
  --asset-size 21173534 \
  --asset-sha256 <sha> \
  --signing-private-key "$APPCAST_SIGNING_PRIVATE_KEY"
```

A flag `--signing-private-key` e opcional. Quando ausente, o item e
publicado sem `plug:edSignature` (compatibilidade com o pipeline atual). Ao
ativar `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true` no cliente, exiga assinatura
em todos os pipelines de release antes de promover a uma proxima versao
publica para evitar bloqueio do fluxo silencioso.

Rotacao de chaves: `AUTO_UPDATE_FEED_PUBLIC_KEY` aceita lista CSV de
chaves base64. Use isso para janela de rotacao sem outage:

```text
# Build N: a chave nova ainda nao e usada para assinar, mas ja viaja
AUTO_UPDATE_FEED_PUBLIC_KEY=<key_atual>,<key_nova>

# Build N+1: releases passam a ser assinadas com <key_nova>.
# Clientes ainda no build N ou N+1 aceitam ambas as chaves.

# Build N+2 (apos todas as releases publicas usarem <key_nova>):
AUTO_UPDATE_FEED_PUBLIC_KEY=<key_nova>
```

O verifier retorna `valid` se a assinatura confere com **qualquer** chave
da lista. Items assinados pela chave antiga continuam sendo aceitos
enquanto ela permanecer na lista. Quando todas as chaves listadas
falharem, o status fica `invalid`
(`automaticValidationFailure` com codigo `feed_signature_invalid`).

## Feed Oficial via GitHub Pages

O feed oficial e publicado por GitHub Pages usando Actions artifact, sem branch
`gh-pages`.

Configuracao unica no repositorio:

1. Acesse `Settings` > `Pages`.
2. Em `Build and deployment`, selecione `GitHub Actions`.
3. Salve a configuracao.

Depois disso, o workflow `.github/workflows/update-appcast.yml`:

1. atualiza `appcast.xml` em `main`;
2. publica somente `appcast.xml` no Pages artifact;
3. valida o feed publicado em
   `https://cesar-carlos.github.io/plug_agente/appcast.xml`.

GitHub Pages reduz o problema de cache do GitHub Raw. Os comandos de smoke
continuam usando tentativas com atraso porque a publicacao do Pages pode levar
alguns segundos para propagar.

## Fluxo Silencioso

The coordinator checks the feed at boot and at
`AUTO_UPDATE_CHECK_INTERVAL_SECONDS`, respecting channel, rollout, cooldown,
quiet hours and pending state. On Windows, the service adapter owns preparation
and application; see
[bootstrap registration](../../lib/bootstrap/bootstrap_dependency_registrar_auto_update.dart)
and [PrivilegedSilentUpdateInstaller](../../lib/application/services/privileged_silent_update_installer.dart).

### Fase automatica (boot / timer)

1. Inspect persisted pending state. An unconfirmed launched operation requires
   reconciliation; do not delete its evidence or start a replacement attempt.
2. Select an eligible feed item and validate its signed metadata.
3. Ask the service for capabilities. An unavailable/unready service fails before
   the adapter downloads or stages the installer (`service_not_ready` when the
   service responds but cannot apply).
4. Only when readiness permits, verify the manifest, download/verify the setup
   and ask the service to prepare the bound operation.
5. Persist the returned service operation identity for later application.

Production gates currently prevent successful automatic preparation/application.

### Fase de apply (automatica, explicita ou no shutdown)

The adapter rechecks service readiness, caller ownership, version and operation
identity. It then coordinates maintenance and an encrypted secrets snapshot
before asking the service to start. An uncertain dispatch is reconciled through
service state; it is never silently replayed through the legacy helper.

The original-session launcher, probation and recovery acceptance are tracked in
the [updater plan](../implemente/plano_auto_update_evolution.md). Fixture success
alone does not certify the installed lifecycle or enable automatic application.

## Modo de instalação e helper legado

This section documents the retained legacy component and its tests. Current
Windows bootstrap does not fall back to this helper when the service is unavailable.

O modo vem de `install-mode.ini`: `user` permite `/CURRENTUSER`; `global`
(ou ausência do registro antigo) usa `/ALLUSERS`. Gravabilidade da pasta é
somente diagnóstico; não muda o modo nem provoca uma segunda instalação global
após falha da instalação por usuário. Pasta personalizada é preservada.

O helper espera o processo terminar cooperativamente. Os argumentos são:

```text
/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCLOSEAPPLICATIONS /LAUNCHAFTERUPDATE=0 /MERGETASKS="!desktopicon,!startup" /DIR="<pasta registrada>" /LOG="<log>"
```

O helper, executado no usuário original, relança o aplicativo depois de setup
confirmado, cancelamento do UAC ou falha antes de iniciar o setup. `[Run]` não
relança nesse caminho. Não há fechamento forçado do agente. A supervisão tem
prazo de 30 minutos; ao exceder, registra `recoveryRequired` e mantém o lock
até a saída real do instalador. Status ausente, antigo ou desconhecido depois
do despacho não libera retry nem remove artefatos. O mutex do setup é
`Global\PlugAgenteSetup`, compartilhado entre sessões.

`/MERGETASKS="!desktopicon,!startup"` impede o update silencioso de
re-selecionar o atalho da area de trabalho e a task **Iniciar com o
Windows**. Auto-start de instalacao elevada (nao de update) usa
`runasoriginaluser` mais o marker
`{commonappdata}\PlugAgente\autostart-requested`; veja
[requirements.md](requirements.md).

O `installer/setup.iss` usa `SetupMutex=Global\PlugAgenteSetup` para impedir duas
instancias do Setup (manual + helper silencioso). `AppMutex` e omitido de
proposito: o helper espera o PID primeiro; um AppMutex abortaria
`/VERYSILENT` durante a janela de pre-close. O setup interativo usa
`CloseApplications=yes`, com filtro `plug_agente.exe`; o helper passa
`/NOCLOSEAPPLICATIONS` e nao inicia a instalacao se a espera pelo PID falhar.
A desinstalacao remove `{commonappdata}\PlugAgente\updates`.

Em instalacoes sob `Program Files`, UAC continua esperado no caminho legado.
O servico dedicado descrito no plano vigente ainda nao aplica atualizacoes.
Se o operador cancelar o UAC, o
pending permanece **Ready** (nao sucesso e nao fail+cooldown); o banner
oferece retry.

## Pending Update, Cooldown e Diagnosticos

Apos o download bem-sucedido, o orquestrador persiste pending update com versao,
paths do instalador/log/helper/status, estrategia e PID. O agente continua
operacional ate o apply.

No proximo boot (reconcile):

- sucesso e marcado quando `AppConstants.appVersion >= pendingVersion`;
- pending *staged* (Downloaded sem evidencia de launch: sem `launchedAt` e
  sem status do helper) permanece Ready — nao e limpo nem marcado como falha,
  **exceto** quando `startedAt` ultrapassa o TTL de staged
  (`AutoUpdateDefaults.stagedPendingTtl`, 7 dias): nesse caso o pending e
  limpo (ops bound para Ready indefinido);
- helper em execucao (status in-progress ou `launchedAt` recente dentro de
  `AUTO_UPDATE_HELPER_WAIT_MINUTES`) permanece pending in-progress;
  `hasPendingDownloadedUpdate` / banner Ready **excluem** in-flight (nao
  oferecem Install enquanto o helper ja esta rodando);
- status terminal confirmado de falha do helper aplica a politica
  fail+cooldown; timeout, status ausente ou `recoveryRequired` depois do
  despacho preservam o pending e os artefatos, sem liberar retry. O prazo
  expirado nao comprova que o setup terminou;
- cancelamento do UAC (`elevatedCancelled` / estado `elevatedCancelled`) e
  a excecao: o instalador staged permanece Ready para retry no banner, com
  mensagem localizada; nao conta como sucesso e nao incrementa o cooldown;
- `launchedAt` e persistido **antes** do spawn do helper (e flushed) para que
  um kill entre `Process.start` e a escrita antiga nao deixe Ready sem
  evidencia de launch;
- o contador de falhas automaticas entra em cooldown depois de 3 falhas por 6
  horas;
- durante cooldown, o fluxo **automatico** (boot/timer) nao baixa nem inicia
  instalador;
- o apply explicito do usuario (`Instalar agora` / `applyAvailableUpdate` com
  `userInitiated: true`) ignora quiet hours e o cooldown de falhas
  automaticas; SHA-256, rollout e a preferencia para *novos* downloads
  continuam valendo;
- se a preferencia automatica for desligada **depois** de um stage bem-sucedido,
  o pending Ready e **mantido** para apply manual (banner/shutdown); so o
  download em voo e cancelado.

A tela **Atualizacoes/Sobre** mostra diagnosticos copiaveis com:

- versao remota, URL, nome e tamanho do asset;
- release notes (texto e URL quando disponiveis);
- correlation id `checkId` (UUIDv7) para casar com logs;
- SHA esperado e SHA calculado;
- canal, rollout percentage, bucket e elegibilidade;
- pending update, cooldown, contador de falhas e janela silenciosa
  (`skippedByQuietHours` quando aplicavel);
- path do helper/status/log/instalador;
- estrategia usada, diretorio de instalacao e gravabilidade;
- PID aguardado, duracao de espera, exit codes e retry elevado;
- status das tres assinaturas:
  - `signatureStatus` — Authenticode do `setup.exe` (escrita pelo helper
    C++): `valid` / `invalid` / `unsigned` / `unknown`.
  - `helperSignatureStatus` — Authenticode do `plug_update_helper.exe`
    (probe PowerShell em Dart, revalidação em cada chamada, sem cache por caminho): `valid` / `invalid` /
    `unsigned` / `unknown`. Quando `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true`
    e o status nao for `valid`, o silent flow falha com
    `validation_code=helper_signature_*` antes mesmo de baixar o instalador.
  - `feedSignatureStatus` — Ed25519 do item do appcast: `valid` /
    `invalid` / `missing` / `publicKeyUnavailable` / `malformed`. Quando
    `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true` e o status nao for `valid`,
    o silent flow falha com `validation_code=feed_signature_*`.

O botao **Tentar atualizacao automatica agora** dispara o mesmo
`checkSilently()` unattended usado pelo boot/intervalo. Ele nao ignora
SHA-256, rollout, cooldown, quiet hours, pending update ou a preferencia
do usuario. O botao **Instalar agora** e user-initiated e ignora cooldown
e quiet hours, como descrito acima.

## Fonte de Verdade do Appcast

A logica de geracao, validacao, smoke check e assinatura do `appcast.xml`
fica distribuida entre:

| Modulo | Responsabilidade |
| --- | --- |
| `tool/appcast/appcast_manager.py` | Estrutura do feed, validacao, smoke check, comandos `update` / `validate-file` / `smoke-validate-url` / `inspect-url`. |
| `tool/appcast/appcast_signing.py` | Canonical payload Ed25519, sign/verify, `verify_with_any_key` (CSV). Fonte de verdade compartilhada com `lib/core/security/appcast_signature_verifier.dart` — bytes precisam continuar identicos. |
| `tool/appcast/generate_appcast_signing_key.py` | Gera keypair Ed25519 e imprime `APPCAST_SIGNING_PRIVATE_KEY` / `AUTO_UPDATE_FEED_PUBLIC_KEY`. |
| `tool/appcast/validate_release.py` | Cruza GitHub Release + appcast local/remoto (tag, asset, SHA, size, channel, rollout). |
| `tool/appcast/validate_launcher_status.py` | Valida JSON do helper nativo contra `docs/communication/schemas/silent_update_launcher_status.schema.json`. Usado pelo workflow Release Preflight. |
| `tool/release/release_preflight.py` | Sincronizacao de versao, tag disponivel, ferramentas no PATH, presenca do instalador, chave publica embutida (`--feed-public-key`) e Pages habilitado (`--check-pages`). |

Workflows que consomem esse tooling:

| Workflow | Funcao |
| --- | --- |
| `.github/workflows/release.yml` | Build + signtool gate + publica release. |
| `.github/workflows/release-preflight.yml` | Ensaio sem commit/tag/release; valida helper e schema do status JSON. |
| `.github/workflows/update-appcast.yml` | Atualiza `appcast.xml` (com `plug:edSignature` quando `APPCAST_SIGNING_PRIVATE_KEY` esta configurado), valida e publica o Pages artifact. |
| `.github/workflows/validate-appcast.yml` | Roda diariamente contra o feed publicado e tambem manualmente. |
| `.github/workflows/feed-smoke.yml` | Probe diario do feed publicado; checa shape, `plug:sha256` obrigatorio e `plug:edSignature` (quando a chave publica esta configurada como secret). |

Teste local rapido do tooling Python:

```bash
python -m unittest \
  tool.appcast.test_appcast_manager \
  tool.appcast.test_validate_release \
  tool.appcast.test_appcast_signing \
  tool.appcast.test_validate_launcher_status \
  -v
```

`tool.appcast.test_appcast_signing` exige `cryptography>=42.0.0` instalado.
Os workflows de appcast e o `release_preflight.py --appcast-tooling` falham
explicitamente se essa suite reportar `skipped=N`, evitando regressao
silenciosa do gate de assinatura.

## Workflow de Publicacao

The [release guide](release_guide.md) owns publication order, inputs, signing
providers and secrets. `Publish Windows Release` calls `update-appcast.yml` as a
reusable workflow; no secondary release event or PAT dispatch is required.
Publication, Pages deployment and smoke checks use the published commit.

The release gate must pass before production installer/appcast publication.
Use provider-appropriate preflight/dry-run checks for preparation; they do not
remove the independent Windows automatic-application gate.

`Validate Current Appcast` checks the deployed feed and retains diagnostics on
failure. Appcast tooling and validation commands are listed above.

## Teste Operacional

Use the private fixture procedures and acceptance boundaries in the
[updater plan](../implemente/plano_auto_update_evolution.md). Do not use a
production installation to demonstrate an automatic application that is still gated.

For the current Windows runtime, verify that an unavailable or unready service
returns an actionable failure, without launching the helper, prompting UAC or
claiming that installation succeeded. Unknown operations retain their evidence
and require reconciliation.

For feed inspection, use `tool/appcast/validate_release.py` as described in the
[release guide](release_guide.md). `inspect-url` and `smoke-validate-url` in
`tool/appcast/appcast_manager.py` add `cb=` by default; use `--no-cache-bust` only
to reproduce the original URL exactly.

## Falhas Comuns

### Feed override invalido

- Remova `AUTO_UPDATE_FEED_URL` para voltar ao feed oficial.
- Se precisar de um feed customizado, ele precisa terminar em `.xml`.

### GitHub Pages nao publicado

- Confirme `Settings` > `Pages` > `Build and deployment` > `GitHub Actions`.
- Confira se o job `deploy-pages` do workflow **Update Appcast on Release**
  terminou com sucesso.
- Confira se o smoke check validou
  `https://cesar-carlos.github.io/plug_agente/appcast.xml`.

### Workflow nao executou

- Release sem asset `PlugAgente-Setup-{versao}.exe`.
- Asset com nome diferente da versao curta da tag.

### Versao fora de sincronia

- `pubspec.yaml`, `installer/setup.iss` e
  `lib/core/constants/app_version.g.dart` divergem; veja **Versao e Tags** em
  [release_guide.md](release_guide.md).

### Feed publicado nao reflete a release

- Aguarde a publicacao do Pages propagar.
- Confirme se o smoke check passou.
- Verifique se o item mais recente do `appcast.xml` aponta para a versao, SHA e
  asset esperados.
