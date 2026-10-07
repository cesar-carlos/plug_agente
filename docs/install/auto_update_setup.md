# Auto-Update

> Revisão de 2026-10-06: `signing_provider=manifest` (padrão no publish) e
> `build_installer.py --manifest-only` exigem Ed25519 do feed/manifesto e SHA-256,
> sem certificado Authenticode. Exigências de certificado neste guia se aplicam
> aos provedores opcionais `pfx`/`signpath`. As chaves do feed continuam obrigatórias.
> O novo adaptador Windows usa o serviço sem fallback com UAC, mas a aplicação
> automática permanece bloqueada até concluir e homologar a transição. Consulte
> o [estado atual](../implemente/plano_auto_update_evolution.md) antes de publicar.


Configuracao, publicacao e diagnostico do update automatico do Plug Agente no
Windows.

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
Ainda faltam conectar o launcher da sessão original, a manutenção ao runtime,
o bootstrap em validação, a restauração DPAPI/SQLite e a homologação nas VMs.
O caminho ativo do aplicativo continua sendo o helper legado e pode pedir UAC.
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

O app tem dois fluxos de update:

- verificacao manual via `auto_updater`/WinSparkle, mantendo interacao do
  usuario;
- fluxo silencioso legado, ligado por padrao, com verificacao e download em
  background e instalacao pelo helper nativo quando auto-apply esta ligado.
  Instalacoes globais ainda podem exigir UAC. Com auto-apply desligado, o apply
  permanece explicito via banner ou shutdown natural. A autorizacao do servico
  e separada dessa preferencia; sua aplicacao ainda esta bloqueada.

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
e a configuracao do `.env.example`. Quando ligado, o gate atua em dois pontos:

- Lado Dart (`DioSilentUpdateInstaller`): bloqueia antes de spawnar o helper
  se `plug_update_helper.exe` nao retornar Authenticode `valid` no
  `IHelperSignatureProbe` (`helperSignatureStatus`).
- Helper nativo (`windows/update_helper/main.cpp`): bloqueia antes de executar
  `setup.exe` quando a Authenticode do instalador nao for `valid`
  (`signatureStatus`).

A protecao em camadas inclui ainda o `plug:sha256` validado em Dart durante o
download e novamente no helper antes de elevar privilegios.

Estado atual do rollout (plano `docs/implemente/plano_auto_update_evolution.md`
fase 1E.2): o workflow `Publish Windows Release` ainda compila releases com
`AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false` por padrao. Para promover, vire o
input `require_valid_update_signature` para `true` ao acionar o workflow apos
duas releases consecutivas com Authenticode valido em helper, runner elevado e
installer. Builds locais de desenvolvedor sem certificado configurado devem
manter `false` no `.env`; o status da assinatura continua sendo verificado e
registrado em `signatureStatus`/`helperSignatureStatus`. Nunca distribua builds
para usuarios finais quando o gate estiver desligado e o pipeline Authenticode
nao estiver verde.

## Assinatura Ed25519 do Feed (opt-in)

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

O app executa o fluxo silencioso no boot e no intervalo configurado por
`AUTO_UPDATE_CHECK_INTERVAL_SECONDS`, respeitando `AUTO_UPDATE_CHANNEL`,
rollout, cooldown, quiet hours e pending update.

O ciclo divide-se em **verificacao + download** (automaticos) e **apply**
(automatico quando `AUTO_UPDATE_AUTO_APPLY` e a preferencia
`settings.automatic_silent_updates_auto_apply_enabled` estao ligadas; caso
contrario, explicito via banner ou no shutdown natural). Enquanto o instalador
esta apenas *staged* em disco, o agente permanece online e conectado ao hub.

### Fase automatica (boot / timer)

1. Validar pending persistido: stage sem evidencia de launch pode ser limpo
   pela politica de expiracao; launch sem conclusao confirmada preserva os
   artefatos e bloqueia novo ciclo. Update ja staged pode seguir para auto-apply.
2. Ler o appcast e selecionar a maior versao elegivel no canal configurado.
3. Comparar a versao remota com `AppConstants.appVersion`.
4. Rejeitar o fluxo se `plug:sha256`, tamanho, nome do asset, URL do
   instalador ou assinatura Ed25519 (quando exigida) estiverem ausentes ou
   invalidos. Nos enclosures com manifesto, verificar tambem o binding
   assinado, hash, assinatura e identidade antes do download do setup.
   O gate UAC nao bloqueia o download automatico.
5. Baixar o `.exe` para a pasta global de updates, primeiro como `.part`.
6. Validar tamanho e SHA-256.
7. Copiar `plug_update_helper.exe` do bundle instalado para a pasta global de
   updates (`deferHelperLaunch: true` — o helper **nao** e iniciado nesta
   fase quando auto-apply esta desligado).
8. Persistir pending update (`PendingSilentUpdateDownloaded`) e concluir com
   `SilentUpdateOutcome.installerReady`.
9. Quando auto-apply esta ligado, lancar o helper e fechar o app logo apos o
   staging (toast de pre-fechamento conforme
   `AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS`).

### Fase de apply (automatica, explicita ou no shutdown)

O helper nativo e lancado quando:

- auto-apply esta ligado e o download terminou com sucesso (caminho padrao
  para agentes 24/7); ou
- o operador confirma no banner in-app (`applyPendingSilentUpdate` ou
  `applyAvailableUpdate` para sessoes legadas com estado `awaitingUserConsent`);
  ou
- o app encerra naturalmente com update staged (`shutdownApp` chama
  `applyPendingSilentUpdate(triggerAppClose: false)` antes de parar o
  orchestrator).

No apply explicito pelo banner ou no auto-apply, o app exibe toast de
pre-fechamento (`AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS`) e fecha para o helper
instalar. No shutdown natural, o helper e lancado sem reentrar na logica de
close.

Em instalacoes sob `Program Files`, o Windows ainda pode exibir prompt UAC
**na instalacao** (elevacao do setup). Isso e esperado e nao bloqueia o
download automatico.

O helper recebe argumentos explicitos, incluindo versao, instalador,
diretorio atual de instalacao, log, status JSON, PID do app, estrategia de
permissao e `--wait-pid-timeout-seconds` (piso 70, mesmo default do helper
em `kDefaultWaitPidTimeoutSeconds`). A espera do PID precisa cobrir o
pre-close; um timeout menor (por exemplo 45 s) deixaria o Inno iniciar
enquanto o app ainda esta no aviso de fechamento.

## Modo de instalação e helper legado

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

1. Publique a versao pelo workflow manual **Publish Windows Release** seguindo
   [release_guide.md](release_guide.md) (inputs e secrets do workflow estao
   la).
2. O workflow cria a tag, gera o instalador e publica a GitHub Release.
3. O workflow **Update Appcast on Release** valida tag, versao e asset.
4. O workflow calcula SHA-256 do asset publicado.
5. O workflow atualiza `appcast.xml` em `main` e, quando
   `APPCAST_SIGNING_PRIVATE_KEY` esta configurado em GitHub Secrets, anexa o
   atributo `plug:edSignature` no item recem-publicado.
6. O workflow publica o feed em GitHub Pages.
7. O smoke check confirma que o feed publicado aponta para o asset esperado.

O publish chama `update-appcast.yml` como workflow reutilizável. Não depende
de PAT, de `release.published` ou de redespacho secundário. Mutação de `main`
usa uma fila compartilhada; publicação/deploy/smoke do feed também são
serializados. Deploy e smoke usam o SHA do commit que publicou o appcast.

Prerelease usa `beta`; publicação de prerelease em `stable` é bloqueada.
O item é deduplicado por versão, plataforma e canal, e é reassinado quando
publicado com chave, inclusive durante rotação. Releases novas incluem
`PlugAgente-Manifest-<versão>.json`: assinatura Ed25519 cobre commit/tag,
versão/canal, hash/tamanho do setup, requisitos e protocolos de dados.
`plug:manifestSignature` vincula URL/hash do manifesto ao item, preservando
`plug:edSignature` para clientes antigos. O serviço rejeita formato legado
como autorização de aplicação privilegiada.

Produção exige certificado Authenticode e chaves de feed válidas. O workflow
seleciona exatamente o asset esperado, valida bytes, assinatura, tag/commit e
canal antes de escrever o feed. A primeira publicação pelo workflow começa
em 5%; mudanças para 25% e 100% exigem as observações previstas no plano.

Para ensaio completo sem publicacao, execute o workflow manual
**Release Preflight**. Ele atualiza a versao apenas no workspace temporario do
runner, roda validacoes, gera o instalador, valida o helper nativo e publica
artefatos de diagnostico, mas nao cria commit, tag, GitHub Release nem deploy
Pages. Use `require_valid_update_signature=true` somente em staging assinado.

O workflow **Validate Current Appcast** roda diariamente contra o feed oficial
do GitHub Pages e continua disponivel manualmente para validar uma URL custom.
Quando falha, ele publica o appcast baixado e os arquivos de diagnostico como
artifact do GitHub Actions.

O job Windows de smoke do helper no CI publica `manifest.txt`, stdout/stderr e
status JSON quando falha, para diagnosticar o helper sem reproduzir localmente.

Nome esperado do asset:

```text
PlugAgente-Setup-{MAJOR.MINOR.PATCH}.exe
```

## Teste Operacional

1. Instale uma versao antiga.
2. Abra **Configuracoes** > **Atualizacoes**.
3. Confirme que **Instalar atualizacoes automaticamente** esta ligado.
4. Opcional: confirme o toggle de **aplicar automaticamente** (ligado por
   padrao; desligue para testar o fluxo legado com banner).
5. Clique em **Tentar atualizacao automatica agora** para exercitar o fluxo
   silencioso com as mesmas validacoes do boot.
6. Se quiser testar o fluxo manual, clique no botao de refresh da verificacao
   manual.
7. Confirme:
   - com versao nova e auto-apply ligado: download, staging e apply ocorrem
     sem clicar no banner (o app fecha para o helper instalar);
   - com auto-apply desligado: download e staging concluem; o banner oferece
     apply manual;
   - em `Program Files`, UAC pode aparecer **na instalacao**, nao no download;
   - se o UAC for cancelado: o pending permanece Ready para retry; a UI nao
     trata o apply como sucesso;
   - **Instalar agora** funciona mesmo em cooldown ou quiet hours;
   - sem versao nova: a UI informa que nao ha atualizacao;
   - em cooldown (fluxo automatico / **Tentar atualizacao automatica agora**):
     a UI registra `automaticCooldown`;
   - com falha: a UI mostra detalhes tecnicos copiaveis.

Para cruzar a GitHub Release com o feed publicado, use
`tool/appcast/validate_release.py` conforme [release_guide.md](release_guide.md).

Os comandos `inspect-url` e `smoke-validate-url` de `tool/appcast/appcast_manager.py`
adicionam `cb=` por padrao. Use `--no-cache-bust` apenas quando precisar
reproduzir exatamente a URL original.

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
