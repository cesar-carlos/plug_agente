# Instalador Inno Setup - Plug Agente

Scripts para gerar o instalador Windows do Plug Agente.

## Requisitos

- **Flutter** no PATH
- **Inno Setup 6** instalado (https://jrsoftware.org/isinfo.php)
- **Python 3.8+**

## Uso

```bash
# 1. Sincronizar versão (pubspec.yaml -> setup.iss, .env)
python installer/update_version.py

# 2. Build Flutter
flutter build windows --release

# 3. Compilar instalador
python installer/build_installer.py
```

Ou em um único comando:

```bash
python installer/build_installer.py
```

O script `build_installer.py` executa `update_version.py` e `flutter build` automaticamente.

## Saída

O instalador será gerado em:

```
installer/dist/PlugAgente-Setup-{versão}.exe
```

## Scripts

| Script | Descrição |
|--------|-----------|
| `update_version.py` | Lê versão do pubspec.yaml e atualiza setup.iss e .env |
| `build_installer.py` | Executa update_version, flutter build e compila Inno Setup |

## Documentação

Para guias completos de instalação, release e auto-update, consulte [docs/install/](../docs/install/README.md).
