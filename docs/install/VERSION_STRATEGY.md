# Estratégia de Versionamento - Plug Agente

Este documento define a estratégia de versionamento e o fluxo de releases do Plug Agente.

## Formato de Versão (SemVer)

Formato: **`MAJOR.MINOR.PATCH+BUILD`**

| Componente | Uso | Exemplo |
|------------|-----|---------|
| **MAJOR** | Mudanças incompatíveis, breaking changes | `2.0.0` |
| **MINOR** | Novas funcionalidades compatíveis | `1.1.0` |
| **PATCH** | Correções de bugs, ajustes | `1.0.1` |
| **BUILD** | Número de build (opcional, para CI) | `1.0.0+42` |

## Onde a Versão é Definida

| Arquivo | Propósito |
|---------|-----------|
| `pubspec.yaml` | Fonte única da versão (campo `version`) |
| `installer/setup.iss` | Inno Setup (gerado por `update_version.py`) |
| `.env` | `AUTO_UPDATE_FEED_URL` (opcional, gerado por `update_version.py`) |

## Tags Git

- Padrão: **`v{VERSÃO}`** (ex.: `v1.0.0`, `v1.2.3`)
- O prefixo `v` é obrigatório para o workflow de appcast
- A versão na tag deve corresponder ao `pubspec.yaml` (sem o `+BUILD`)

## Fluxo de Release

```
1. Atualizar pubspec.yaml (version: 1.0.1+2)
2. python installer/update_version.py
3. flutter build windows --release
4. python installer/build_installer.py
5. git add, commit, push
6. git tag v1.0.1 && git push origin v1.0.1
7. Criar release no GitHub com o instalador
8. GitHub Actions atualiza appcast.xml
```

## Auto-Update via GitHub

- **Feed**: `appcast.xml` (formato Sparkle/WinSparkle)
- **Hospedagem**: GitHub Raw ou GitHub Pages
- **Workflow**: `.github/workflows/update-appcast.yml` atualiza o feed automaticamente em cada release publicado

## Scripts de Desenvolvimento (Python)

| Script | Uso |
|--------|-----|
| `installer/update_version.py` | Sincroniza versão em setup.iss e .env |
| `installer/build_installer.py` | Build Flutter + compila Inno Setup |

Preferência por scripts em Python para facilitar manutenção e portabilidade.
