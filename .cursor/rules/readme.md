# Cursor Rules - Guia de Uso

Este diretorio contem as regras do Cursor para manter consistencia no projeto.
Depois da consolidacao, as rules ficaram separadas em 3 grupos:

- universais
- Dart/Flutter
- especificas do repositorio

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

## Categorias

### 1. Universais

Essas regras podem ser reaproveitadas em qualquer stack:

- `general_rules.mdc`
- `clean_architecture.mdc`
- `solid_principles.mdc`
- `testing.mdc`

### 2. Dart/Flutter

Essas regras sao reutilizaveis apenas em projetos Dart/Flutter:

- `coding_style.mdc`
- `null_safety.mdc`
- `flutter_widgets.mdc`
- `ui_ux_design.mdc`
- `testing_dart_flutter.mdc`

### 3. Especificas do Projeto

Essas regras devem ser adaptadas para cada repositorio:

- `project_specifics.mdc`

## Fonte de Verdade por Tema

- comportamento geral e higiene de codigo: `general_rules.mdc`
- arquitetura em camadas: `clean_architecture.mdc`
- design de classes e interfaces: `solid_principles.mdc`
- testes universais: `testing.mdc`
- sintaxe/estilo Dart: `coding_style.mdc`
- Flutter e UI: `flutter_widgets.mdc` e `ui_ux_design.mdc`
- testes Dart/Flutter: `testing_dart_flutter.mdc`
- decisoes do repositorio: `project_specifics.mdc`

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

Ao adaptar `project_specifics.mdc`, ajuste:

1. Tipo de aplicacao
2. Arquitetura e estrutura de pastas
3. Dependencias obrigatorias
4. Regras de erro, runtime e integracoes
5. Contratos ou protocolos do projeto

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
- Prefira referencia cruzada curta em vez de copiar texto
- Mantenha `rules_index.mdc` sincronizado quando um arquivo mudar de escopo
