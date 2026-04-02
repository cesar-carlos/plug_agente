# Guia para Criar Release

Checklist operacional para criação de release do Plug Agente: versão, build do
instalador, tag e publicação no GitHub.

## Formato de Tags

As tags seguem o padrão **`v{VERSÃO}`**:

- A versão vem do `pubspec.yaml` (campo `version`)
- O prefixo `v` é obrigatório
- Exemplo: versão `1.0.0` → tag `v1.0.0`

Detalhes de SemVer e responsabilidades dos arquivos ficam em
[version_strategy.md](version_strategy.md).

## Processo Recomendado

### 1. Atualizar versão

Edite `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

### 2. Gerar build Windows e instalador

```bash
python installer/build_installer.py
```

O script executa `update_version.py`, `flutter build windows --release` e
compila o Inno Setup. A saída será
`installer/dist/PlugAgente-Setup-1.0.0.exe`.

> O `build_installer.py` injeta automaticamente
> `--dart-define=AUTO_UPDATE_FEED_URL=...` usando o valor do `.env`.

### 3. Validar artefatos versionados

```bash
git add pubspec.yaml installer/setup.iss lib/core/constants/app_version.g.dart
git commit -m "chore: bump version to 1.0.0"
git push origin main
```

> `installer/setup.iss` e `lib/core/constants/app_version.g.dart` devem refletir
> a versão do `pubspec.yaml`.
> O CI valida essa sincronização; se houver divergência, o workflow falha em vez
> de corrigir `main` automaticamente.

### 4. Criar tag e enviar

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 5. Criar release no GitHub

1. Acesse: https://github.com/cesar-carlos/plug_agente/releases
2. Clique em **"Create a new release"**
3. Selecione a tag `v1.0.0`
4. Título: `Version 1.0.0`
5. Adicione descrição com as mudanças
6. Arraste o instalador (`PlugAgente-Setup-1.0.0.exe`) para upload
7. Marque **"Set as the latest release"**
8. Clique em **"Publish release"**

### 6. Verificar GitHub Actions

1. Acesse: https://github.com/cesar-carlos/plug_agente/actions
2. O workflow **"Update Appcast on Release"** executará automaticamente
3. Aguarde conclusão (1-2 minutos)
4. Confirme que o secret `DSA_PRIVATE_KEY` está configurado; sem ele, o
   workflow falha em qualquer tipo de release
5. O workflow também valida se `DSA_PRIVATE_KEY` corresponde ao `dsa_pub.pem`
   embutido no app

## Fluxo manual/avançado

Use apenas se precisar depurar o processo em etapas:

```bash
python installer/update_version.py
flutter build windows --release
ISCC installer/setup.iss
```

## Referências

- [version_strategy.md](version_strategy.md)
- [auto_update_setup.md](auto_update_setup.md)
- [testing_auto_update.md](testing_auto_update.md)
