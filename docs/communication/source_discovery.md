> Escopo vigente: PostgreSQL, SQL Server e SQL Anywhere. Firebird removido do suporte por decisão do produto. Evidências históricas não homologam o novo candidato; produção permanece bloqueada.

# Identidade física e dialeto por hub/agente

Toda comunicação com bases de negócio segue **MCP → plug_server → plug_agente →
banco**. O MCP abre apenas seu banco de controle. Não recebe DSN, host, porta ou
credenciais do GDBR. A conexão ODBC e os SELECTs de metadados pertencem ao agente.

O contrato aditivo de desenvolvimento do hub 1.6.0 inclui `sql.describeSource` v1
em `POST /api/v1/agents/commands`. Ainda não foi publicado; não pressupor esse RPC
na instalação pública. A extensão `sourceDiscovery: 1` deve ser negociada na
sessão autenticada do agente, revalidada antes do envio. Agentes antigos são
recusados para cadastro/execução v2, sem fallback para o dialeto informado pela IA.

Entrada: `contractVersion: 1`, `database` obrigatório e `client_token` técnico da
fonte. JWT Client e ClientAgentAccess continuam obrigatórios no hub. O agente
confere token vigente, vínculo ao agentId e banco obrigatório da policy; revalida
token e configuração após a descoberta. Não há SQL fornecido pelo consumidor,
consulta de dados de negócio, DML, DDL ou concessão implícita de leitura.

Saída estrita: `contractVersion`, `database`, `dialect`, `identityHash`,
`identityKind`, `engineVersion`, `verifiedAt`. O motor vem dos metadados DBMS da
conexão, não do nome do driver configurado. Dialeto desconhecido é recusado.

| Motor        | Metadados fixos na conexão real                                       | Estado                                         |
| ------------ | --------------------------------------------------------------------- | ---------------------------------------------- |
| PostgreSQL   | current_database, system_identifier de pg_control_system, OID da base | native; requer acesso aos metadados            |
| SQL Server   | DB_NAME, MachineName/ServerName, database_guid/recovery_fork_guid     | native; metadados incompletos são recusados    |
| Firebird 4+ (historical; unsupported) | MON$DATABASE_NAME, MON$GUID, MON$FILE_ID                              | native; motores sem esses campos são recusados |
| SQL Anywhere | DB_NAME, UUID/version de DBA.se7e_source_identity                     | provisioned; exige provisionamento DBA manual |

O hash SHA-256 combina versão, motor, endpoint da configuração e identificadores
nativos ou UUID provisionado. Metadados brutos de caminhos/servidor não saem do agente. O nome é
conferido exatamente; somente caminhos Windows absolutos do Firebird permitem
normalizar caixa/separador. Credenciais não entram no hash. Nome e caminho não
constituem uma identidade durável no SQL Anywhere; não usar propriedade reservada
como garantia. A exceção DV2-007 admite UUID provisionado pelo DBA, com os
limites abaixo; não estabelece uma identidade nativa desse motor.

No cadastro, o MCP compara banco/dialeto e exige `identityKind: native`, exceto
`provisioned` exclusivamente no SQL Anywhere. `locator` é sempre recusado. Persiste
hash e horário de confirmação. A chave física interna combina origem do hub com
hash admitido, permitindo vínculos entre personas sem compartilhar credenciais,
treino ou resultados. Aliases de endpoint diferentes podem gerar chaves distintas;
não se promete reconhecimento universal de todas as rotas até a mesma base.

Consultas verificam novamente a prova antes do dispatch e da entrega; operações
verificam antes da preparação/execução. Prova válida incompatível desativa os
vínculos conhecidos dessa identidade física, incrementa autorização/revisão de
cache e suspende publicações locais e dependências transitivas. A mutação local
é transacional, com personas bloqueadas em ordem estável. Não reassociar
automaticamente a base nova ao treino antigo. Falha de transporte não prova
substituição, mas impede execução/entrega. Consulta do journal não abre banco de
negócio nem depende de uma nova descoberta; suas permissões continuam obrigatórias.

`verificar_fonte` mantém `sqlExecuted: false` para SQL de negócio e informa
`metadataSqlExecuted: true`. Sucesso não publica skills nem concede acesso a dados.
A migração `0005` suspende fontes anteriores sem prova nativa e suas dependências,
sem apagar treinamento, reescrever snapshots ou importar cadastros legados.

## Prova na própria conexão executora

O MCP v2 envia `expectedSource: {version: 1, dialect, identityHash}` obtido no
cadastro. Exige `sourceIdentity: 1` na consulta de capacidades e o hub verifica
novamente a sessão viva antes do dispatch, também em batches. O agente recusa
essa execução se a extensão não estiver negociada. Campo ausente permanece
compatível com contratos antigos do hub/agente, mas nunca é fallback do MCP v2.

`sql.execute` verificado usa uma conexão dedicada no agente, sem pool, reconexão,
retry ou cache de resultados. Confere a prova admitida nessa conexão antes do SELECT
e novamente antes de entregar o resultado. Policy vigente com banco obrigatório
continua exigida mesmo com a flag legada de autorização desligada; decisões de
cache não substituem essa checagem. O caminho é materializado, limitado a 16 MiB;
stream nativo, idempotency_key e múltiplos resultados são recusados. Paginação usa
o motor comprovado; Firebird recebe apenas a paginação SQL já treinada no MCP.

`sql.operation.execute` confere o hash/dialeto admitidos na conexão dedicada antes
de abrir a transação e executar qualquer etapa de negócio. A prova substitui o
SELECT anterior de nome, mantendo um comando interno no teto de 32. A conexão
não se reconecta. SQL treinado não pode trocar de banco/conexão. O hash de conteúdo
calculado pelo agente inclui expectedSource; o namespace do journal inclui a prova
esperada, token e vínculo. O identificador físico novo combina origem do hub e
hash admitido. `get/cancel` preservam essa referência sem consultar o banco de negócio.

Identidade divergente antes da transação termina sem lançamento; uma chamada
duplicada devolve o estado durável e não reexecuta, mesmo após correção do destino.
Isso não elimina incerteza de commit nem autoriza retry. Não altera a garantia
limitada de identidade em clones/restaurações descrita abaixo.

## SQL Anywhere: UUID provisionado pelo DBA

Exceção DV2-007 do MCP, aprovada
em 2026-10-11. O agente consulta `DBA.se7e_source_identity`: exatamente uma linha,
versão `1` e UUID v4 canônico. Hash inclui namespace `source-discovery-provisioned-v1`,
motor, endpoint, nome da base, UUID e versão. Não inclui senha, caminho do arquivo
nem propriedades reservadas. Apenas hash/tipo/horário saem do agente.

O script revisável `tool/sql_anywhere_source_identity.sql` é executado
**somente pelo DBA**, em manutenção e após confirmar o destino e o backup. Ele
cria singleton com UUID e trigger que recusa INSERT/UPDATE/DELETE posteriores;
tabela já existente deve causar parada, nunca sobrescrita de identidade. O DBA
confere a versão e concede somente SELECT sobre essa tabela ao principal técnico
do agente. Não conceder DBA, alteração de schema/trigger ou escrita no marcador.
Permissões de negócio são separadas e continuam limitadas pela policy/skill/token.

Descoberta, cadastro, consulta e DML nunca criam/reparam o marcador. Ausência,
permissão insuficiente, versão desconhecida ou metadados incompletos bloqueiam uso.
O marcador é reservado: não pode ser treinado como tabela consultável ou gravável,
e o guard do agente recusa referências em operações. A prova é conferida antes e
depois de SELECT e antes da transação DML na própria conexão, sem reconnect.

Procedimento operacional obrigatório:

1. Reinício da mesma base conserva UUID. Não reenrolar por falha de transporte.
2. Cópia destinada a **outra fonte** conserva o UUID no backup: mantê-la isolada do
   agente e provisionar novo UUID em manutenção DBA antes de cadastrar. Nunca
   associar automaticamente treino ou permissões da original. Encerrar conexões
   durante a manutenção e repetir descoberta/cadastro explícitos.
3. Restauração da **mesma fonte** conserva UUID. Suspender o acesso durante o restore,
   revisar schema/treinamento e operações pendentes após voltar. Um journal externo
   pode registrar lançamentos que o backup não contém; conciliar negócio antes de
   liberar. Não apagar journal, reenviar operações incertas ou inferir rollback.
4. UUID ausente/alterado ou identidade incompatível exige intervenção e revisão
   explícitas. A aplicação não recupera o valor antigo nem repara a tabela.

Uma cópia que mantenha UUID, nome e endpoint observáveis é indistinguível pelo
contrato. Esse limite exige o procedimento DBA, não uma promessa de detectar todo
restore/clone. Aliases de endpoint também podem gerar hashes físicos diferentes.

Homologação isolada: `plug_mcp/scripts/run-sql-anywhere-identity-homologation.ps1` exige raiz
temporária nova `se7e_persona_<12 hex>_test`; não usa `.env`, DSN existente ou fonte
cadastrada. Cria/provisiona apenas essa fixture e testa permissões, reinício e
substituição homônima. Executar o runner não autoriza provisionar bases do usuário.

## Limitações que ainda bloqueiam aceite

Identificadores nativos também têm limites em clones/restaurações que preservam
metadados, e no reuso eventual de OIDs. Não se promete detectar substituição
byte a byte que preserve toda a identidade observável. Políticas operacionais de
restauração/reenrolamento precisam integrar a solução final. Ainda falta homologar
o RPC novo numa instalação completa de hub/agente, incluindo permissões mínimas,
troca real por base homônima, timeout e configuração alterada durante dispatch.
Deploy e aceite integral permanecem bloqueados.


Historical isolated MCP/REST/Socket.IO/ODBC evidence covered four engines,
including the SQL Anywhere identity marker provisioned within the fixture.
O validador de entrada sql.execute aceita expectedSource v1 estritamente, sem
remover os portões de negociação, policy, banco e identidade no executor.
Perfil remoto incompleto falha com ValidationFailure, sem interromper callbacks.
Isso complementa os testes nativos; não elimina as pendências de instalação
completa e cenários em trânsito descritas acima. Procedimento e limites:
plug_mcp/docs/persona-v2/homologation-chain.md.

O transporte v1 preserva seu enum histórico por compatibilidade; isso não
concede suporte ao motor. O runtime recusa Firebird antes de metadados ou SQL
de negócio. A matriz atual exige PostgreSQL, SQL Server e SQL Anywhere.


## Structural inspection (sourceSchema v1)

Current engine scope is PostgreSQL, SQL Server and SQL Anywhere. Firebird
examples and fixture results below are historical only; the runtime rejects
that engine before metadata or business SQL. These results do not replace
acceptance of the current three-engine candidate.


Extensão aditiva, em desenvolvimento e sem liberação de deploy. `sql.describeSchema`
exige `sourceSchema`/`sourceIdentity` v1, ID correlacionável, token vigente,
ClientAgentAccess upstream e banco obrigatório da policy. Inspeciona somente recursos
explicitamente autorizados; recebe até 16 recursos únicos e pagina até quatro.
Schemas são explícitos; Firebird usa schema nulo. SQL, DSN ou conexão do consumidor
não entram nesse contrato. As consultas aos catálogos são fixas e os nomes são valores
parametrizados. O agente usa a mesma conexão para identidade antes/depois e metadados.

Retorna tipos/nulabilidade, PKs, índices únicos e FKs com pares ordenados e somente
alvos no escopo autorizado. Defaults, comentários e linhas de negócio não são enviados.
`coverage`/`limitations` distinguem informação incompleta; visibilidade limitada
não prova inexistência. Estados são enabled/disabled/unvalidated/unknown por recurso.
PostgreSQL verifica índices/validação e triggers de FK; SQL Server índices e confiança
das FKs; Firebird índices associados. Índices parciais ou por expressão não provam
unicidade global. SQL Anywhere mantém enforcement desconhecido: o indicador interno
not_enforced não habilita dependências. SQL Anywhere distingue tabelas BASE de views
regulares VIEW por SYSTAB.table_type_str; materialized views não entram como views
regulares nem como tabelas implicitamente. `metadataPage` é separado da paginação SQL;
nulos obrigatórios são preservados, inclusive schema Firebird.

`sql.execute.expectedStructure` exige as mesmas capabilities e `expectedSource`.
Contém recursos, colunas e constraints utilizadas; constraints exigem também
sourceConstraints v1. Destinos de FK devem pertencer ao escopo autorizado. A policy
autoriza os recursos; a mesma conexão confere colunas e chaves/ordem/status antes e
depois do SELECT. Divergência descarta linhas com SOURCE_STRUCTURE_MISMATCH, sem
reconectar/repetir. DML, prova de enforcement SQL Anywhere e matriz completa de
mínimos privilégios/views continuam pendentes. Prova não aprova significado de negócio.

Referências técnicas dos catálogos: [PostgreSQL pg_constraint](https://www.postgresql.org/docs/15/catalog-pg-constraint.html),
[SQL Server sys.columns](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-columns-transact-sql?view=sql-server-ver16),
[SQL Anywhere SYSIDXCOL](https://help.sap.com/docs/SAP_SQL_Anywhere/93079d4ba8e44920ae63ffb4def91f5b/3be8e1416c5f1014aa0185d6ff33803a.html)
e [Firebird RDB$RELATION_FIELDS](https://firebirdsql.org/file/documentation/chunk/en/refdocs/fblangref25/fblangref-appx04-relfields.html).
SQL e schemas efetivos estão no runtime e nos JSON/OpenRPC empacotados; referências
não substituem execução dos testes reais de cada versão/driver.

A fixture da cadeia persistente acrescenta rel_left/rel_link/rel_right, com FKs
compostas e policy somente leitura. O MCP fixa a FK na filha na navegação 1:N e
preserva intermediárias/elos N:N; a relação conceitual não autoriza JOIN direto.
A ação fixa relationship-drop-right-fk do companion confere a base descartável
antes de remover fk_rel_right, sem receber SQL ou identificadores do consumidor.
PostgreSQL, SQL Server e Firebird recusam a consulta após a remoção; SQL Anywhere
continua recusando adoção dependente de enforcement desconhecido. Esse alcance
não conclui a matriz integral nem libera instalador/appcast/deploy.
