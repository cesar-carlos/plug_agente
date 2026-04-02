# Instalação - Plug Agente

Índice canônico da documentação de instalação, empacotamento Windows e
atualização automática.

## Compatibilidade

- **Windows 10/11**: suporte completo
- **Windows 8/8.1 e Windows Server 2012+**: suporte degradado
- **Abaixo de Windows 8 / Server 2012**: não suportado

Checklist e matriz detalhada em [requirements.md](requirements.md).

## Fluxos mais comuns

### Instalar no cliente

1. Validar ambiente em [requirements.md](requirements.md)
2. Executar os passos de [installation_guide.md](installation_guide.md)
3. Usar [install_monitor.bat](../../install_monitor.bat) apenas se houver
   necessidade de PlugPortMon

### Gerar instalador para release

1. Revisar versionamento em [version_strategy.md](version_strategy.md)
2. Executar `python installer/build_installer.py`
3. Publicar conforme [release_guide.md](release_guide.md)

Saída esperada: `installer/dist/PlugAgente-Setup-{versão}.exe`.

## Documentos operacionais

| Documento                                      | Quando usar                                                    |
| ---------------------------------------------- | -------------------------------------------------------------- |
| [installation_guide.md](installation_guide.md) | Instalação, desinstalação e validação básica no Windows        |
| [requirements.md](requirements.md)             | Pré-requisitos, compatibilidade e notas opcionais de ODBC/PATH |

## Documentos de release e update

| Documento                                        | Quando usar                                          |
| ------------------------------------------------ | ---------------------------------------------------- |
| [release_guide.md](release_guide.md)             | Checklist operacional para build, tag e publicação   |
| [version_strategy.md](version_strategy.md)       | Fonte de verdade para versão e convenção de tags     |
| [auto_update_setup.md](auto_update_setup.md)     | Configuração do feed, appcast e assinatura DSA       |
| [testing_auto_update.md](testing_auto_update.md) | Validação do fluxo automático e silencioso de update |

## Scripts úteis

| Script                                           | Uso                                                                            |
| ------------------------------------------------ | ------------------------------------------------------------------------------ |
| `python installer/build_installer.py`            | Fluxo recomendado: sincroniza versão, faz build Flutter e compila o Inno Setup |
| `python installer/update_version.py`             | Fluxo manual/avançado para sincronizar versão sem gerar instalador             |
| [install_monitor.bat](../../install_monitor.bat) | Instalar PlugPortMon como administrador                                        |
