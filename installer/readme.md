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

1. `python installer/update_version.py`
2. `flutter build windows --release`
3. validacao de que `plug_update_helper.exe` esta no bundle Release
4. assinatura opcional de `plug_agente.exe`, `plug_update_helper.exe` e
   instalador, quando configurada
5. `ISCC installer/setup.iss`

Quando o ambiente ou `.env` define `AUTO_UPDATE_FEED_URL`,
`AUTO_UPDATE_CHANNEL` ou `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE`, o build injeta
esses valores via `--dart-define`. Sem override de feed, o app usa o feed
oficial padrao. Mantenha `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false` em
producao ate a assinatura Authenticode estar validada ponta a ponta.

Antes de publicar manualmente, rode:

```bash
python tool/release_preflight.py --version {versao} --require-iscc --check-pages
```

Para uma validacao completa no GitHub Actions sem publicar, use o workflow
manual **Release Preflight**. Ele gera o instalador, valida o helper nativo e
salva logs/status JSON como artifacts sem criar commit, tag ou release.

Assinatura de codigo e opcional. Se `WINDOWS_CODE_SIGNING_CERT_PATH` apontar
para um certificado PFX, o script assina `plug_agente.exe`, o helper nativo de
update `plug_update_helper.exe` e o instalador. Use
`WINDOWS_CODE_SIGNING_CERT_PASSWORD` para senha do PFX e
`WINDOWS_CODE_SIGNING_REQUIRED=true` para falhar quando a assinatura nao estiver
configurada.

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
