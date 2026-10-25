# Instalador - Plug Agente

Este diretorio contem os artefatos e scripts locais para gerar o instalador
Windows.

## Atualização sem certificado comercial

O modo gratuito usa `signing_provider=manifest` no workflow **Publish Windows Release**
(padrão) ou `python installer/build_installer.py` no build local. `--manifest-only` permanece como alias.
Esse modo exige chaves Ed25519 para feed e manifesto e mantém SHA-256, tamanho,
canal, versão crescente e permissões administrativas registradas. A primeira
instalação global requer administrador para registrar o serviço e proteger os
binários. Os executáveis não recebem Authenticode; o Windows poderá mostrar
publicador desconhecido na instalação manual.

O novo adaptador Windows usa exclusivamente o serviço: indisponibilidade não
aciona o helper com UAC. A aplicação automática **continua bloqueada** pelos gates
`kApplicationContractImplemented=false` e `applicationContractValidated=false`.
Transition acceptance is still in progress. Do not publish this candidate as
a completed automatic updater; production distribution remains subject to the
coordinated release gate. Consulte o [estado detalhado](../docs/implemente/plano_auto_update_evolution.md).

## SignPath opcional

Referência histórica: desativado nos fluxos oficiais. O build recusa
`--prepare-signpath`, PFX e flags de confiança conflitantes.

A SignPath Foundation recusou a candidatura em 2026-10-06 por visibilidade pública
insuficiente. A integração fica disponível para uma eventual contratação ou
nova aprovação; não é dependência do modo `manifest`.

Os provedores opcionais `pfx` e `signpath` mantêm Authenticode obrigatório em
produção. SignPath faz duas solicitações: componentes e uninstaller, depois
instalador final. A política SignPath deve exigir aprovação manual de cada
solicitação. A preparação local usa `python installer/build_installer.py --prepare-signpath`.
Entradas intermediárias em `installer/signpath-work` não são artefatos de distribuição.

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

Automatic-application status and acceptance are maintained only in the
[updater plan](../docs/implemente/plano_auto_update_evolution.md).

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

A dependencia `odbc_fast` vem do pub.dev. O build prepara a biblioteca nativa
da release oficial correspondente ao `pubspec.lock`, verifica o SHA-256 e
inclui `data/odbc_native_manifest.json` no bundle, sem compilar o engine Rust.

Esse comando executa:

1. `flutter build windows --release` (gera `plug_agente.exe` e
   `plug_update_helper.exe` no bundle Release). Passe `--sync-version` se
   quiser sincronizar `pubspec.yaml`, `installer/setup.iss` e
   `lib/core/constants/app_version.g.dart` via `update_version.py` antes do
   build. Sem essa flag a versao atual e preservada (util para testes locais).
2. `python tool/elevated/build_elevated_runner.py --release-only` (compila o helper Dart
   `plug_agente_elevated_runner.exe` em `tool/plug_agente_elevated_runner/` e
   copia para o bundle Release). O script falha cedo se esse helper nao
   estiver no bundle.
3. Compila e valida também `updater/plug_update_service.exe`, `plug_update_client.exe` e `plug_update_worker.exe`. O instalador coloca controle em `%ProgramFiles%\PlugAgenteUpdater` e workers em `workers/<versão+build>`, fora do bundle substituído. `build_installer.py` compila o parâmetro `MyAppWorkerVersion` a partir do `pubspec.yaml`.
4. Validacao de que `plug_agente.exe`, `plug_update_helper.exe` e
   `plug_agente_elevated_runner.exe` estao no bundle Release.
5. Assinatura do aplicativo, helper, runner elevado, servico, cliente e worker.
   Obrigatória para os provedores `pfx` e `signpath`; `manifest` usa Ed25519
   no feed e manifesto, sem Authenticode nos executáveis.
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
assinado. O provedor `manifest` desliga somente Authenticode, no Dart e no
contrato nativo; a assinatura Ed25519 continua obrigatória. Os demais provedores
mantêm ambos os tipos de assinatura em produção.

O build embute as mesmas chaves públicas no Dart e no supervisor nativo. O
canal também é compilado no setup, para enrollment e `install-mode.ini`.
Instalação interativa global oferece autorização do serviço; instalação
silenciosa nova exige `/AUTOUPDATE=1`. Upgrades silenciosos preservam a
autorização administrativa existente. Desmarcar a opção revoga aplicações
futuras. Enrollment valida publicador, ACL e contrato do serviço já registrado.

Enrollment does not override the automatic-application gates described above.

Para validar a sintaxe do Inno Setup sem o bundle Flutter (o mesmo gate do
job `iss-syntax` no Flutter CI), rode:

```bash
python tool/release/release_preflight.py --compile-iss
```

Esse comando chama `ISCC /DCOMPILE_SCRIPT_ONLY` e grava o exe em um diretorio
temporario (nunca em `installer/dist`). A diretiva omite a secao `[Files]`
porque o payload Release nao existe em PRs.

Version preflight, embedded feed-key checks, release workflow inputs and
provider-specific signing requirements are maintained in the
[release guide](../docs/install/release_guide.md). Follow that guide before
publication. Do not use local build success to bypass its release gates.

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
