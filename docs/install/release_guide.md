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

### 1. Atualizar versao

Edite `pubspec.yaml`:

```yaml
version: 1.2.7+2
```

### 2. Gerar build Windows e instalador

```bash
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
https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

Validacoes detalhadas do feed e do update ficam em
[auto_update_setup.md](auto_update_setup.md).

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

## Seguranca Operacional

- Para distribuicao ampla, priorize tambem assinatura de codigo do executavel e
  do instalador para reduzir alertas de SmartScreen e aumentar confianca no
  update.
- A retencao do `appcast.xml` e limitada pelo workflow para evitar crescimento
  indefinido do feed.
