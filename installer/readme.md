# Instalador - Plug Agente

Este diretorio contem os artefatos e scripts locais para gerar o instalador
Windows.

## SignPath readiness

The application was submitted on 2026-10-06; SignPath acknowledged receipt.
Approval and account provisioning are pending. The [code signing and privacy
policies](../readme.md#code-signing-policy), MIT license, PlutoGrid migration,
bundled Montserrat fonts and release integration are prepared locally.
Publish these reviewed changes so the policies are accessible during review.

The **Publish Windows Release** workflow now accepts `signing_provider=pfx`
(the default) or `signing_provider=signpath`. SignPath builds on GitHub-hosted
Windows runners and makes two requests: the seven project executables plus
Inno's uninstaller, followed by the packaged installer. Every signing request
must require manual approval in the SignPath policy. Local preparation uses
`python installer/build_installer.py --prepare-signpath`; inputs are placed in
`installer/signpath-work`, which must be empty before a new preparation.
Staged unsigned inputs are not distribution artifacts.

After approval, configure:

| GitHub setting | Purpose |
| --- | --- |
| Secret `SIGNPATH_API_TOKEN` | Submitter token limited to the approved project/policy |
| Variable `SIGNPATH_ORGANIZATION_ID` | Approved organization ID |
| Variable `SIGNPATH_PROJECT_SLUG` | Project slug |
| Variable `SIGNPATH_SIGNING_POLICY_SLUG` | Policy requiring manual approval |
| Variable `SIGNPATH_COMPONENTS_CONFIGURATION` | Slug for imported `signpath-components.xml` |
| Variable `SIGNPATH_INSTALLER_CONFIGURATION` | Slug for imported `signpath-installer.xml` |

Keep the existing feed secrets `APPCAST_SIGNING_PRIVATE_KEY` and
`AUTO_UPDATE_FEED_PUBLIC_KEY`. Confirm MFA and author/reviewer/approver roles,
configure SignPath's GitHub trusted build integration, import the two XML
configurations and validate a release with `dry_run=true` and
`signing_provider=signpath` before production publication. The remote service
cannot be tested until approval and these settings exist.

All executables receive the same logical product name and full application
version before signing. Inno stores padded strings in its version resources;
the workflow passes those exact strings as metadata restriction parameters.
It preserves the original uninstaller bytes, including Inno's internal checks.
Dart AOT payloads survive metadata editing and are exercised with `--help`.
Returned files must have unchanged executable content, trusted Authenticode
signatures and the same certificate across components and installer. Bundle,
input and configuration hashes prevent reusing signing inputs after changes.
Third-party DLLs are included without signing them as project-owned code.

The installer displays the privacy notice before installation and copies the
MIT and Montserrat licenses. The interface uses bundled fonts without Google
font requests. The original dependency scan found MIT, BSD, Apache and MPL
texts; this remains a heuristic, not a complete binary redistribution audit.

Automatic update application is a separate outstanding feature:
`kApplicationContractImplemented=false` and
`applicationContractValidated=false` remain until a non-elevated launcher,
authenticated health/probation, original-user data recovery and rollback
migration handling are integrated and validated. See
[updater status](../docs/implemente/plano_auto_update_evolution.md).

References: [SignPath conditions](https://signpath.org/terms.html),
[GitHub integration](https://docs.signpath.io/trusted-build-systems/github),
[Inno Setup signed uninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm).

## Fluxo recomendado

Para publicacao final, prefira o workflow manual **Publish Windows Release** em
GitHub Actions. O fluxo local abaixo continua sendo a forma recomendada para
depurar build e instalador na maquina de desenvolvimento.

```bash
python installer/build_installer.py
```

Esse comando executa:

1. `flutter build windows --release` (gera `plug_agente.exe` e
   `plug_update_helper.exe` no bundle Release). Passe `--sync-version` se
   quiser sincronizar `pubspec.yaml`, `installer/setup.iss` e
   `lib/core/constants/app_version.g.dart` via `update_version.py` antes do
   build. Sem essa flag a versao atual e preservada (util para testes locais).
2. `python tool/elevated/build_elevated_runner.py` (compila o helper Dart
   `plug_agente_elevated_runner.exe` em `tool/plug_agente_elevated_runner/` e
   copia para o bundle Release/Debug). O script falha cedo se esse helper nao
   estiver no bundle.
3. Compila e valida também `updater/plug_update_service.exe`, `plug_update_client.exe` e `plug_update_worker.exe`. O instalador coloca controle em `%ProgramFiles%\PlugAgenteUpdater` e workers em `workers/<versão+build>`, fora do bundle substituído. `build_installer.py` compila o parâmetro `MyAppWorkerVersion` a partir do `pubspec.yaml`.
4. Validacao de que `plug_agente.exe`, `plug_update_helper.exe` e
   `plug_agente_elevated_runner.exe` estao no bundle Release.
5. Assinatura do aplicativo, helper, runner elevado, servico, cliente e worker.
   Obrigatoria em producao; artefatos sem assinatura sao restritos a
   desenvolvimento/dry-run, sem distribuicao.
6. `ISCC installer/setup.iss`. Com certificado, o ISCC recebe `SignTool` e
   `SignedUninstaller=yes` para assinar o setup e o uninstaller embutido.
7. `signtool verify` no `PlugAgente-Setup-<versao>.exe` quando a assinatura
   estiver configurada.

Quando o ambiente ou `.env` define `AUTO_UPDATE_FEED_URL`,
`AUTO_UPDATE_CHANNEL`, `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE`,
`AUTO_UPDATE_FEED_PUBLIC_KEY` ou `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE`, o build
injeta esses valores via `--dart-define`. Sem override de feed, o app usa o
feed oficial padrao.

`AUTO_UPDATE_REQUIRE_VALID_SIGNATURE` controla um gate em dois niveis: o lado
Dart bloqueia o spawn quando `plug_update_helper.exe` nao esta com Authenticode
valido; o helper nativo bloqueia o `setup.exe` quando o instalador nao esta
assinado. Produção exige esse gate e assinatura do feed; os inputs de
publicação são `true` por padrão. Artefatos locais sem certificado podem ser
usados apenas para desenvolvimento/dry-run, sem distribuição automática.

O build embute as mesmas chaves públicas no Dart e no supervisor nativo. O
canal também é compilado no setup, para enrollment e `install-mode.ini`.
Instalação interativa global oferece autorização do serviço; instalação
silenciosa nova exige `/AUTOUPDATE=1`. Upgrades silenciosos preservam a
autorização administrativa existente. Desmarcar a opção revoga aplicações
futuras. Enrollment valida publicador, ACL e contrato do serviço já registrado.

**Estado atual:** enrollment e controle estão implementados, mas
`kApplicationContractImplemented=false` e `applicationContractValidated=false` bloqueiam aplicação automática. Launcher,
manutenção ligada ao runtime e recuperação completa ainda precisam ser
integrados e homologados antes de distribuição; veja
[status](../docs/implemente/plano_auto_update_evolution.md).

Para validar a sintaxe do Inno Setup sem o bundle Flutter (o mesmo gate do
job `iss-syntax` no Flutter CI), rode:

```bash
python tool/release/release_preflight.py --compile-iss
```

Esse comando chama `ISCC /DCOMPILE_SCRIPT_ONLY` e grava o exe em um diretorio
temporario (nunca em `installer/dist`). A diretiva omite a secao `[Files]`
porque o payload Release nao existe em PRs.

Antes de publicar manualmente, rode:

```bash
python tool/release/release_preflight.py --version {versao} --allow-dirty --require-iscc --check-pages
```

`--allow-dirty` libera o gate de working tree limpo enquanto voce ainda esta
ajustando arquivos antes do bump; remova quando rodar a validacao final do
commit de release. O preflight precisa de `git`, `python`, `flutter` e `gh`
(quando `--check-pages`) no PATH; se faltar, o erro lista o comando
ausente.

Para tambem validar que a chave publica Ed25519 do feed esta embutida no
instalador (evita builds que esqueceram o `--dart-define`), rode apos o
`build_installer.py`:

```bash
python tool/release/release_preflight.py --version {versao} --allow-dirty --check-installer \
  --feed-public-key "$AUTO_UPDATE_FEED_PUBLIC_KEY"
```

Para uma validacao completa no GitHub Actions sem publicar, use o workflow
manual **Release Preflight**. Ele gera o instalador, valida o helper nativo,
roda `tool/appcast/validate_launcher_status.py` contra o status JSON e salva os
artifacts sem criar commit, tag ou release.

Assinatura de código é obrigatória em produção e opcional somente em desenvolvimento sem distribuição. Se `WINDOWS_CODE_SIGNING_CERT_PATH` apontar
para um certificado PFX, o script assina `plug_agente.exe`,
`plug_update_helper.exe`, `plug_agente_elevated_runner.exe` e os componentes
`plug_update_service.exe`, `plug_update_client.exe`, `plug_update_worker.exe`, e passa
`SignTool` ao ISCC (`SignedUninstaller=yes`) para o instalador e o
uninstaller embutido. Use `WINDOWS_CODE_SIGNING_CERT_PASSWORD` para senha do
PFX e `WINDOWS_CODE_SIGNING_REQUIRED=true` para falhar quando a assinatura
nao estiver configurada. Builds locais unsigned nao definem `SignTool`.

No workflow `Publish Windows Release`, o passo `Verify Authenticode
signatures` valida `signtool verify /pa /v` para installer e helper apos o
build. Ele falha o release se qualquer dos dois nao estiver assinado pela
cadeia confiável. O gate inclui aplicativo, helper, runner elevado, serviço, cliente, worker e setup. `skip_authenticode_check=true` é restrito a dry-run sem distribuição.

## Saida

```text
installer/dist/PlugAgente-Setup-{MAJOR.MINOR.PATCH}.exe
```

Esse nome precisa bater com a tag da release para o workflow de appcast.

## Fonte operacional

Para processo completo de versionamento, release, appcast e auto-update, use:

- [docs/install/readme.md](../docs/install/readme.md)
- [docs/install/release_guide.md](../docs/install/release_guide.md)
- [docs/install/auto_update_setup.md](../docs/install/auto_update_setup.md)
