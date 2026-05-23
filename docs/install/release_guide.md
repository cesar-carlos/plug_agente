# Guia de Release e Versionamento

Fonte operacional para versionamento, build do instalador, tag e publicacao do
Plug Agente.

## Versao e Tags

- A versao nasce em `pubspec.yaml`, no formato `MAJOR.MINOR.PATCH+BUILD`.
- `installer/update_version.py` sincroniza `installer/setup.iss` com a versao
  curta (`MAJOR.MINOR.PATCH`) e `lib/core/constants/app_version.g.dart` com a
  versao completa.
- Tags usam `v{MAJOR.MINOR.PATCH}`. Exemplo: `version: 1.2.6+1` exige tag
  `v1.2.6`.
- O CI falha se `pubspec.yaml`, `installer/setup.iss` e
  `lib/core/constants/app_version.g.dart` estiverem fora de sincronia.

## Processo Recomendado

O caminho preferencial e o workflow manual **Publish Windows Release** em
GitHub Actions. Ele atualiza a versao, valida sincronizacao, gera o instalador
Windows, cria commit/tag/release e anexa o asset correto.

1. Acesse `Actions` > `Publish Windows Release`.
2. Execute `Run workflow` em `main`.
3. Informe:
   - `version`: versao curta, exemplo `1.6.6`;
   - `build_number`: sufixo do `pubspec.yaml`, exemplo `1`;
   - `run_tests`: mantenha ativo para release estavel;
   - `require_signing`: ative apenas quando os secrets de assinatura estiverem
     configurados;
   - `prerelease`: use apenas para versoes de validacao;
   - `dry_run`: gera e valida o instalador sem criar commit, tag ou release.
4. Apos a publicacao, confirme que o workflow **Update Appcast on Release**
   terminou com sucesso.

Use `dry_run=true` para validar uma versao antes de publica-la. O workflow
continua atualizando a versao no workspace temporario do runner, rodando
preflight e gerando o instalador, mas encerra antes dos passos destrutivos.

Secrets opcionais para assinatura:

- `WINDOWS_CODE_SIGNING_CERT_BASE64`: certificado PFX em Base64.
- `WINDOWS_CODE_SIGNING_CERT_PASSWORD`: senha do PFX.

Quando `require_signing=true`, a release falha se o certificado nao estiver
disponivel. Quando `false`, a assinatura e aplicada apenas se os secrets
existirem.

## Processo Local Manual

### 1. Atualizar versao

Edite `pubspec.yaml`:

```yaml
version: 1.2.7+2
```

### 2. Gerar build Windows e instalador

```bash
python tool/release_preflight.py --version 1.2.7 --allow-dirty --require-iscc --check-pages
python installer/build_installer.py
```

O script executa:

1. `installer/update_version.py`
2. `flutter build windows --release`
3. `ISCC installer/setup.iss`

Quando `.env` define `AUTO_UPDATE_FEED_URL`, o build recebe
`--dart-define=AUTO_UPDATE_FEED_URL=...` como override. Sem essa variavel, o
app usa o feed oficial padrao embutido.

Saida esperada:

```text
installer/dist/PlugAgente-Setup-{MAJOR.MINOR.PATCH}.exe
```

### 3. Revisar e commitar artefatos versionados

```bash
git add pubspec.yaml installer/setup.iss lib/core/constants/app_version.g.dart
git commit -m "chore: bump version to 1.2.7"
git push origin main
```

Mantenha alteracoes de runtime/runner Windows em commit separado do bump de
versao. O commit de release deve conter apenas os artefatos versionados acima.

### 4. Criar tag

```bash
git tag v1.2.7
git push origin v1.2.7
```

### 5. Publicar release no GitHub

1. Acesse `https://github.com/cesar-carlos/plug_agente/releases`.
2. Crie uma release para a tag `v1.2.7`.
3. Use titulo como `Version 1.2.7`.
4. Anexe `installer/dist/PlugAgente-Setup-1.2.7.exe`.
5. Publique como latest release quando for a versao estavel mais recente.

### 6. Validar automacao

Apos publicar, confira o workflow **Update Appcast on Release** em GitHub
Actions. Ele valida tag, versao, nome do asset, atualiza `appcast.xml` e roda
o smoke check do feed publicado usando `tool/appcast_manager.py`.

Feed oficial:

```text
https://cesar-carlos.github.io/plug_agente/appcast.xml
```

Validacoes detalhadas do feed e do update ficam em
[auto_update_setup.md](auto_update_setup.md).

Validacao manual da release publicada:

```bash
python tool/validate_release.py \
  --tag v1.2.7 \
  --appcast appcast.xml
```

Para validar o feed remoto publicado:

```bash
python tool/validate_release.py \
  --tag v1.2.7 \
  --feed-url https://cesar-carlos.github.io/plug_agente/appcast.xml
```

## Fonte de Verdade do Appcast

O arquivo `tool/appcast_manager.py` concentra:

- geracao do item mais recente do `appcast.xml`;
- validacao estrutural do feed;
- smoke check do feed publicado;
- testes Python do fluxo de appcast.

Antes de mexer no workflow de update, atualize primeiro esse script e rode:

```bash
python -m unittest tool.test_appcast_manager -v
```

## Fluxo Manual para Depuracao

Use apenas quando precisar isolar uma etapa:

```bash
python installer/update_version.py
flutter build windows --release
ISCC installer/setup.iss
```

Preflight local completo antes de publicar manualmente:

```bash
python tool/release_preflight.py --version 1.2.7 --require-iscc --check-pages --analyze --tests
```

## Seguranca Operacional

- Para distribuicao ampla, priorize tambem assinatura de codigo do executavel e
  do instalador para reduzir alertas de SmartScreen e aumentar confianca no
  update.
- O script `installer/build_installer.py` assina `plug_agente.exe` e o
  instalador quando `WINDOWS_CODE_SIGNING_CERT_PATH` aponta para um PFX. Use
  `WINDOWS_CODE_SIGNING_REQUIRED=true` para falhar explicitamente quando a
  assinatura nao estiver configurada.
- A retencao do `appcast.xml` e limitada pelo workflow para evitar crescimento
  indefinido do feed.
- O feed oficial e publicado via GitHub Pages usando Actions artifact; habilite
  `Settings` > `Pages` > `GitHub Actions` uma vez no repositorio.
- O CI executa `actionlint` nos workflows para detectar problemas de sintaxe,
  expressoes e scripts inline antes de usar o fluxo de release.
