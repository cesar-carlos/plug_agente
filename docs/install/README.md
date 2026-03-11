# Instalação - Plug Agente

Documentação e scripts de instalação do Plug Agente.

## Documentos

| Documento | Descrição |
|-----------|-----------|
| [installation_guide.md](installation_guide.md) | Guia passo a passo para o usuário final |
| [requirements.md](requirements.md) | Requisitos do sistema |
| [path_setup.md](path_setup.md) | Configuração de PATH (ODBC, etc.) |
| [release_guide.md](release_guide.md) | Como criar releases (desenvolvedores) |
| [auto_update_setup.md](auto_update_setup.md) | Configuração do auto-update via GitHub |
| [testing_auto_update.md](testing_auto_update.md) | Como testar o auto-update |
| [VERSION_STRATEGY.md](VERSION_STRATEGY.md) | Estratégia de versionamento |

## Scripts

| Script | Uso |
|--------|-----|
| [install_monitor.bat](../../install_monitor.bat) | Instala o PlugPortMon (monitor de portas) - executar como administrador |
| [uninstall_monitor.bat](uninstall_monitor.bat) | Desinstala o PlugPortMon - executar como administrador |

## Instalador Inno Setup

O instalador principal é gerado pela pasta `installer/`:

```bash
python installer/update_version.py
flutter build windows --release
python installer/build_installer.py
```

O executável será gerado em `installer/dist/PlugAgente-Setup-{versão}.exe`.
