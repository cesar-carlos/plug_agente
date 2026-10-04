# Ponto de Entrada do Agente

Este arquivo e o ponto de entrada para agentes de codigo neste repositorio.

## Fonte de Verdade

As regras canonicas ficam em [`.cursor/rules/`](.cursor/rules/).

1. [`.cursor/rules/rules_index.mdc`](.cursor/rules/rules_index.mdc) e o indice autoritativo. Ele lista cada arquivo e define qual e o dono de cada tema. Comece por aqui.
2. [`.cursor/rules/project_specifics.mdc`](.cursor/rules/project_specifics.mdc) guarda as decisoes deste repositorio: pacotes obrigatorios, contrato de transporte Plug, failures tipadas, runtime desktop, persistencia, localizacao e ambiente de teste. Leia antes de mudar arquitetura, dependencias, transporte, persistencia, runtime, failures ou testes.
3. [`.cursor/rules/readme.md`](.cursor/rules/readme.md) explica como o conjunto e mantido e como reaproveita-lo em outro projeto.

Carregue somente a rule tematica dona da tarefa. Se este arquivo e o indice divergirem, siga `rules_index.mdc`.

## Uso

- Nao copie o texto das rules para este arquivo. Mantenha a regra completa no arquivo dono e referencie-o.
- Quando os temas se sobrepoem, siga o ownership definido em `rules_index.mdc`.
- Em trabalho so de teste, leia `project_specifics.mdc` mesmo assim.
