# Instalador - Plug Agente

Este diretorio contem os artefatos e scripts locais para gerar o instalador
Windows.

## Fluxo recomendado

Para publicacao final, prefira o workflow manual **Publish Windows Release** em
GitHub Actions. O fluxo local abaixo continua sendo a forma recomendada para
depurar build e instalador na maquina de desenvolvimento.

```bash
python installer/build_installer.py
```

Esse comando executa:

1. `python installer/update_version.py` (sincroniza versao em `pubspec.yaml`,
   `installer/setup.iss` e `lib/core/constants/app_version.g.dart`)
2. `flutter build windows --release` (gera `plug_agente.exe` e
   `plug_update_helper.exe` no bundle Release)
3. `tool/build_elevated_runner.ps1` (compila o helper Dart
   `plug_agente_elevated_runner.exe` em `tool/plug_agente_elevated_runner/` e
   copia para o bundle Release/Debug). O script falha cedo se esse helper nao
   estiver no bundle.
4. Validacao de que `plug_agente.exe`, `plug_update_helper.exe` e
   `plug_agente_elevated_runner.exe` estao no bundle Release.
5. Assinatura opcional, na ordem `plug_agente.exe`,
   `plug_update_helper.exe`, `plug_agente_elevated_runner.exe` e instalador,
   quando o certificado esta configurado.
6. `ISCC installer/setup.iss`
7. Assinatura opcional do `PlugAgente-Setup-<versao>.exe` gerado.

Quando o ambiente ou `.env` define `AUTO_UPDATE_FEED_URL`,
`AUTO_UPDATE_CHANNEL`, `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE`,
`AUTO_UPDATE_FEED_PUBLIC_KEY` ou `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE`, o build
injeta esses valores via `--dart-define`. Sem override de feed, o app usa o
feed oficial padrao.

`AUTO_UPDATE_REQUIRE_VALID_SIGNATURE` controla um gate em dois niveis: o lado
Dart bloqueia o spawn quando `plug_update_helper.exe` nao esta com Authenticode
valido; o helper nativo bloqueia o `setup.exe` quando o instalador nao esta
assinado. O `.env.example` e o default do codigo sao `true`; o workflow
`Publish Windows Release` mantem `false` enquanto o rollout de Authenticode
nao termina (plano `docs/implemente/plano_auto_update_evolution.md` fase 1E.2)
e expoe o input `require_valid_update_signature` para virar `true` quando
helper e instalador ja estiverem assinados ponta a ponta. Em builds locais que
ainda nao tem certificado configurado, exporte `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false`
no `.env` antes de rodar o build.

Antes de publicar manualmente, rode:

```bash
python tool/release_preflight.py --version {versao} --allow-dirty --require-iscc --check-pages
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
python tool/release_preflight.py --version {versao} --allow-dirty --check-installer \
  --feed-public-key "$AUTO_UPDATE_FEED_PUBLIC_KEY"
```

Para uma validacao completa no GitHub Actions sem publicar, use o workflow
manual **Release Preflight**. Ele gera o instalador, valida o helper nativo,
roda `tool/validate_launcher_status.py` contra o status JSON e salva os
artifacts sem criar commit, tag ou release.

Assinatura de codigo e opcional. Se `WINDOWS_CODE_SIGNING_CERT_PATH` apontar
para um certificado PFX, o script assina `plug_agente.exe`,
`plug_update_helper.exe`, `plug_agente_elevated_runner.exe` e o instalador
(`PlugAgente-Setup-<versao>.exe`). Use `WINDOWS_CODE_SIGNING_CERT_PASSWORD`
para senha do PFX e `WINDOWS_CODE_SIGNING_REQUIRED=true` para falhar quando a
assinatura nao estiver configurada.

No workflow `Publish Windows Release`, o passo `Verify Authenticode
signatures` valida `signtool verify /pa /v` para installer e helper apos o
build. Ele falha o release se qualquer dos dois nao estiver assinado pela
cadeia confiavel. Use o input `skip_authenticode_check=true` apenas em
rebuild manual sem certificado disponivel; nesse caso confirme depois com
`signtool verify /pa` localmente.

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
