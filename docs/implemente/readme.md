# Implemente

Planos vivos de implementacao. Cada plano e a **fonte de verdade** da feature
correspondente: os subdocs `acoes/` sao indices que apontam aqui.

| Arquivo | Quando consultar |
| --- | --- |
| [plano_acoes_agendadas_execucoes.md](plano_acoes_agendadas_execucoes.md) | Plano canonico de acoes agendadas e execucoes (`agent.action.*`): dominio, scheduler, runners, contrato remoto, threat model, riscos aceitos. |
| [plano_auto_update_evolution.md](plano_auto_update_evolution.md) | Plano de evolucao do auto-update silencioso (assinatura Ed25519, Authenticode, download resilience, rollback). |
| [acoes/](acoes/) | Subdocs por contexto da feature de acoes (entry-points para contrato remoto, UI, seguranca). |

## Convencao

- Linkar para secoes do plano canonico via **anchor** (`#secao`), nunca por
  numero de linha — o arquivo cresce e quebra referencias.
- Atualizar status oficial e backlog pos-MVP no proprio plano canonico antes
  de mergear feature relevante.
- Subdocs em `acoes/` nao podem duplicar regra canonica do repositorio
  (`.cursor/rules`, `docs/communication`).
