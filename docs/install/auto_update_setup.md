# Auto-Update

Configuracao, publicacao e diagnostico do update automatico do Plug Agente no
Windows.

## Visao Geral

O app tem dois fluxos de update:

- verificacao manual via `auto_updater`/WinSparkle, mantendo interacao do
  usuario;
- instalacao automatica silenciosa, ligada por padrao, com download,
  validacao e execucao do instalador por helper nativo.

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
```

O default seguro em `resolveAutoUpdateRequireValidSignature` e `true`. Quando
ligado, o helper nativo bloqueia a instalacao silenciosa se a assinatura
Authenticode do instalador nao for `valid`. A protecao em camadas inclui
ainda o `plug:sha256` validado em Dart durante o download e novamente no
helper antes de elevar privilegios.

Use `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false` apenas em ambientes onde
ainda nao ha pipeline de Authenticode configurado (por exemplo, builds locais
de desenvolvedor). Nesse modo a assinatura ainda e verificada e registrada em
`signatureStatus`, mas nao bloqueia a instalacao. Nunca distribua builds com
esse valor para usuarios finais.

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
python tool/generate_appcast_signing_key.py
```

A saida traz `APPCAST_SIGNING_PRIVATE_KEY` (guarde em GitHub Actions
Secrets) e `AUTO_UPDATE_FEED_PUBLIC_KEY` (distribua nos builds de release
via `--dart-define` ou `.env`).

Assinatura durante a publicacao:

```bash
python tool/appcast_manager.py update \
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

Rotacao de chaves: gere um novo keypair, assine os proximos items com a
chave nova e atualize `AUTO_UPDATE_FEED_PUBLIC_KEY` no proximo release. O
cliente passa a aceitar somente items assinados pela chave nova; items
antigos assinados com a chave anterior viram `invalid` na proxima validacao
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
rollout, cooldown e pending update.

Etapas:

1. Ler o appcast e localizar o item mais recente.
2. Comparar a versao remota com `AppConstants.appVersion`.
3. Rejeitar o fluxo se `plug:sha256`, tamanho, nome do asset ou URL do
   instalador estiverem ausentes ou invalidos.
4. Baixar o `.exe` para a pasta global de updates, primeiro como `.part`.
5. Validar tamanho e SHA-256.
6. Copiar `plug_update_helper.exe` do bundle instalado para a pasta global de
   updates.
7. Persistir pending update e iniciar o helper detached.
8. Fechar o app para permitir a instalacao.

O helper nativo recebe argumentos explicitos, incluindo versao, instalador,
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

Antes de fechar o app, o orquestrador persiste pending update com versao,
paths do instalador/log/helper/status, estrategia e PID.

No proximo boot:

- sucesso e marcado quando `AppConstants.appVersion >= pendingVersion`;
- caso contrario, o app le o status JSON do helper e registra falha/retry;
- o contador de falhas automaticas entra em cooldown depois de 3 falhas por 6
  horas;
- durante cooldown, o fluxo automatico nao baixa nem inicia instalador.

A tela **Atualizacoes/Sobre** mostra diagnosticos copiaveis com:

- versao remota, URL, nome e tamanho do asset;
- SHA esperado e SHA calculado;
- canal, rollout percentage, bucket e elegibilidade;
- pending update, cooldown e contador de falhas;
- path do helper/status/log/instalador;
- estrategia usada, diretorio de instalacao e gravabilidade;
- PID aguardado, duracao de espera, exit codes e retry elevado;
- status de assinatura (`valid`, `invalid`, `unsigned` ou `unknown`).

O botao **Tentar atualizacao automatica agora** dispara o mesmo
`checkSilently()` usado pelo boot/intervalo. Ele nao ignora SHA-256, rollout,
cooldown, pending update ou a preferencia do usuario.

## Fonte de Verdade do Appcast

A logica de geracao, validacao e smoke check do `appcast.xml` fica em:

```text
tool/appcast_manager.py
```

O workflow `.github/workflows/update-appcast.yml` chama esse script para:

1. atualizar o feed;
2. validar o arquivo local;
3. publicar o Pages artifact;
4. validar o feed publicado.

Teste local rapido do tooling:

```bash
python -m unittest tool.test_appcast_manager tool.test_validate_release -v
```

## Workflow de Publicacao

1. Publique a versao pelo workflow manual **Publish Windows Release** seguindo
   [release_guide.md](release_guide.md).
2. O workflow cria a tag, gera o instalador e publica a GitHub Release.
3. O workflow **Update Appcast on Release** valida tag, versao e asset.
4. O workflow calcula SHA-256 do asset publicado.
5. O workflow atualiza `appcast.xml` em `main`.
6. O workflow publica o feed em GitHub Pages.
7. O smoke check confirma que o feed publicado aponta para o asset esperado.

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
4. Clique em **Tentar atualizacao automatica agora** para exercitar o fluxo
   silencioso com as mesmas validacoes do boot.
5. Se quiser testar o fluxo manual, clique no botao de refresh da verificacao
   manual.
6. Confirme:
   - com versao nova: download, validacao e helper sao iniciados;
   - sem versao nova: a UI informa que nao ha atualizacao;
   - em cooldown: a UI registra `automaticCooldown`;
   - com falha: a UI mostra detalhes tecnicos copiaveis.

Validacao manual recomendada:

```bash
python tool/validate_release.py \
  --tag v1.2.7 \
  --feed-url https://cesar-carlos.github.io/plug_agente/appcast.xml
```

Os comandos `inspect-url` e `smoke-validate-url` de `tool/appcast_manager.py`
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
- Rode `python tool/release_preflight.py --version <versao> --require-iscc`
  para checar sincronizacao, tag e ferramentas antes de publicar.

### Feed publicado nao reflete a release

- Aguarde a publicacao do Pages propagar.
- Confirme se o smoke check passou.
- Verifique se o item mais recente do `appcast.xml` aponta para a versao, SHA e
  asset esperados.
