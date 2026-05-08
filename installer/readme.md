# Instalador - Plug Agente

Este diretorio contem os artefatos e scripts locais para gerar o instalador
Windows.

## Fluxo recomendado

```bash
python installer/build_installer.py
```

Esse comando executa:

1. `python installer/update_version.py`
2. `flutter build windows --release`
3. `ISCC installer/setup.iss`

Quando `.env` define `AUTO_UPDATE_FEED_URL`, o build recebe
`--dart-define=AUTO_UPDATE_FEED_URL=...`. Sem override, o app usa o feed
oficial padrao.

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
