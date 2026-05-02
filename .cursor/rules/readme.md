# Cursor Rules - Guia de Uso

Este diretorio contem as rules do Cursor para manter consistencia no projeto.

`rules_index.mdc` e a fonte de verdade para categorias, ownership por tema e
coordenacao entre arquivos.

Este `readme.md` existe para explicar manutencao, reaproveitamento e como
evitar duplicacao entre rules.

## Estrutura

```text
.cursor/rules/
|-- rules_index.mdc          # indice e fonte de verdade por categoria
|
|-- general_rules.mdc        # principios universais de colaboracao e higiene
|-- clean_architecture.mdc   # arquitetura em camadas
|-- solid_principles.mdc     # SRP, OCP, LSP, ISP, DIP
|-- testing.mdc              # estrategia universal de testes
|
|-- coding_style.mdc         # estilo Dart
|-- null_safety.mdc          # null safety no Dart
|-- flutter_widgets.mdc      # widgets Flutter
|-- ui_ux_design.mdc         # UX desktop para Flutter
|-- testing_dart_flutter.mdc # testes Dart/Flutter
|
`-- project_specifics.mdc    # regras especificas do plug_agente
```

## Como Usar

1. Leia primeiro `rules_index.mdc`
2. Leia `project_specifics.mdc` antes de mudar codigo real do repositorio
3. Leia apenas as rules tematicas que a tarefa tocar

Exemplo:

- arquitetura/imports: `clean_architecture.mdc`
- estilo Dart/tooling: `coding_style.mdc`
- widgets/layout/rebuild: `flutter_widgets.mdc`
- UX desktop/acessibilidade: `ui_ux_design.mdc`
- testes Dart/Flutter: `testing_dart_flutter.mdc`

## Como Manter Sem Duplicar

- Cada tema tem um unico arquivo dono definido em `rules_index.mdc`
- Nao replique a mesma regra em varios arquivos; deixe a regra completa apenas
  no arquivo dono
- Quando um tema tiver parte generica e parte local, mantenha a parte generica
  na rule tematica e deixe em `project_specifics.mdc` apenas o delta do
  `plug_agente`
- Prefira referencia cruzada curta em vez de copiar texto
- Se uma rule mudar de escopo, atualize primeiro `rules_index.mdc` e depois
  este `readme.md`

## Foco Atual destas Rules

Hoje este conjunto esta orientado a:

- aplicacao Flutter desktop-first para Windows
- Fluent UI como linguagem principal, com Material apenas em escopos isolados
- arquitetura em camadas globais com `core`, `shared` e suporte a `l10n`
- `Provider` para estado de apresentacao e `get_it` para DI
- `result_dart` e failures tipadas nas fronteiras
- protocolo Plug via Socket.IO, persistencia local e runtime desktop

## Reaproveitando em Outro Projeto

### Projeto de outra linguagem

Copie apenas:

- `rules_index.mdc`
- `general_rules.mdc`
- `clean_architecture.mdc`
- `solid_principles.mdc`
- `testing.mdc`

### Projeto Dart/Flutter

Copie:

- todas as rules universais
- `coding_style.mdc`
- `null_safety.mdc`
- `flutter_widgets.mdc`
- `ui_ux_design.mdc` se houver interface desktop
- `testing_dart_flutter.mdc`

### Sempre adaptar

- `project_specifics.mdc`
- `clean_architecture.mdc` quando a arquitetura do repositorio nao seguir o
  mesmo modelo de camadas

Ao adaptar `project_specifics.mdc`, ajuste:

1. Tipo de aplicacao
2. Arquitetura e estrutura de pastas
3. Dependencias obrigatorias
4. Regras de erro, runtime e integracoes
5. Contratos ou protocolos do projeto

Nao presuma que `clean_architecture.mdc` e intercambiavel entre repositorios.
Projetos com organizacao por feature, por camada global ou com fronteiras
hibridas precisam refletir isso explicitamente na rule.

## Ajustando Globs

Se a estrutura do projeto mudar, atualize o frontmatter:

```yaml
---
description: Descricao da regra
globs: ["lib/presentation/**/*.dart"]
alwaysApply: true
---
```

## Observacoes

- Nao duplique regra em mais de um arquivo
- `project_specifics.mdc` complementa as rules tematicas; ele nao substitui
  `clean_architecture.mdc`, `coding_style.mdc`, `flutter_widgets.mdc`,
  `ui_ux_design.mdc`, `testing.mdc` ou `testing_dart_flutter.mdc`
- Mantenha `rules_index.mdc` sincronizado quando um arquivo mudar de escopo
- Quando uma regra nova surgir, primeiro decida se ela e universal,
  Dart/Flutter ou especifica do repositorio
- Ao evoluir o projeto, prefira atualizar a rule existente dona do tema em vez
  de criar sobreposicoes
