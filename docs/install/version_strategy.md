# Estratégia de Versionamento - Plug Agente

Este documento define a estratégia de versionamento e o fluxo de releases do Plug Agente.

## Formato de Versão (SemVer)

Formato: **`MAJOR.MINOR.PATCH+BUILD`**

| Componente | Uso                                      | Exemplo    |
| ---------- | ---------------------------------------- | ---------- |
| **MAJOR**  | Mudanças incompatíveis, breaking changes | `2.0.0`    |
| **MINOR**  | Novas funcionalidades compatíveis        | `1.1.0`    |
| **PATCH**  | Correções de bugs, ajustes               | `1.0.1`    |
| **BUILD**  | Número de build (opcional, para CI)      | `1.0.0+42` |

## Onde a Versão é Definida

| Arquivo                                 | Propósito                                                  |
| --------------------------------------- | ---------------------------------------------------------- |
| `pubspec.yaml`                          | Fonte única da versão (campo `version`)                    |
| `installer/setup.iss`                   | Inno Setup (gerado por `update_version.py`)                |
| `lib/core/constants/app_version.g.dart` | Constante Dart (gerado por `update_version.py`)            |
| `.env`                                  | `AUTO_UPDATE_FEED_URL` (opcional, configurado manualmente) |

## Tags Git

- Padrão: **`v{VERSÃO}`** (ex.: `v1.0.0`, `v1.2.3`)
- O prefixo `v` é obrigatório para o workflow de appcast
- A versão na tag deve corresponder ao `pubspec.yaml` (sem o `+BUILD`)

## Fluxo de Release

Fluxo operacional detalhado em [release_guide.md](release_guide.md).

Resumo:

1. Atualizar `pubspec.yaml`
2. Sincronizar instalador (`installer/update_version.py`)
3. Build + instalador
4. Criar tag `v{versão}` e publicar release
5. Workflow atualiza `appcast.xml`

## Auto-Update via GitHub

- **Feed**: `appcast.xml` (formato Sparkle, sem assinatura DSA)
- **Hospedagem**: GitHub Raw ou GitHub Pages
- **Workflow**: `.github/workflows/update-appcast.yml` atualiza o feed automaticamente em cada release publicado
- **Assinatura**: não usada; o cliente confia em HTTPS e hosts GitHub permitidos.

## Scripts de Desenvolvimento (Python)

| Script                         | Uso                                                                                                                          |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `installer/update_version.py`  | Sincroniza versão em `setup.iss` e `app_version.g.dart` a partir do `pubspec.yaml`. **Execute antes de cada build/release.** |
| `installer/build_installer.py` | Executa `update_version.py`, build Flutter e compila Inno Setup                                                              |

O `update_version.py` lê a versão completa (ex.: `1.0.11+12`) do `pubspec.yaml` e atualiza:

- `installer/setup.iss`: `MyAppVersion` (versão curta, ex.: `1.0.11`)
- `lib/core/constants/app_version.g.dart`: constante `appVersion` (versão completa)

Preferência por scripts em Python para facilitar manutenção e portabilidade.
