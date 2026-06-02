# Guia de Release e Versionamento

Fonte operacional para versionamento, build do instalador, tag e publicacao do
Plug Agente.

## Versao e Tags

- A versao nasce em `pubspec.yaml`, no formato `MAJOR.MINOR.PATCH+BUILD`.
- `installer/update_version.py` sincroniza `installer/setup.iss` com a versao
  curta (`MAJOR.MINOR.PATCH`) e `lib/core/constants/app_version.g.dart` com a
  versao completa.
- Tags usam `v{MAJOR.MINOR.PATCH}`. Exemplo: `version: 1.2.6+1` exige tag
  `v1.2.6`.
- O CI falha se `pubspec.yaml`, `installer/setup.iss` e
  `lib/core/constants/app_version.g.dart` estiverem fora de sincronia.

## Pre-validacao local (antes do CI)

Rode o gate local com paridade ao publish workflow **antes** de disparar o CI:

```powershell
.\tool\pre_publish_release.ps1 -Version 1.8.4
```

Equivalente manual:

```bash
python tool/release_preflight.py --version 1.8.4 --gate --check-secrets --print-publish-hints
```

O gate executa `flutter analyze`, `flutter test --exclude-tags "live || slow || perf"`,
`test/architecture/layer_boundaries_test.dart` e os testes Python de appcast.
Tambem imprime avisos sobre secrets (`RELEASE_PUBLISH_TOKEN`, assinatura, feed key)
e os comandos `gh workflow run` sugeridos.

Hook git opcional (pre-push em `main` quando `pubspec.yaml`, `lib/` ou `test/` mudam):

```powershell
.\tool\install_git_hooks.ps1
# pular uma vez: $env:SKIP_RELEASE_GATE = '1'
```

## Processo Recomendado

O caminho preferencial e o workflow manual **Publish Windows Release** em
GitHub Actions. Ele atualiza a versao, valida sincronizacao, gera o instalador
Windows, cria commit/tag/release e anexa o asset correto.

Ordem sugerida:

1. `.\tool\pre_publish_release.ps1 -Version X.Y.Z` (local).
2. (Opcional) `Actions` > **Release Preflight** com a mesma versao (build no CI
   sem publicar).
3. (Opcional) **Publish Windows Release** com `dry_run=true`.
4. **Publish Windows Release** em producao (`dry_run=false`):
   - Acesse `Actions` > `Publish Windows Release`.
   - Execute `Run workflow` em `main`.
   - Informe:
   - `version`: versao curta, exemplo `1.6.6`;
   - `build_number`: sufixo do `pubspec.yaml`, exemplo `1`;
   - `run_tests`: mantenha ativo para release estavel;
   - `require_signing`: ative apenas quando os secrets de assinatura estiverem
     configurados;
   - `prerelease`: use apenas para versoes de validacao;
   - `dry_run`: gera e valida o instalador sem criar commit, tag ou release.
5. Apos a publicacao, confirme que o workflow **Update Appcast on Release**
   terminou com sucesso (disparo automatico com `RELEASE_PUBLISH_TOKEN`, ou
   fallback disparado pelo proprio publish workflow).

Use `dry_run=true` para validar uma versao antes de publica-la. O workflow
continua atualizando a versao no workspace temporario do runner, rodando
preflight e gerando o instalador, mas encerra antes dos passos destrutivos.

Secrets opcionais para assinatura:

- `WINDOWS_CODE_SIGNING_CERT_BASE64`: certificado PFX em Base64.
- `WINDOWS_CODE_SIGNING_CERT_PASSWORD`: senha do PFX.

Quando `require_signing=true`, a release falha se o certificado nao estiver
disponivel. Quando `false`, a assinatura e aplicada apenas se os secrets
existirem. Sem certificado, o workflow **pula automaticamente** a verificacao
Authenticode (nao e mais necessario marcar `skip_authenticode_check=true`).

Secrets recomendados:

- `RELEASE_PUBLISH_TOKEN`: PAT classico com escopo `repo` para o appcast disparar
  sozinho apos a release. Sem ele, o workflow **Publish Windows Release** dispara
  **Update Appcast on Release** como fallback.

## Processo Local Manual

### 1. Atualizar versao

Edite `pubspec.yaml`:

```yaml
version: 1.2.7+2
```

### 2. Gerar build Windows e instalador

```bash
python tool/release_preflight.py --version 1.2.7 --allow-dirty --require-iscc --check-pages
python installer/build_installer.py
python tool/release_preflight.py --version 1.2.7 --allow-dirty --check-installer \
  --feed-public-key "$AUTO_UPDATE_FEED_PUBLIC_KEY"
```

O `installer/build_installer.py` executa:

1. `installer/update_version.py`
2. `flutter build windows --release`
3. `tool/build_elevated_runner.ps1` (compila e copia
   `plug_agente_elevated_runner.exe` para o bundle Release/Debug; obrigatorio)
4. Validacao de presenca de `plug_agente.exe`, `plug_update_helper.exe` e
   `plug_agente_elevated_runner.exe` no bundle Release
5. Assinatura opcional, na ordem: `plug_agente.exe`,
   `plug_update_helper.exe`, `plug_agente_elevated_runner.exe`, instalador
6. `ISCC installer/setup.iss`

A segunda chamada do preflight (`--check-installer --feed-public-key`)
confirma que a chave publica Ed25519 esta embutida no `.exe` gerado; sem isso,
clientes com `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true` reportariam
`feedSignatureStatus=publicKeyUnavailable` em todo silent check.

Quando `.env` define `AUTO_UPDATE_FEED_URL`, `AUTO_UPDATE_CHANNEL`,
`AUTO_UPDATE_REQUIRE_VALID_SIGNATURE`, `AUTO_UPDATE_FEED_PUBLIC_KEY` ou
`AUTO_UPDATE_REQUIRE_FEED_SIGNATURE`, o build injeta esses valores via
`--dart-define`. Sem override de feed, o app usa o feed oficial padrao
embutido.

Saida esperada:

```text
installer/dist/PlugAgente-Setup-{MAJOR.MINOR.PATCH}.exe
```

### 3. Revisar e commitar artefatos versionados

```bash
git add pubspec.yaml installer/setup.iss lib/core/constants/app_version.g.dart
git commit -m "chore: bump version to 1.2.7"
git push origin main
```

Mantenha alteracoes de runtime/runner Windows em commit separado do bump de
versao. O commit de release deve conter apenas os artefatos versionados acima.

### 4. Criar tag

```bash
git tag v1.2.7
git push origin v1.2.7
```

### 5. Publicar release no GitHub

1. Acesse `https://github.com/cesar-carlos/plug_agente/releases`.
2. Crie uma release para a tag `v1.2.7`.
3. Use titulo como `Version 1.2.7`.
4. Anexe `installer/dist/PlugAgente-Setup-1.2.7.exe`.
5. Publique como latest release quando for a versao estavel mais recente.

### 6. Validar automacao

Apos publicar, confira o workflow **Update Appcast on Release** em GitHub
Actions. Ele valida tag, versao, nome do asset, atualiza `appcast.xml` e roda
o smoke check do feed publicado usando `tool/appcast_manager.py`.

> **IMPORTANTE — Trigger automatico do update-appcast.**
>
> O `update-appcast.yml` so dispara automaticamente quando o GitHub Release e
> criado com um Personal Access Token (PAT). Releases publicadas com o
> `GITHUB_TOKEN` padrao nao propagam o evento `release.published` (protecao
> contra recursao de workflows) e exigem disparo manual:
>
> ```bash
> gh workflow run update-appcast.yml --ref main \
>   -f release_tag=v1.2.7 \
>   -f rollout_percentage=100 \
>   -f channel=stable
> ```
>
> Para automatizar, crie um PAT classico com escopo `repo` e configure-o como
> o segredo de repositorio `RELEASE_PUBLISH_TOKEN`. O `release.yml` ja prioriza
> esse segredo quando ele existe e cai para `GITHUB_TOKEN` (emitindo um
> `::warning::`) quando ausente.
>
> Passos:
>
> 1. GitHub > Settings > Developer settings > Personal access tokens > Tokens
>    (classic) > Generate new token (classic).
> 2. Escopo minimo: `repo` (apenas). Expiracao curta recomendada
>    (90 dias, com renovacao agendada).
> 3. No repositorio: Settings > Secrets and variables > Actions > New
>    repository secret > nome `RELEASE_PUBLISH_TOKEN`, valor = o PAT gerado.

Feed oficial:

```text
https://cesar-carlos.github.io/plug_agente/appcast.xml
```

Validacoes detalhadas do feed e do update ficam em
[auto_update_setup.md](auto_update_setup.md).

Validacao manual da release publicada:

```bash
python tool/validate_release.py \
  --tag v1.2.7 \
  --appcast appcast.xml
```

Para validar o feed remoto publicado:

```bash
python tool/validate_release.py \
  --tag v1.2.7 \
  --feed-url https://cesar-carlos.github.io/plug_agente/appcast.xml
```

## Fonte de Verdade do Appcast

O arquivo `tool/appcast_manager.py` concentra:

- geracao do item mais recente do `appcast.xml`;
- validacao estrutural do feed;
- smoke check do feed publicado;
- testes Python do fluxo de appcast.

Antes de mexer no workflow de update, atualize primeiro esse script e rode:

```bash
python -m unittest tool.test_appcast_manager -v
```

## Fluxo Manual para Depuracao

Use apenas quando precisar isolar uma etapa:

```bash
python installer/update_version.py
flutter build windows --release
ISCC installer/setup.iss
```

Preflight local completo antes de publicar manualmente:

```bash
python tool/release_preflight.py --version 1.2.7 --require-iscc --check-pages --analyze --tests
```

## Seguranca Operacional

- Para distribuicao ampla, priorize tambem assinatura de codigo do executavel e
  do instalador para reduzir alertas de SmartScreen e aumentar confianca no
  update.
- O script `installer/build_installer.py` assina `plug_agente.exe`,
  `plug_update_helper.exe`, `plug_agente_elevated_runner.exe` e o instalador
  `PlugAgente-Setup-<versao>.exe` quando `WINDOWS_CODE_SIGNING_CERT_PATH`
  aponta para um PFX. Use `WINDOWS_CODE_SIGNING_REQUIRED=true` para falhar
  explicitamente quando a assinatura nao estiver configurada.
- O workflow `Publish Windows Release` roda `signtool verify /pa /v` sobre
  instalador e `plug_update_helper.exe` apos o build. Esse gate falha o
  release quando qualquer dos dois nao tem cadeia confiavel. Use o input
  `skip_authenticode_check=true` apenas em rebuild manual sem certificado.
- O workflow tambem expoe o input `require_valid_update_signature`: quando
  `true`, compila o release com `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true` e
  forca `WINDOWS_CODE_SIGNING_REQUIRED=true`. Use somente depois que
  Authenticode estiver verde no helper e no instalador em duas releases.
- A retencao do `appcast.xml` e limitada pelo workflow para evitar crescimento
  indefinido do feed.
- O feed oficial e publicado via GitHub Pages usando Actions artifact; habilite
  `Settings` > `Pages` > `GitHub Actions` uma vez no repositorio.
- O CI executa `actionlint` nos workflows para detectar problemas de sintaxe,
  expressoes e scripts inline antes de usar o fluxo de release.
