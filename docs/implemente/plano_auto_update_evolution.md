# Plano de Evolucao do Auto-Update

## Objetivo

Entregar atualizacao automatica por servico Windows, autorizada na primeira
instalacao, com encerramento seguro, recuperacao de binarios e dados locais e
revisao de requisitos a cada release. Preservar instalacao global, pasta
personalizada, atualizacao manual por usuario e contratos RPC existentes.

Este documento guarda apenas o que falta fazer e as decisoes pendentes. O
comportamento ja entregue esta descrito em
[auto_update_setup.md](../install/auto_update_setup.md) e a analise de
seguranca em [auto_update_threat_model.md](../security/auto_update_threat_model.md).

## Status oficial

**2026-10-04 — implementação do plano de serviço:** estado verificável:

| Etapa do novo plano | Estado verificável |
| --- | --- |
| Correções imediatas | Schema/gates, canal, deduplicação, reassinatura, asset exato, cache removido, relançamento legado e supervisão corrigidos; testes locais. |
| Contratos e confiança | Manifesto Python/Dart/C++ e fixture criptográfica comum; cliente valida binding, baixa manifesto por HTTPS com limite de 128 KiB e verifica hash/assinatura/identidade antes do download do setup. IPC/DACL/PID/SCM, consulta de capacidades e staging protegido implementados. Apply privilegiado permanece pendente. |
| Serviço e instalador | Binários compilados; autorização interativa/silenciosa e revogação implementadas; supervisor separado de workers por versão completa; SID e sessão ativa conferidos. Enrollment ainda não homologado em instalação real. |
| Manutenção segura | Filas SQL/ações congeláveis, coordenador reversível, checkpoint SQLite e testes. Falta admission de configuração, inspeção integrada de recursos nativos e conexão ao fluxo de apply. |
| Recuperação | Snapshot de segredos exato/DPAPI e checkpoint testados; worker experimental. Faltam launcher não elevado, probation/saúde autenticada, restauração no usuário original, retenção/reconciliação completas e migrações em rollback. |
| Homologação e entrega | Gates locais e build Windows disponíveis. VMs Windows 10/11/Server, 20 ciclos, certificado de teste/distribuição e rollout em campo ainda não executados. |

A aplicação pelo serviço é **bloqueada no código**, com
`kApplicationContractImplemented=false`, e na política com
`applicationContractValidated=false`. Enrollment não é homologação. O caminho
operacional do aplicativo ainda usa helper legado. Não afirmar atualização sem
UAC, rollback automático completo ou aprovação da matriz antes dos itens acima.
Não há novos métodos RPC do hub nesta mudança.

Validação da integração do manifesto: 4.774 testes Dart aprovados e 5 ignorados
na suíte completa, 62 testes Python de tooling, 46 testes afetados do feed/
manifesto e 26 de contrato/instalador após o ajuste de `recoveryRequired`.
Também passaram 47 testes Python de scripts, os dois alvos CTest e o
`actionlint` dos quatro workflows alterados. Logs locais em `build/updater`.
`recoveryRequired` exige atenção, sem provar término do setup ou liberar ownership.
`dart analyze` sem diagnósticos; build Windows e empacotamento Inno com payload
compilados localmente. O setup gerado em `build/installer-payload` é **unsigned de
desenvolvimento**, não foi executado nem distribuído. Testes locais não comprovam
instalação real, ausência de UAC ou rollback entre schemas em máquinas cliente/Server.

O protocolo nativo não permite novo prepare sobre fases ativas, desconhecidas ou
de recuperação, mesmo se o worker já tiver terminado. Revogação mantém status,
cancelamento seguro e confirmação de saúde acessíveis; não autoriza novo start. Fontes e baseline são fixados
por handles durante validação/cópia; worker ativo nunca é substituído pelo setup.

Bloqueios externos observados: módulo Hyper-V presente, mas `Get-VM` negou
acesso ao processo atual; nenhum certificado de code signing encontrado nos
stores `CurrentUser/My` e `LocalMachine/My`, nem PFX configurado para build local.
Acesso às VMs e certificado adequado continuam necessários. As integrações
pendentes acima são trabalho de implementação, separadas desses bloqueios.

## Trabalho restante

### Servico, autorizacao e sessao

- Integrar o apply privilegiado sem liberar os gates de seguranca antes de
  cumprir o contrato completo. Preservar `IAutoUpdateOrchestrator` como fachada.
- Completar launcher fora do bundle, nao elevado, na sessao e conta originais,
  com uma unica instancia. Sem sessao apta, preparar download e adiar apply.
- Completar aprovacao administrativa de requisitos adicionais e alteracoes do
  host; comparar politica antes da manutencao e antes da instalacao. Preferencias
  do app nao autorizam ampliacao de servicos, drivers, firewall, DSNs ou destinos.
- Homologar enrollment, revogacao, desinstalacao e migracao das instalacoes
  existentes. Baseline sem assinatura e recuperacao impede modo automatico.

### Manutencao e supervisao

- Conectar o coordenador reversivel ao fluxo real: suspender admissao SQL,
  acoes e configuracao; inspecionar operacoes, recursos nativos e resultado
  incerto antes de confirmar cleanup e persistencia.
- Aguardar ate 60 segundos; se nao houver encerramento seguro, restaurar
  admissao e adiar por 15 minutos sem contabilizar falha de instalacao.
- Aplicar quiet hours e cooldown a pending e shutdown. A acao manual pode
  ignorar essas janelas, mas continua exigindo integridade, autorizacao e drain.
- Executar politicas de saida uma vez por tentativa, antes do snapshot.
  Nao repetir seus efeitos durante recuperacao.
- Reconciliar setup real apos 30 minutos, interrupcao do servico e reboot.
  `recoveryRequired` nao libera lock, recursos ou nova instalacao.

### Snapshot, validacao e rollback

- Integrar snapshot exato do bundle, worker, instalador anterior validado,
  configuracoes, SQLite e segredos do agente no usuario original. Usar
  checkpoint confirmado ou API de backup SQLite para preservar efeitos do WAL.
- Validar hashes, schema, espaco e completude; backup incompleto bloqueia apply.
  Reter dois snapshots confirmados sem remover o da tentativa ativa.
- Integrar bootstrap em validacao, sem SQL remoto, acoes, startup triggers ou
  efeitos externos. Confirmar saude autenticada em ate 120 segundos, incluindo
  versao, processo, SQLite, configuracoes e componentes locais necessarios.
  Hub ou banco remoto indisponivel nao determina rollback por si so.
- Completar restauracao de binarios, schema e segredos DPAPI na conta original,
  preservando outros namespaces, politica administrativa, logs e efeitos externos.
- Permitir uma restauracao automatica por tentativa; apos rollback, bloquear
  o mesmo manifesto ate nova release ou acao administrativa. Falha de
  restauracao preserva evidencias e exige `recoveryRequired`.

### Observabilidade e publicacao

- Integrar diagnosticos de fase, autorizacao, adiamento, setup, saude e rollback
  ao collector existente; testar duracoes, falhas de telemetria e redacao.
  IDs sao correlacao de logs, sem labels de metricas de alta cardinalidade.
- Usar os secrets existentes para assinar feed e manifesto. Exigir Authenticode
  em todos os executaveis proprios e setup, identidade de publicador autorizada
  e rotacao testada. Falta de assinatura bloqueia producao.
- Validar publicacao atomica, chamada reutilizavel, canal stable/beta, asset exato,
  vinculo ao commit publicado e smoke criptografico. Nao introduzir novos RPCs
  do hub para executar este plano.

## Homologacao e criterios de conclusao

- Executar matriz em VMs descartaveis Windows 10/11 e Server suportado, com
  administrador e usuario padrao: instalacao nova/upgrade/silenciosa/manual,
  credenciais administrativas distintas, pasta personalizada e desinstalacao.
- Cobrir ACL/assinatura/publicador invalidos, reparse points, substituicao de
  arquivos, IPC remoto, replay, requisitos novos, cancelamento e revogacao.
- Cobrir SQL/acoes/transacoes ativos, recurso pendente e resultado incerto;
  logout/RDP/ausencia de sessao; setup travado; interrupcao em cada fase/reboot;
  falta de espaco; snapshot invalido; falha de boot e de rollback.
- Executar migracoes SQLite/WAL e restauracao exata de configuracoes/segredos,
  sem efeitos externos no modo de validacao, e 20 ciclos de update sem crescimento
  de processos, locks ou handles. Testes ignorados nao aprovam a matriz.
- Publicar primeiro a transicao assinada; promover em 5%, 25% e 100%, com pelo
  menos 48 horas de observacao por etapa. Integridade, permissoes, perda de dados,
  relancamento elevado ou rollback incorreto interrompem a promocao.
- Concluir somente com updates comuns sem UAC/confirmacao, novas permissoes
  bloqueadas ate aprovacao, rollback de schema testado e feed validado.
  Entregar evidencias e procedimentos de revogacao e recuperacao para o ultimo
  build homologado. Nao desabilitar validacao de assinatura como recuperacao.

## Referencias cruzadas

- Operacao: [auto_update_setup.md](../install/auto_update_setup.md).
- Instalacao: [installation_guide.md](../install/installation_guide.md).
- Publicacao: [release_guide.md](../install/release_guide.md).
- Seguranca: [auto_update_threat_model.md](../security/auto_update_threat_model.md).
