# Instalação - Plug Agente

Índice da documentação de instalação, release e atualização automática.

## Compatibilidade (resumo)

- **Windows 10/11**: suporte completo (todos os recursos)
- **Windows 8/8.1 e Windows Server 2012+**: suporte degradado (sem tray, notificações, auto-update)
- **Abaixo de Windows 8 / Server 2012**: não suportado

Detalhes e checklist em [requirements.md](requirements.md).

## Documentos para operação

| Documento | Quando usar |
|-----------|-------------|
| [installation_guide.md](installation_guide.md) | Instalar/desinstalar no ambiente do cliente |
| [requirements.md](requirements.md) | Validar requisitos mínimos e matriz de compatibilidade |
| [path_setup.md](path_setup.md) | Ajustar PATH apenas se driver/ferramenta ODBC não for encontrada |

## Documentos para release/update

| Documento | Quando usar |
|-----------|-------------|
| [release_guide.md](release_guide.md) | Criar e publicar release com instalador |
| [version_strategy.md](version_strategy.md) | Regras de versionamento e tags |
| [auto_update_setup.md](auto_update_setup.md) | Configurar feed/appcast e assinatura DSA |
| [testing_auto_update.md](testing_auto_update.md) | Validar fluxo automático e silencioso de update |

## Scripts

| Script | Uso |
|--------|-----|
| [install_monitor.bat](../../install_monitor.bat) | Instalar PlugPortMon (executar como administrador) |

## Build do instalador

```bash
python installer/update_version.py
flutter build windows --release
python installer/build_installer.py
```

Saída: `installer/dist/PlugAgente-Setup-{versão}.exe`.
