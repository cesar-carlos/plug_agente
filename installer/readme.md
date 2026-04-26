# Instalador - Plug Agente

Scripts para gerar o instalador Windows (Inno Setup) do Plug Agente.

## Estrutura

```text
installer/
├── readme.md          # Este arquivo
├── constants.iss      # Constantes compartilhadas (autostart)
├── setup.iss          # Script Inno Setup (versão via update_version.py)
├── update_version.py  # Sincroniza versão em setup.iss
├── build_installer.py # Fluxo completo: update_version → flutter build → ISCC
└── dist/              # Saída do instalador (PlugAgente-Setup-{versão}.exe)
```

## Requisitos

- **Flutter** no PATH
- **Inno Setup 6** (ISCC no PATH ou em `C:\Program Files (x86)\Inno Setup 6\`)
- **Python 3.8+**
- **Microsoft Visual C++ Redistributable x64** no ambiente de destino

## Uso

### Fluxo rápido (recomendado)

```bash
python installer/build_installer.py
```

Executa automaticamente: `update_version.py` → `flutter build windows --release`
(com `--dart-define=AUTO_UPDATE_FEED_URL=...` quando disponível no `.env`) →
compilação Inno Setup.

### Fluxo manual/depuração

```bash
# 1. Sincronizar versão (pubspec.yaml → setup.iss + app_version.g.dart)
python installer/update_version.py

# 2. Build Flutter
flutter build windows --release

# 3. Compilar instalador diretamente
ISCC installer/setup.iss
```

## Scripts

| Script | Descrição |
|--------|-----------|
| `update_version.py` | Lê `version` do `pubspec.yaml` e atualiza `setup.iss` e `app_version.g.dart` |
| `build_installer.py` | Orquestra: update_version → flutter build (com `--dart-define` do feed) → Inno Setup |

## Saída

O instalador é gerado em:

```text
installer/dist/PlugAgente-Setup-{versão}.exe
```

O nome segue o padrão esperado pelo workflow **Update Appcast on Release** (`.github/workflows/update-appcast.yml`), que prioriza assets `PlugAgente-Setup-*.exe` no release.

## Integração com release e auto-update

O processo de versão, tag, publicação e validação do feed fica em
[docs/install/release_guide.md](../docs/install/release_guide.md) e
[docs/install/auto_update_setup.md](../docs/install/auto_update_setup.md).
Este diretório mantém apenas os scripts e o arquivo Inno Setup.

## Documentação relacionada

- [docs/install/readme.md](../docs/install/readme.md) - índice de instalação e release
- [docs/install/release_guide.md](../docs/install/release_guide.md) - processo completo de release
- [docs/install/auto_update_setup.md](../docs/install/auto_update_setup.md) - feed oficial, appcast e validações
