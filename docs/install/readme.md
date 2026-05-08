# Instalacao - Plug Agente

Indice canonico da documentacao de instalacao, empacotamento Windows e
atualizacao automatica.

## Compatibilidade

- **Windows 10/11**: suporte completo
- **Windows Server 2016+**: suporte com possiveis recursos degradados
- **Windows 8/8.1 e Windows Server 2012/2012 R2 ou inferiores**: nao suportado
  pelo instalador

Checklist e matriz detalhada em [requirements.md](requirements.md).

## Fluxos mais comuns

### Instalar no cliente

1. Validar ambiente em [requirements.md](requirements.md)
2. Executar [installation_guide.md](installation_guide.md)
3. Usar [install_monitor.bat](../../install_monitor.bat) apenas se houver
   necessidade de PlugPortMon

### Gerar instalador e publicar release

1. Revisar versionamento em [release_guide.md](release_guide.md)
2. Executar `python installer/build_installer.py`
3. Publicar a release no GitHub
4. Validar o auto-update em [auto_update_setup.md](auto_update_setup.md)

Saida esperada:

```text
installer/dist/PlugAgente-Setup-{versao}.exe
```

## Documentos operacionais

- [installation_guide.md](installation_guide.md): instalacao, desinstalacao e
  validacao basica no Windows
- [requirements.md](requirements.md): pre-requisitos, compatibilidade e notas
  opcionais de ODBC/PATH
- [release_guide.md](release_guide.md): versionamento, build, tag, release e
  pos-release
- [auto_update_setup.md](auto_update_setup.md): feed oficial, appcast, smoke
  checks, diagnostico e testes

## Scripts uteis

- `python installer/build_installer.py`: fluxo recomendado de build Windows
- `python installer/update_version.py`: sincroniza versao sem gerar instalador
- [install_monitor.bat](../../install_monitor.bat): instala PlugPortMon como
  administrador
