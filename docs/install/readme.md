# Instalação - Plug Agente

Índice canônico da documentação de instalação, empacotamento Windows e
atualização automática.

## Compatibilidade

- **Windows 10/11**: suporte completo
- **Windows Server 2016+**: suporte com possíveis recursos degradados
- **Windows 8/8.1 e Windows Server 2012/2012 R2 ou inferiores**: não suportado pelo instalador

Checklist e matriz detalhada em [requirements.md](requirements.md).

## Fluxos mais comuns

### Instalar no cliente

1. Validar ambiente em [requirements.md](requirements.md)
2. Executar os passos de [installation_guide.md](installation_guide.md)
3. Usar [install_monitor.bat](../../install_monitor.bat) apenas se houver
   necessidade de PlugPortMon

### Gerar instalador para release

1. Revisar versionamento em [release_guide.md](release_guide.md)
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
| [release_guide.md](release_guide.md)             | Versionamento, build, tag, publicação e pós-release  |
| [auto_update_setup.md](auto_update_setup.md)     | Feed oficial, appcast, smoke checks e testes         |

## Scripts úteis

| Script                                           | Uso                                                                            |
| ------------------------------------------------ | ------------------------------------------------------------------------------ |
| `python installer/build_installer.py`            | Fluxo recomendado: sincroniza versão, faz build Flutter e compila o Inno Setup |
| `python installer/update_version.py`             | Fluxo manual/avançado para sincronizar versão sem gerar instalador             |
| [install_monitor.bat](../../install_monitor.bat) | Instalar PlugPortMon como administrador                                        |
