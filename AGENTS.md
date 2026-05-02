# Codex Entry Point

Este arquivo e um sumario operacional para IA neste repositorio.
Nao replique regras aqui. Use este arquivo apenas para descobrir onde esta a
fonte de verdade e qual arquivo consultar primeiro.

## Canonical Rules Location

As rules canonicas deste projeto ficam em:

- `./.cursor/rules/`
- `D:\Developer\plug_database\plug_agente\.cursor\rules`

Se houver qualquer divergencia entre este arquivo e o conteudo da pasta acima,
confie na pasta `./.cursor/rules`.

## Mandatory Reading Order

Ao entrar no repositorio, leia nesta ordem:

1. `./.cursor/rules/rules_index.mdc`
   Arquivo inicial obrigatorio. Define as categorias, a coordenacao entre
   temas e qual rule e dona de cada assunto.
2. `./.cursor/rules/project_specifics.mdc`
   Arquivo obrigatorio para qualquer mudanca real no projeto. Define
   arquitetura do repositorio, dependencias obrigatorias, transporte, falhas,
   persistencia, runtime desktop e convencoes locais.
3. `./.cursor/rules/readme.md`
   Contexto complementar sobre organizacao, reaproveitamento e manutencao do
   conjunto de rules.

Depois disso, leia apenas as rules do tema que a tarefa tocar.

## Topic Routing

Use `rules_index.mdc` para decidir a rule correta. Como atalho:

- comportamento geral, comentarios, duplicacao, refatoracao:
  `./.cursor/rules/general_rules.mdc`
- camadas, limites arquiteturais e direcao de imports:
  `./.cursor/rules/clean_architecture.mdc`
- SRP, DIP, contratos e design de classes/interfaces:
  `./.cursor/rules/solid_principles.mdc`
- estrategia de testes em qualquer stack:
  `./.cursor/rules/testing.mdc`
- estilo Dart, imports, async, logging e linguagem:
  `./.cursor/rules/coding_style.mdc`
- null safety e modelagem de nulabilidade:
  `./.cursor/rules/null_safety.mdc`
- widgets Flutter, composicao, estado local e performance de rebuild:
  `./.cursor/rules/flutter_widgets.mdc`
- desktop UX, Fluent UI, acessibilidade e comportamento responsivo:
  `./.cursor/rules/ui_ux_design.mdc`
- testes Dart/Flutter, widget tests, mocks, fakes e harness:
  `./.cursor/rules/testing_dart_flutter.mdc`
- decisoes especificas deste repositorio:
  `./.cursor/rules/project_specifics.mdc`

## Search Strategy For AI

Para pesquisar contexto da melhor forma:

1. Nao responda pelas regras "de memoria". Comece em `rules_index.mdc`.
2. Em mudancas de codigo, leia `project_specifics.mdc` antes de decidir
   arquitetura, dependencias, transporte, persistencia ou falhas.
3. Se a tarefa tocar mais de um tema, combine as rules pelos donos do assunto,
   sem copiar texto entre arquivos.
4. Quando houver conflito aparente:
   `rules_index.mdc` decide a coordenacao;
   `project_specifics.mdc` vence para decisoes especificas do repositorio.
5. Leia arquivos extras do repositorio apenas quando o proprio
   `project_specifics.mdc` mandar ou quando a tarefa exigir detalhes locais.

## High-Value Project Context

Este repositorio e um app Flutter desktop-first para Windows que intermedeia
um hub central e bancos locais via ODBC e Socket.IO.

Antes de mudar areas sensiveis, consulte tambem:

- transporte e contrato Socket.IO / Plug:
  `docs/communication/socket_communication_standard.md`
- transporte binario Socket.IO:
  `docs/communication/socketio_client_binary_transport.md`
- roadmap do protocolo:
  `docs/communication/socket_communication_roadmap.md`
- schemas e OpenRPC:
  `docs/communication/schemas/`
  e `docs/communication/openrpc.json`
- configuracao de testes E2E:
  `docs/testing/e2e_setup.md`
  e `test/helpers/e2e_env.dart`

## Usage Rules

- Nao reescreva o conteudo das rules neste arquivo
- Nao crie novas regras aqui; aponte para o arquivo correto em
  `./.cursor/rules`
- Nao invente convencoes que conflitem com `project_specifics.mdc`
- Se a estrutura das rules mudar, atualize primeiro
  `./.cursor/rules/rules_index.mdc` e depois este sumario
- O nome correto da pasta e `./.cursor/rules`, nunca `./.cursor/roles`
