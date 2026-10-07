# Plano de Evolucao do Auto-Update

## Estado atual — 2026-10-07

A implementação das cinco etapas de correção está integrada. A homologação do
fluxo privilegiado continua pendente. Esta seção substitui as pendências de
implementação registradas nas revisões históricas de 04 e 06 de outubro.
`kApplicationContractImplemented=false` e `applicationContractValidated=false`
permanecem desabilitados; nenhuma destas evidências autoriza sua ativação.

| Etapa | Implementação e evidência local |
| --- | --- |
| 1. Contrato e compatibilidade | Pending `windowsService` independente do helper, com identidade, versão, datas e intenção de cancelamento; registros antigos exigem nova preparação. IPC aditivo com contrato de recuperação e comando restrito ao aplicativo registrado. Testes de parsing, compatibilidade, persistência e proprietário. |
| 2. Manutenção e falha de despacho | Admissão na aplicação para SQL, ações, configurações, sessões, credenciais e caches; bloqueio da interface; pausa dos purges, gatilhos, renovação de token e retry periódico. Efeitos de saída autorizados por operação, uma vez; segredos capturados depois dos efeitos e antes de fechar recursos. Falha de `start` consulta o serviço, sem segundo despacho; rejeição confirmada solicita reinício e resultado desconhecido consulta a cada 15 segundos por cinco minutos, preservando recuperação manual. Teste integrado com SQLite real, pending persistido, coordenador de manutenção e adaptador IPC. |
| 3. Finalização resistente a interrupções | Resultado da atualização separado da finalização; reconciliação de estados terminais, guarda vinculada à operação e identidade do relançamento gravada enquanto suspenso. Sessão indisponível preserva finalização pendente. Finalização comum a conclusão, rollback e reinício de recuperação; processo criado e perdido exige recuperação explícita. CTest interrompe sete checkpoints usando journal em disco e processos reais suspensos. |
| 4. Cancelamento, expiração e limpeza | Coordenador compartilhado persiste intenção antes do IPC, confirma cancelamento antes de remover pending, reconcilia preparações órfãs do mesmo proprietário e preserva operações ativas ou desconhecidas. Cancelamento idempotente; limpeza nativa apenas de preparação cancelada e inativa. Adiamento/cancelamento não contabilizam falha de instalação. Teste lê a intenção em disco durante o IPC e cobre resposta perdida, expiração e proprietário distinto. |
| 5. Reinstalação, reparo e supervisor | `PrepareToInstall` usa o cliente extraído do próprio instalador; política residual passa por validação de ACL/journal/identidade. Cliente ausente pode ser reparado; supervisor incompatível exige transição administrativa explícita `/UPGRADEUPDATERHOST=1`, revogação, confirmação de inatividade, parada, substituição, enrollment e reinício. Falha mantém autorização desligada e diagnóstico. Fixtures Pascal executam o mesmo helper de preparação usado pelo instalador. |

Reinício de recuperação não instala, migra ou restaura dados. O serviço valida
SID, sessão, PID e criação do processo, espera o original terminar e permite uma
tentativa por operação. Cooldown durável impede reaplicação imediata da mesma
versão. Após fechar recursos, o aplicativo não reabre SQLite/pool no processo
original; shutdown não repete efeitos de saída confirmados.

Ed25519, SHA-256, ACLs, identidade IPC e autorização administrativa foram
preservados. Authenticode continua dependente do provedor configurado. Instalação
manual e contratos RPC do hub permanecem compatíveis.

### Evidências de execução

- Suíte Flutter/Dart do CI (`--exclude-tags "live || slow || perf"`): 4.851 testes aprovados e 5 ignorados; `build/update-full-tests-final.log`. Os skips não homologam recursos externos.
- Regressões dos writers: 72 testes aprovados; `build/update-writer-regressions.log`.
- Regressões finais de ciclo de vida: 98 testes aprovados; `build/update-lifecycle-regressions-final.log`. Incluem o scheduler real após restauração da manutenção, binding do provider e ausência de repetição dos efeitos no shutdown.
- Python/Inno: 45 testes aprovados, incluindo fixtures Pascal compiladas e executadas; `build/update-python-final.log`.
- C++: build Release e 3/3 testes CTest aprovados, incluindo manifesto criptográfico e interrupções da finalização; `build/update-native-final.log`.
- Análise estática Flutter/Dart: sem diagnósticos; `build/update-analyze-final.log`.
- Sintaxe Inno Setup: `ISCC /DCOMPILE_SCRIPT_ONLY` aprovado; `build/update-inno-syntax-final.log`.
- Build Windows Release: compilação local com Ed25519 obrigatório e chave pública de fixture; `build/update-windows-build-final.log`. O payload não foi instalado, assinado para distribuição ou publicado.

Os testes de aplicação usam transportes controlados para IPC; os testes nativos
locais não executam enrollment nem instalação como serviço SYSTEM. O build de
validação usa a chave pública da fixture e não é um artefato de distribuição.

## Histórico — revisão de 2026-10-06: serviço sem certificado comercial

Decisão: atualizações comuns devem ocorrer sem intervenção após a primeira
instalação global autorizada. Authenticode deixa de ser requisito no provedor
`manifest`; Ed25519 do feed/manifesto, SHA-256, ACLs, identidade IPC, versão e
permissões registradas continuam obrigatórios. A recusa da SignPath não bloqueia
esse provedor. As exigências de certificado nas seções históricas abaixo se
aplicam somente a `pfx`/`signpath`.

Implementado nesta revisão, ainda sem homologação de instalação real:

- Build `--manifest-only` e publicação `signing_provider=manifest`, com chaves
  obrigatórias e política nativa consistente com o Dart.
- Enrollment administrativo registra hashes do app, supervisor, cliente, worker
  e baseline. Políticas antigas continuam exigindo Authenticode por padrão.
- Adaptador Windows prepara e inicia pelo serviço, sem fallback com UAC.
- Launcher nativo cria processo suspenso no usuário original, verifica token
  não elevado e registra identidade antes de executar.
- Bootstrap isolado `--update-validation` verifica assets, versão, SQLite e
  acesso aos segredos sem DI normal, hub ou gatilhos de startup. Restauração
  DPAPI e confirmação de saúde usam operação, nonce, PID e criação do processo.
- Guarda de boot durante a troca; recuperação supervisionada aguarda o mesmo
  usuário e o término comprovado do setup, preservando snapshot e política.
- Retenção dos dois snapshots de operações confirmadas mais recentes; tentativas
  ativas ou sem confirmação não são removidas.

**Estado histórico, substituído pela implementação de 2026-10-07:** a revisão
identificou pendências de admissão, gatilhos internos, recuperação após falha de
despacho e cancelamento/reconciliação. Essas pendências foram implementadas nas
cinco etapas acima; os controles de ativação continuam desabilitados por falta
de homologação, não por dependência do helper legado.

O usuário informou não possuir VM descartável. Esta sessão não é administrativa.
Não foram executados enrollment/upgrade/rollback reais, reboot durante instalação
ou matriz de Windows/Server. Não habilitar os gates nem anunciar ausência de UAC
homologada somente com testes unitários e compilação. Instalação manual continua
separada desse bloqueio. Nenhum commit, push ou release foi feito nesta revisão.

Validação local desta revisão: suíte de CI com 4.819 testes aprovados e 5 skips;
38 testes direcionados após ajustes finais (incluindo nova identidade de processo
na validação); ferramentas Python do updater, release e feed aprovadas; análise
Dart sem diagnósticos; actionlint dos três workflows e sintaxe Inno aprovados.
Build Windows Release sem Authenticode compilado com chaves públicas e exigência
Ed25519. Build nativo independente no modo manifest passou os dois testes CTest,
incluindo vetor criptográfico compartilhado com Dart/Python. O executável gerado
não foi instalado nem publicado; compilação não comprova execução privilegiada.



## Objetivo

Entregar atualizacao automatica por servico Windows, autorizada na primeira
instalacao, com encerramento seguro, recuperacao de binarios e dados locais e
revisao de requisitos a cada release. Preservar instalacao global, pasta
personalizada, atualizacao manual por usuario e contratos RPC existentes.

Este documento guarda o estado atual, as evidências e as decisões históricas. O
comportamento ja entregue esta descrito em
[auto_update_setup.md](../install/auto_update_setup.md) e a analise de
seguranca em [auto_update_threat_model.md](../security/auto_update_threat_model.md).

## Histórico — estado em 2026-10-04

**2026-10-04 — implementação do plano de serviço:** estado verificável:

| Etapa do novo plano | Estado verificável |
| --- | --- |
| Correções imediatas | Schema/gates, canal, deduplicação, reassinatura, asset exato, cache removido, relançamento legado e supervisão corrigidos; testes locais. |
| Contratos e confiança | Manifesto Python/Dart/C++ e fixture criptográfica comum; cliente valida binding, baixa manifesto por HTTPS com limite de 128 KiB e verifica hash/assinatura/identidade antes do download do setup. IPC/DACL/PID/SCM, consulta de capacidades e staging protegido implementados. Naquela data, o apply privilegiado ainda estava pendente. |
| Serviço e instalador | Binários compilados; autorização interativa/silenciosa e revogação implementadas; supervisor separado de workers por versão completa; SID e sessão ativa conferidos. Enrollment ainda não homologado em instalação real. |
| Manutenção segura | Filas SQL/ações congeláveis, coordenador reversível, checkpoint SQLite e testes. Naquela data faltavam admissão de configuração, inspeção integrada de recursos nativos e conexão ao apply. |
| Recuperação | Snapshot de segredos exato/DPAPI e checkpoint testados; worker experimental. Naquela data faltavam launcher não elevado, saúde autenticada, restauração no usuário original, retenção/reconciliação completas e migrações em rollback. |
| Homologação e entrega | Gates locais e build Windows disponíveis. VMs Windows 10/11/Server, 20 ciclos, certificado de teste/distribuição e rollout em campo ainda não executados. |

A aplicação pelo serviço é **bloqueada no código**, com
`kApplicationContractImplemented=false`, e na política com
`applicationContractValidated=false`. Enrollment não é homologação. Naquela revisão, o caminho
operacional do aplicativo ainda usava o helper legado. Não afirmar atualização sem
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
Acesso a ambiente descartável administrativo continua necessário; certificado
é necessário apenas para os provedores Authenticode opcionais. As integrações que estavam
pendentes nessa data foram tratadas posteriormente; o estado atual é o registro
de 2026-10-07 no início deste documento.

## Trabalho restante — homologação e liberação

- Homologar enrollment, revogação, atualização, rollback, desinstalação seguida
  de reinstalação, reparo sem cliente e transição de supervisor antigo em Windows
  descartável, com usuário padrão e administrador distinto.
- Executar a matriz abaixo, incluindo falha de despacho/resposta perdida,
  recuperação sem reinstalação, manutenção sem gravações, cancelamento
  interrompido, pending perdido, logout, reboot e interrupções da finalização.
- Executar 20 ciclos medindo instâncias, handles e retenção de snapshots;
  verificar restauração de binários, SQLite/schema e segredos na conta original.
- Depois da homologação, preparar a transição administrativa e a liberação
  gradual de 5%, 25% e 100%, com evidências e procedimentos de recuperação.
  Ativar os dois controles somente mediante aprovação dessa homologação.
- Commit, publicação, distribuição e execução de instaladores reais não fazem
  parte desta execução. A ausência de ambiente descartável impede declarar o
  fluxo aprovado; não impede concluir as correções de implementação.

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
- Concluir a homologação somente com updates comuns sem UAC/confirmacao, novas permissoes
  bloqueadas ate aprovacao, rollback de schema testado e feed validado.
  Entregar evidencias e procedimentos de revogacao e recuperacao para o ultimo
  build homologado. Nao desabilitar validacao de assinatura como recuperacao.

## Referencias cruzadas

- Operacao: [auto_update_setup.md](../install/auto_update_setup.md).
- Instalacao: [installation_guide.md](../install/installation_guide.md).
- Publicacao: [release_guide.md](../install/release_guide.md).
- Seguranca: [auto_update_threat_model.md](../security/auto_update_threat_model.md).
