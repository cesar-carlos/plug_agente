# Guia para Criar Release

Este guia consolida o processo completo de criação de releases do Plug Agente: versão, tags, build, instalador e publicação no GitHub.

## Versão Atual

A versão do projeto é definida em `pubspec.yaml` (ex.: `1.0.0`).

## Formato de Tags

As tags seguem o padrão **`v{VERSÃO}`**:

- A versão vem do `pubspec.yaml` (campo `version`)
- O prefixo `v` é obrigatório
- Exemplo: versão `1.0.0` → tag `v1.0.0`

## Processo Completo (Recomendado)

### 1. Atualizar Versão

Edite `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

### 2. Sincronizar Versão

```powershell
python installer/update_version.py
```

Este script atualiza `installer/setup.iss` e `lib/core/constants/app_version.g.dart`. O `build_installer.py` executa esse passo automaticamente.

### 3. Build e Instalador

```bash
python installer/build_installer.py
```

O script executa `update_version.py`, `flutter build windows --release` e compila o Inno Setup. O instalador será criado em `installer/dist/PlugAgente-Setup-1.0.0.exe`.

> O `build_installer.py` injeta automaticamente
> `--dart-define=AUTO_UPDATE_FEED_URL=...` usando o valor do `.env`.

### 4. Commit e Push

```bash
git add pubspec.yaml installer/setup.iss lib/core/constants/app_version.g.dart
git commit -m "chore: bump version to 1.0.0"
git push origin main
```

> O workflow `Sync Version on pubspec Change` pode atualizar automaticamente `setup.iss` e `app_version.g.dart` ao fazer push de alterações no `pubspec.yaml`.

### 5. Criar Tag e Enviar

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 6. Criar Release no GitHub

1. Acesse: https://github.com/cesar-carlos/plug_agente/releases
2. Clique em **"Create a new release"**
3. Selecione a tag `v1.0.0`
4. Título: `Version 1.0.0`
5. Adicione descrição com as mudanças
6. Arraste o instalador (`PlugAgente-Setup-1.0.0.exe`) para upload
7. Marque **"Set as the latest release"**
8. Clique em **"Publish release"**

### 7. Verificar GitHub Actions

1. Acesse: https://github.com/cesar-carlos/plug_agente/actions
2. O workflow **"Update Appcast on Release"** executará automaticamente
3. Aguarde conclusão (1-2 minutos)
4. Confirme que o secret `DSA_PRIVATE_KEY` está configurado; sem ele, o workflow falha em qualquer tipo de release.

## Estrutura de Versão

Formato: `MAJOR.MINOR.PATCH+BUILD`

| Parte | Uso                               |
| ----- | --------------------------------- |
| MAJOR | Mudanças incompatíveis            |
| MINOR | Novas funcionalidades compatíveis |
| PATCH | Correções de bugs                 |
| BUILD | Número de build (opcional)        |

Consulte [version_strategy.md](version_strategy.md) para detalhes.

## Scripts Relacionados

| Script                         | Propósito                                                     |
| ------------------------------ | ------------------------------------------------------------- |
| `installer/update_version.py`  | Sincroniza versão em setup.iss e app_version.g.dart           |
| `installer/build_installer.py` | Executa update_version.py, build Flutter e compila Inno Setup |

## Comandos Rápidos

```bash
python installer/update_version.py
git add pubspec.yaml installer/setup.iss lib/core/constants/app_version.g.dart
git commit -m "chore: bump version to 1.0.0"
git push origin main
git tag v1.0.0
git push origin v1.0.0
```

Depois, crie o release manualmente no GitHub e faça upload do instalador.
