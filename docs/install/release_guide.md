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
python tool/release/pre_publish_release.py --version 1.8.4
```

Equivalente manual:

```bash
python tool/release/release_preflight.py --version 1.8.4 --gate --check-secrets --print-publish-hints
```

O gate executa `flutter analyze`, `flutter test --exclude-tags "live || slow || perf"`,
`test/architecture/layer_boundaries_test.dart` e os testes Python de appcast.
Tambem imprime avisos sobre secrets (`RELEASE_PUBLISH_TOKEN`, assinatura, feed key)
e os comandos `gh workflow run` sugeridos.

Hook git opcional (pre-push em `main` quando `pubspec.yaml`, `lib/` ou `test/` mudam):

```powershell
python tool/dev/install_git_hooks.py
# pular uma vez: $env:SKIP_RELEASE_GATE = '1'
```

## Processo Recomendado

O caminho preferencial e o workflow manual **Publish Windows Release** em
GitHub Actions. Ele atualiza a versao, valida sincronizacao, gera o instalador
Windows, cria commit/tag/release e anexa o asset correto.

Ordem sugerida:

1. `python tool/release/pre_publish_release.py --version X.Y.Z` (local).
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
  sozinho apos a release. Releases criadas com o `GITHUB_TOKEN` padrao nao
  propagam `release.published`; sem o PAT, o step **Dispatch appcast update
  without PAT** do **Publish Windows Release** dispara **Update Appcast on
  Release** como fallback. Para criar o PAT: GitHub > Settings > Developer
  settings > Personal access tokens > Tokens (classic), escopo `repo` apenas,
  expiracao curta (ex.: 90 dias); depois Settings > Secrets and variables >
  Actions > New repository secret `RELEASE_PUBLISH_TOKEN`.

Secrets e variables do feed assinado (`AUTO_UPDATE_FEED_PUBLIC_KEY`,
`APPCAST_SIGNING_PRIVATE_KEY`, `vars.AUTO_UPDATE_REQUIRE_FEED_SIGNATURE`)
ficam em [auto_update_setup.md](auto_update_setup.md).

## Processo Local Manual

### 1. Atualizar versao

Edite `pubspec.yaml`:

```yaml
version: 1.2.7+2
```

### 2. Gerar build Windows e instalador

```bash
python installer/update_version.py
python tool/release/release_preflight.py --version 1.2.7 --allow-dirty --require-iscc --check-pages
python installer/build_installer.py
python tool/release/release_preflight.py --version 1.2.7 --allow-dirty --check-installer \
  --feed-public-key "$AUTO_UPDATE_FEED_PUBLIC_KEY"
```

O `installer/build_installer.py` executa:

1. Recusa o build se `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE` resolver para
   `true` (default quando ausente) sem assinatura configurada; para build local
   sem certificado, defina `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false`
2. `installer/update_version.py` somente com `--sync-version`
3. `flutter build windows --release`
4. `python tool/elevated/build_elevated_runner.py` (`dart build cli`, copia
   `plug_agente_elevated_runner.exe` e sidecars nativos para o bundle
   Release/Debug; obrigatorio)
5. Validacao de presenca de `plug_agente.exe`, `plug_update_helper.exe` e
   `plug_agente_elevated_runner.exe` no bundle Release
6. Assinatura opcional de `plug_agente.exe`, `plug_update_helper.exe` e
   `plug_agente_elevated_runner.exe`
7. `ISCC installer/setup.iss` (com `SignTool` + `SignedUninstaller` quando o
   certificado estiver configurado) e `signtool verify` do instalador assinado

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
Actions (os dois runs: o de `release.published` e o redespacho que publica o
Pages; detalhes em [auto_update_setup.md](auto_update_setup.md)). Se ele nao
disparar, rode manualmente:

```bash
gh workflow run update-appcast.yml --ref main \
  -f release_tag=v1.2.7 \
  -f rollout_percentage=100 \
  -f channel=stable
```

Validacao manual da release publicada:

```bash
python tool/appcast/validate_release.py \
  --tag v1.2.7 \
  --appcast appcast.xml
```

Para validar o feed remoto publicado:

```bash
python tool/appcast/validate_release.py \
  --tag v1.2.7 \
  --feed-url https://cesar-carlos.github.io/plug_agente/appcast.xml
```

## Tooling do Appcast

Modulos Python, workflows e testes do appcast estao em **Fonte de Verdade do
Appcast** em [auto_update_setup.md](auto_update_setup.md). Antes de mexer no
workflow de update, atualize primeiro o tooling e rode os testes listados la.

## Fluxo Manual para Depuracao

Use apenas quando precisar isolar uma etapa:

```bash
python installer/update_version.py
flutter build windows --release
python tool/elevated/build_elevated_runner.py
ISCC installer/setup.iss
```

Para validar so a sintaxe do `setup.iss` (sem payload Flutter), use
`python tool/release/release_preflight.py --compile-iss`.

Preflight local completo antes de publicar manualmente:

```bash
python tool/release/release_preflight.py --version 1.2.7 --require-iscc --check-pages --analyze --tests
```

## Seguranca Operacional

- Para distribuicao ampla, priorize tambem assinatura de codigo do executavel e
  do instalador para reduzir alertas de SmartScreen e aumentar confianca no
  update.
- O script `installer/build_installer.py` assina `plug_agente.exe`,
  `plug_update_helper.exe` e `plug_agente_elevated_runner.exe`, e passa
  `SignTool` ao ISCC (`SignedUninstaller=yes`) para o instalador e o
  uninstaller embutido quando `WINDOWS_CODE_SIGNING_CERT_PATH` aponta para um
  PFX. Use `WINDOWS_CODE_SIGNING_REQUIRED=true` para falhar
  explicitamente quando a assinatura nao estiver configurada.
- O workflow `Publish Windows Release` roda `signtool verify /pa /v` sobre
  instalador e `plug_update_helper.exe` apos o build quando ha certificado.
  Esse gate falha o release quando qualquer dos dois nao tem cadeia
  confiavel. Sem certificado o gate e pulado automaticamente; o input
  `skip_authenticode_check=true` so e necessario para pular o gate mesmo com
  certificado (uso restrito).
- O workflow tambem expoe o input `require_valid_update_signature`: quando
  `true`, compila o release com `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true` e
  forca `WINDOWS_CODE_SIGNING_REQUIRED=true`. Criterio de promocao em
  [auto_update_setup.md](auto_update_setup.md).
- A retencao do `appcast.xml` e limitada pelo workflow (`MAX_APPCAST_ITEMS=10`)
  para evitar crescimento indefinido do feed.
- O feed oficial e publicado via GitHub Pages; a configuracao unica esta em
  [auto_update_setup.md](auto_update_setup.md).
- O CI executa `actionlint` nos workflows para detectar problemas de sintaxe,
  expressoes e scripts inline antes de usar o fluxo de release.
