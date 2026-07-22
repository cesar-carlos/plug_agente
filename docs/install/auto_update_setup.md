# Auto-Update

Configuracao, publicacao e diagnostico do update automatico do Plug Agente no
Windows.

## Visao Geral

O app tem dois fluxos de update:

- verificacao manual via `auto_updater`/WinSparkle, mantendo interacao do
  usuario;
- instalacao automatica silenciosa, ligada por padrao, com verificacao,
  download e apply em background (quando auto-apply esta ligado), validacao e
  *staging* do instalador por helper nativo; com auto-apply desligado, o apply
  permanece explicito via banner ou shutdown natural.

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
| `AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS` | `300` | minimo 60. Timeout do `HttpClient` durante o download do instalador. |
| `AUTO_UPDATE_DOWNLOAD_RESUME` | `true` | quando `false` desliga `HTTP Range`; use apenas em proxies que nao honram `Range`. |
| `AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS` | `30` | 0 desliga o aviso pre-fechamento; max 120. Tempo de espera apos a notificacao "fechando para atualizar" antes do `exit`. |
| `AUTO_UPDATE_QUIET_HOURS_START` / `_END` | desligado | formato `HH:MM`; ambos obrigatorios para ativar. Janela onde **novos** downloads automaticos retornam `skippedByQuietHours`. Pending ja *staged* ainda pode auto-aplicar / permanecer Ready. Suporta janelas que cruzam meia-noite. |
| `AUTO_UPDATE_HELPER_WAIT_MINUTES` | `30` | min 5, max 120. Tempo maximo que o reconcile aguarda um helper **ja lancado** (status / `launchedAt`) antes de marcar falha e limpar. Download apenas staged nao usa este timeout para clear+fail. |
| `AUTO_UPDATE_AUTO_APPLY` | `true` | quando `false`/`0`, o fluxo silencioso faz apenas download e *staging*; o apply exige banner ou shutdown. Opt-out por deploy. |
| `AUTO_UPDATE_FEED_PUBLIC_KEY` | nao definido | CSV base64 de chaves Ed25519 (ver secao de assinatura). |
| `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE` | `false` | quando `true`, items sem `plug:edSignature` valido sao rejeitados. |

O default seguro em `resolveAutoUpdateRequireValidSignature` e `true` e essa
e a configuracao do `.env.example`. Quando ligado, o gate atua em dois pontos:

- Lado Dart (`HttpSilentUpdateInstaller`): bloqueia antes de spawnar o helper
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

1. Validar pending persistido: artefatos ausentes sao limpos; helper em
   execucao bloqueia novo ciclo; update ja staged pode seguir para auto-apply.
2. Ler o appcast e localizar o item mais recente.
3. Comparar a versao remota com `AppConstants.appVersion`.
4. Rejeitar o fluxo se `plug:sha256`, tamanho, nome do asset, URL do
   instalador ou assinatura Ed25519 (quando exigida) estiverem ausentes ou
   invalidos. O gate UAC **nao** bloqueia mais o download automatico.
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
**na instalacao** (elevacao do helper). Isso e esperado e nao bloqueia mais o
download automatico.

O helper recebe argumentos explicitos, incluindo versao, instalador,
diretorio atual de instalacao, log, status JSON, PID do app e estrategia de
permissao.

## Retry Sem Admin e Fallback Elevado

O instalador continua com `PrivilegesRequired=admin` por padrao para o fluxo
manual. Para o auto-update, o setup permite override por linha de comando via
`PrivilegesRequiredOverridesAllowed=commandline`.

O helper usa politica conservadora:

- se a pasta atual do app for gravavel, tenta primeiro:
  `/CURRENTUSER /DIR="<pasta atual>"`;
- se a tentativa retornar exit code diferente de `0`, tenta uma unica vez via
  `ShellExecuteEx(..., lpVerb="runas")` com `/ALLUSERS`;
- se a pasta atual nao for gravavel, pula a tentativa sem admin e inicia direto
  o fallback elevado.

Todos os updates automaticos passam:

```text
/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /LAUNCHAFTERUPDATE=1 /MERGETASKS="!desktopicon,!startup" /DIR="<pasta atual>"
```

Em instalacoes sob `Program Files`, UAC continua esperado. O objetivo desta
etapa e reduzir UAC para instalacoes em diretorios gravaveis pelo usuario, nao
criar um servico privilegiado permanente.

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
- falha/clear apos evidencia de launch + timeout do helper, ou status
  terminal de falha do helper — **reconcile e resolve** compartilham a mesma
  politica fail+cooldown (nunca Ready/retry apos launch concluido/expirado);
- `launchedAt` e persistido **antes** do spawn do helper (e flushed) para que
  um kill entre `Process.start` e a escrita antiga nao deixe Ready sem
  evidencia de launch;
- o contador de falhas automaticas entra em cooldown depois de 3 falhas por 6
  horas;
- durante cooldown, o fluxo automatico nao baixa nem inicia instalador;
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
    (probe PowerShell em Dart, cache por sessao): `valid` / `invalid` /
    `unsigned` / `unknown`. Quando `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true`
    e o status nao for `valid`, o silent flow falha com
    `validation_code=helper_signature_*` antes mesmo de baixar o instalador.
  - `feedSignatureStatus` — Ed25519 do item do appcast: `valid` /
    `invalid` / `missing` / `publicKeyUnavailable` / `malformed`. Quando
    `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true` e o status nao for `valid`,
    o silent flow falha com `validation_code=feed_signature_*`.

O botao **Tentar atualizacao automatica agora** dispara o mesmo
`checkSilently()` usado pelo boot/intervalo. Ele nao ignora SHA-256, rollout,
cooldown, pending update ou a preferencia do usuario.

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
  tool.test_appcast_signing \
  tool.test_validate_launcher_status \
  -v
```

`tool.test_appcast_signing` exige `cryptography>=42.0.0` instalado. Workflows
do CI falham explicitamente se essa suite reportar `skipped=N`, evitando
regressao silenciosa do gate de assinatura.

## Workflow de Publicacao

1. Publique a versao pelo workflow manual **Publish Windows Release** seguindo
   [release_guide.md](release_guide.md). O workflow tambem expoe
   `require_valid_update_signature` (vire para `true` somente apos Authenticode
   verde em helper e installer) e `skip_authenticode_check` (rebuild manual
   sem certificado; uso restrito).
2. O workflow cria a tag, gera o instalador e publica a GitHub Release.
3. O workflow **Update Appcast on Release** valida tag, versao e asset.
4. O workflow calcula SHA-256 do asset publicado.
5. O workflow atualiza `appcast.xml` em `main` e, quando
   `APPCAST_SIGNING_PRIVATE_KEY` esta configurado em GitHub Secrets, anexa o
   atributo `plug:edSignature` no item recem-publicado.
6. O workflow publica o feed em GitHub Pages.
7. O smoke check confirma que o feed publicado aponta para o asset esperado.

Detalhe operacional do passo 6: o workflow `update-appcast.yml` faz o deploy
do Pages apenas no caminho `workflow_dispatch`. Quando disparado pelo evento
`release:published`, o primeiro job commita o `appcast.xml` em `main` e
**redespacha** o proprio workflow via `dispatch-main-appcast-publish`; o
segundo run (workflow_dispatch) e o que publica no Pages e roda o smoke
check. Em pos-release, valide ambos os runs em Actions, nao apenas o
primeiro.

O workflow de appcast aceita `rollout_percentage`, default `100`, para permitir
rollout gradual em proximas releases.
Em execucao manual ele tambem aceita `channel` (`stable`, `beta` ou
`internal`). Releases publicadas automaticamente continuam entrando em
`stable`.

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
   - sem versao nova: a UI informa que nao ha atualizacao;
   - em cooldown: a UI registra `automaticCooldown`;
   - com falha: a UI mostra detalhes tecnicos copiaveis.

Validacao manual recomendada:

```bash
python tool/appcast/validate_release.py \
  --tag v1.2.7 \
  --feed-url https://cesar-carlos.github.io/plug_agente/appcast.xml
```

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
  `lib/core/constants/app_version.g.dart` divergem.
- Rode `python installer/update_version.py`, revise o diff e commite antes da
  tag.
- Rode `python tool/release/release_preflight.py --version <versao> --require-iscc`
  para checar sincronizacao, tag e ferramentas antes de publicar.

### Feed publicado nao reflete a release

- Aguarde a publicacao do Pages propagar.
- Confirme se o smoke check passou.
- Verifique se o item mais recente do `appcast.xml` aponta para a versao, SHA e
  asset esperados.
