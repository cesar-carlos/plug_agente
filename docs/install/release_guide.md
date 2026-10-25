# Guia de Release e Versionamento

> Revisão de 2026-10-06: `signing_provider=manifest` (padrão no publish) e
> `build_installer.py` (ou o alias `--manifest-only`) exigem Ed25519 do feed/manifesto e SHA-256,
> sem certificado Authenticode. Exigências de certificado neste guia se aplicam
> aos provedores opcionais `pfx`/`signpath`. As chaves do feed continuam obrigatórias.
> O novo adaptador Windows usa o serviço sem fallback com UAC, mas a aplicação
> automática permanece bloqueada até concluir e homologar a transição. Consulte
> o [estado atual](../implemente/plano_auto_update_evolution.md) antes de publicar.


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

## Bloqueio coordenado persona-v2

`python tool/release/check_persona_release.py` requires all coordinated gates in
[contracts/persona-v2-release.json](../../contracts/persona-v2-release.json),
including `shared-knowledge-and-compatibility`. The manifest remains
`ready: false` with no completed gates. Partial homologation does not authorize
installer, appcast or production publication.

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
Também imprime avisos sobre as chaves obrigatórias de assinatura do feed
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
   - `signing_provider`: somente `manifest`;
   - `prerelease`: use apenas para versoes de validacao;
   - `dry_run`: gera e valida o instalador sem criar commit, tag ou release.
5. Apos a publicacao, confirme que o workflow **Update Appcast on Release**
   terminou com sucesso como chamada reutilizável do publish, sem PAT nem evento secundário.

Use `dry_run=true` para validar uma versao antes de publica-la. O workflow
continua atualizando a versao no workspace temporario do runner, rodando
preflight e gerando o instalador, mas encerra antes dos passos destrutivos.

O único modo oficial é `manifest`, com `APPCAST_SIGNING_PRIVATE_KEY` e
`AUTO_UPDATE_FEED_PUBLIC_KEY`. Não há certificado Authenticode. PFX/SignPath ficam
preservados como ferramentas históricas, desativadas nos workflows oficiais.
Configurações conflitantes são recusadas antes do build. Os testes obrigatórios
e os gates coordenados de produção continuam exigidos; este documento não
autoriza publicar o candidato sem homologação instalada e aceite explícitos.

O token padrão `github.token` publica a release; `update-appcast.yml` é chamado
como workflow reutilizável e não depende de `RELEASE_PUBLISH_TOKEN`.

O canal passa ao aplicativo, instalador e feed. Prerelease é `beta` e não pode
ser publicada em `stable`. Setup e manifesto são assets obrigatórios. Antes de
publicar, o workflow verifica assinatura Ed25519, bytes do setup e commit da
tag. Deploy/smoke usam o commit exato do feed. O rollout inicial é 5%; avanços
para 25% e 100% exigem pelo menos 48 horas de observação por etapa.

A base do serviço ainda está bloqueada: não publique esta mudança como
atualização automática concluída antes dos itens pendentes registrados em
[plano_auto_update_evolution.md](../implemente/plano_auto_update_evolution.md).

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

O `installer/build_installer.py` usa o pacote `odbc_fast: ^5.0.1` do pub.dev,
com a versao exata e o hash do pacote registrados no `pubspec.lock`.
`tool/odbc/prepare_package_native.py` baixa a biblioteca nativa da release
oficial correspondente e exige o SHA-256 publicado antes de disponibiliza-la
ao hook por `ODBC_FAST_NATIVE_LIBRARY`. Nao compila o engine Rust nem altera
o cache do Pub. Antes de empacotar, exige que a DLL no bundle tenha esse mesmo
hash. A origem, versao e hashes ficam em `data/odbc_native_manifest.json`.

Local build stages and component packaging are maintained in the
[installer guide](../../installer/readme.md#fluxo-recomendado).
O build local usa manifest por padrão; `--manifest-only` é um alias compatível.
Os fluxos oficiais recusam provedores de certificado. Do not treat an unsigned
development build as a release artifact.

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

Após publicar, confira a chamada reutilizável **Update Appcast on Release**,
incluindo deploy e smoke do commit publicado. Para publicação manual, anexe o
manifesto assinado correspondente; execute o workflow com a tag e canal corretos:

```bash
gh workflow run update-appcast.yml --ref main \
  -f release_tag=v1.2.7 \
  -f rollout_percentage=5 \
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

Use the [local installer workflow](../../installer/readme.md#fluxo-recomendado)
to debug packaging. A raw Flutter build followed by ISCC omits required native
components and signing checks.

For Inno syntax only (without a Flutter payload):

```powershell
python tool/release/release_preflight.py --compile-iss
```

## Seguranca Operacional

- Apply the signing-provider requirements above. Certificate providers require
  Authenticode on project executables and the installer; `manifest` requires
  Ed25519 feed/manifest signatures without claiming an Authenticode publisher.
- Never publish while the coordinated release manifest remains blocked.
- The [installer guide](../../installer/readme.md) owns component signing details;
  the [auto-update guide](auto_update_setup.md) owns runtime feed validation.

- A retencao do `appcast.xml` e limitada pelo workflow (`MAX_APPCAST_ITEMS=10`)
  para evitar crescimento indefinido do feed.
- O feed oficial e publicado via GitHub Pages; a configuracao unica esta em
  [auto_update_setup.md](auto_update_setup.md).
- O CI executa `actionlint` nos workflows para detectar problemas de sintaxe,
  expressoes e scripts inline antes de usar o fluxo de release.
