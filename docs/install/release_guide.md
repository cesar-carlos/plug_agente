# Guia de Release e Versionamento

Fonte operacional para versionamento, build do instalador, tag e publicação do
Plug Agente.

## Versão e Tags

- A versão nasce em `pubspec.yaml`, no formato `MAJOR.MINOR.PATCH+BUILD`.
- `installer/update_version.py` sincroniza `installer/setup.iss` com a versão
  curta (`MAJOR.MINOR.PATCH`) e `lib/core/constants/app_version.g.dart` com a
  versão completa.
- Tags usam `v{MAJOR.MINOR.PATCH}`. Exemplo: `version: 1.2.6+1` exige tag
  `v1.2.6`.
- O CI falha se `pubspec.yaml`, `installer/setup.iss` e
  `lib/core/constants/app_version.g.dart` estiverem fora de sincronia.

## Processo Recomendado

### 1. Atualizar versão

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
`--dart-define=AUTO_UPDATE_FEED_URL=...`.

Saída esperada:

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
3. Use título como `Version 1.2.7`.
4. Anexe `installer/dist/PlugAgente-Setup-1.2.7.exe`.
5. Publique como latest release quando for a versão estável mais recente.

### 6. Validar automação

Após publicar, confira o workflow **Update Appcast on Release** em GitHub
Actions. Ele valida tag, versão, nome do asset e atualiza `appcast.xml`.

Feed oficial:

```text
https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

Validações detalhadas do feed e do update ficam em
[auto_update_setup.md](auto_update_setup.md).

## Fluxo Manual para Depuração

Use apenas quando precisar isolar uma etapa:

```bash
python installer/update_version.py
flutter build windows --release
ISCC installer/setup.iss
```

## Segurança Operacional

- O fluxo atual publica `appcast.xml` sem `sparkle:dsaSignature`.
- Para distribuição ampla, priorize assinatura de código do executável e do
  instalador para reduzir alertas de SmartScreen e aumentar confiança no update.
- A retenção do `appcast.xml` é limitada pelo workflow para evitar crescimento
  indefinido do feed.
