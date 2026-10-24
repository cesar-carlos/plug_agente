# Implemente

Implementation plans own feature status, backlog and acceptance evidence.
Wire contracts remain in [communication](../communication/readme.md); repository
rules remain in [.cursor/rules](../../.cursor/rules/rules_index.mdc).
The action subdocuments provide focused UI and operational guidance and link
to the plan for status; they are not interchangeable copies of it.

| Arquivo | Quando consultar |
| --- | --- |
| [plano_acoes_agendadas_execucoes.md](plano_acoes_agendadas_execucoes.md) | Plano vivo de acoes: status, backlog RA, threat baseline e riscos. |
| [plano_auto_update_evolution.md](plano_auto_update_evolution.md) | Plano vigente do servico de atualizacao: autorizacao, manutencao segura, recuperacao e homologacao pendentes. |
| [acoes/](acoes/) | Entry-points (contrato remoto, UI, seguranca) — sem duplicar wire. |

## Convencao

- Linkar para secoes do plano canonico via **anchor** (`#secao`), nunca por
  numero de linha — o arquivo cresce e quebra referencias.
- Atualizar status oficial e backlog pos-MVP no proprio plano canonico antes
  de mergear feature relevante.
- Subdocs em `acoes/` nao podem duplicar regra canonica do repositorio
  (`.cursor/rules`, `docs/communication`).
