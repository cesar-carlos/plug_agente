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
2. (Opcional, recomendado) Executar o workflow manual **Release Preflight**
   para ensaiar build, signtool e helper sem criar commit/tag/release
3. Executar o workflow manual **Publish Windows Release** no GitHub Actions
4. Confirmar o workflow **Update Appcast on Release** (em release publicada,
   ele dispara duas execucoes; a segunda e que faz o deploy do Pages)
5. Validar o auto-update em [auto_update_setup.md](auto_update_setup.md)

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
- `python tool/release_preflight.py`: valida sincronizacao, tag, ferramentas
  no PATH, presenca do instalador, chave publica embutida (`--feed-public-key`)
  e Pages habilitado (`--check-pages`) antes da publicacao
- `python tool/validate_release.py`: valida GitHub Release e appcast local ou
  remoto
- `python tool/validate_launcher_status.py`: valida o JSON do
  `plug_update_helper.exe` contra o schema canonico
- `python tool/generate_appcast_signing_key.py`: gera keypair Ed25519 para o
  feed (privada vira `APPCAST_SIGNING_PRIVATE_KEY` em Secrets; publica vira
  `AUTO_UPDATE_FEED_PUBLIC_KEY` nos builds de release)
- `python tool/appcast_manager.py`: comandos `update` / `validate-file` /
  `smoke-validate-url` / `inspect-url` do feed (chamado pelos workflows)
- [install_monitor.bat](../../install_monitor.bat): instala PlugPortMon como
  administrador

## Validacoes de CI

- O workflow **Flutter CI** executa `actionlint` nos arquivos em
  `.github/workflows/`.
- O workflow **Publish Windows Release** tem modo `dry_run` para gerar o
  instalador e validar o fluxo sem criar commit, tag ou GitHub Release.
