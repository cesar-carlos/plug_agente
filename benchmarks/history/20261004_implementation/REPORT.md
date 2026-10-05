# Relatório de implementação — CI e benchmarks confiáveis

**Resultado: desempenho inconclusivo; aprovação global bloqueada.** O controle com duas cópias da mesma revisão ultrapassou o limite de p95. Há também falhas funcionais no decoder columnar comprimido e no stress de pool do SQL Server.

## Alterações e preservação

- Consolidadas as correções de LF dos arquivos nativos, DATABASE_URL de geração do Prisma e código Drift gerado.
- Preservadas as alterações ODBC e os testes existentes do usuário; sem alteração do cache ou da versão odbc_fast 5.0.0.
- Harness nativo local com fixture determinística de 8.000 linhas, criação fora da medição, equivalência integral e limpeza em finally. Sem fallback de consulta.
- Gateway materializado identificado como rowMajor; formatos nativos verificados no buffer efetivo. Cenários incompletos invalidam a aprovação.
- Wrapper com ambiente por processo e benchmark-path respeitado; parsers aceitam Shell:, decimais e os seis cenários async.
- Resumo v2 com revisão e hash dos fontes, SDK, dependências, driver, workload, parâmetros, categorias e unidades; v1 permanece legível e incompatível para aprovação.
- Comparações e promoção exigem cobertura completa, identidade compatível e controle aprovado. Limites mantidos: p95 +5%, throughput −15%, crescimento do heap +10%.
- CI publica artefatos mesmo com gates reprovados e mantém bancos reais fora dos runners sem DSN. Código de falha 3 dos gates ODBC preservado pelo agregador.
- Teste antigo de warmup separado em construção, primeira execução, execução aquecida e construção com execução de batch vazio.

## Ambiente e método

- Base: `79ecc2dc44277240ed8b2c230c7d6c578721406b`; candidata: `bdfd3ad00edad28e25f8cb6361eda3b8b1c9c785` com alterações locais.
- Hash dos fontes da candidata: `df67a2e06c7ac84d949396fa02a2a8d5da9a8f87d1862cb1c5e848aeff558d9d`.
- Flutter: Flutter 3.47.5 • channel stable • https://github.com/flutter/flutter.git; Dart: Dart SDK version: 3.13.4 (stable) (Tue Sep 15 01:01:15 2026 -0700) on "windows_x64".
- 203 versões de dependências registradas; versões iguais nos checkouts de comparação.
- Transporte: 18 perfis; 10 aquecimentos e 100 medições por perfil, nove repetições por revisão. Controle A/A, base/candidata e candidata/base executados sequencialmente. 97.200 pares de envio/recepção medidos; contagens de amostras verificadas.
- p95: mediana dos nove p95 de cada perfil. Throughput: razão entre as medianas do tempo total das nove repetições. RSS é informativo e separado do heap.
- Heap Dart por VM Service, GC e checkpoints equivalentes em quatro execuções independentes dos cronômetros de aprovação. Perfis CPU, alocações e GC coletados depois da medição de heap.
- Native async/streaming: um aquecimento e três repetições, fixture de 8.000 linhas. Async: 24 consultas por amostra, workers 1/4, pool 4; streaming: buffer 1 MiB em bytes, fetch 1.000 linhas.

## Comparação válida de transporte

| Comparação | Variação de throughput | Alertas de p95 | Crescimento heap base → candidata | Resultado |
| --- | ---: | ---: | ---: | --- |
| Controle idêntico A/A | -3.02% | 20 | 0 → 3367424 bytes | fail |
| Base → candidata | +9.26% | 8 | 1164480 → 1352496 bytes | fail |
| Candidata → base, razão normalizada base/candidata | +6.19% | 13 | 1164480 → 1352496 bytes | fail |

O controle falhou: os alertas das comparações não permitem atribuir causalidade às alterações recentes. Throughput aprovado isoladamente não compensa o controle reprovado.

### SQL grande assinado, sem compressão

| Ordem | Envio p95 base → candidata | Recepção p95 base → candidata | Variação recepção |
| --- | ---: | ---: | ---: |
| control | 5.752 → 6.319 ms | 4.516 → 5.314 ms | +17.67% |
| forward | 9.619 → 9.407 ms | 7.603 → 10.742 ms | +41.29% |
| reverse | 8.055 → 9.341 ms | 5.885 → 10.392 ms | +76.58% |

### Checkpoints independentes de memória

| Execução | Heap após GC antes → depois | Crescimento | RSS |
| --- | ---: | ---: | ---: |
| control-1 | 100475440 → 100136208 bytes | 0 bytes | 327602176 bytes |
| control-2 | 100468624 → 103836048 bytes | 3367424 bytes | 298188800 bytes |
| base | 99017056 → 100181536 bytes | 1164480 bytes | 349208576 bytes |
| candidate | 116082048 → 117434544 bytes | 1352496 bytes | 371572736 bytes |

O controle compara crescimento zero com 3.367.424 bytes, portanto excede o limite sem exceção especial para base zero. Candidata: 1.352.496 bytes versus 1.164.480 da base (+16,15%); alerta de heap, sem conclusão causal em ambiente com controle reprovado.

Históricos v1 e medições anteriores com apenas 51 amostras assinadas foram preservados como incompatíveis/inválidos. Não fundamentam aprovação nem comparação com os valores acima.

## Cobertura real e gates

| Família | SQL Anywhere | SQL Server | Observação |
| --- | --- | --- | --- |
| Async rowMajor workers 1/4 | aprovado | aprovado | 8.000 linhas verificadas |
| Async columnar workers 4 | aprovado | aprovado | encoding real verificado |
| Async columnarCompressed | falha | falha | abort do decoder nativo |
| Async pool nativo e prepared reuse | aprovado | aprovado | sem fallback/timeouts |
| Streaming buffer/batched | medição válida | medição válida | gate opcional 2× reprovado nos dois |
| Transações e modos de pool | aprovado | aprovado | testes funcionais direcionados |
| DML perf e bulk 50.000 linhas | aprovado | aprovado | quantidade e resultados verificados |
| Stress concorrente | aprovado | falha em dois casos | pool ativo inesperado 1/2 |
| Contenção e recuperação de lock | aprovado | aprovado | cobertura existente preservada |

- SQL Anywhere: dbodbc16.dll 16.00.2043, DBMS 16.00.0000.
- SQL Server: msodbcsql17.dll 17.10.0006, DBMS 14.00.1000.
- Gate streaming mínimo 2×: SQL Anywhere 1,200×; SQL Server 0,389×. Código de falha 3; limites não alterados.
- Gate opcional columnar: cenário comprimido falha, portanto a qualificação completa é inválida; ganho do formato simples não substitui o cenário ausente.
- Gateway materializado: dois perfis de serviço com rowMajor efetivo; não qualifica velocidade nativa columnar.
- PostgreSQL: sem cobertura, DSN ausente. Transporte, stack e hot paths locais executados.

## Diagnóstico e pendências

1. Decoder externo odbc_fast 5.0.0 aborta em NativeFinalizer(Pointer.fromFunction(...)), com “Cannot invoke native callback from a different isolate”. Reproducer sem banco: validate_native_odbc_result.dart com drivers-v2/native_reproducer/columnar-compressed-input.json no stdin. Dependência e gate mantidos; child process contém o abort e permite finally da fixture.
2. Stress SQL Server retorna pool ativo 1/2 apesar das tarefas finalizadas. Controles nativos menores, async e transação preparada, ficaram em zero em dez rodadas; não estabelecem a causa do stress. Hipótese baseada em capacidade máxima foi descartada pelo estado detalhado total/idle/active.
3. Controle de ruído reprovado. Repetir em ambiente estável para aprovação do transporte; baseline não promovida.
4. Perfis separados não localizaram remoção segura de trabalho redundante. Nenhuma otimização nova de produção foi aplicada. CPU dos workers sem amostras úteis limita o diagnóstico; snapshots de alocação após GC e eventos do timeline não equivalem ao total de alocações ou ao número de coletas.

Perfil final da candidata: 1.286 amostras na isolate principal. json_payload_size_heuristic.walk: 22 ticks exclusivos (1,71%); não estabelece redundância removível. Workers: zero amostras. Timeline: 27.226 eventos de GC, não 27.226 coletas. Detalhes em candidate-diagnostics-analysis.json.

## Validação

- Suíte Flutter offline: 4.784 testes passaram; cinco ignorados.
- Contratos de comunicação do agente: 86 passaram; contratos Hub/Prisma: 50 passaram em dez arquivos.
- Contrato runtime de encoding: 68 passaram; testes dirigidos de harness: seis passaram.
- Análise Flutter limpa; build Windows debug aprovado; dois testes CTest e smoke dos dois helpers aprovados.
- Drift: segunda geração com zero outputs e hash idêntico. Prisma gerado com DATABASE_URL de CI.
- Ferramentas Python: 72 testes passaram; actionlint e git diff --check aprovados.
- SQL Anywhere: 12 testes live passaram. SQL Server: dez passaram, dois de stress falharam. Matriz e suíte publicam artefatos apesar das falhas.
- CI remoto não reexecutado; alterações locais sem commit/push. Baseline não promovida.

## Artefatos

- final-suite/summary.json e REPORT.md: resumo v2 e todas as métricas da suíte final.
- transport-qualified/comparison.json: controle, duas ordens, identidades e gates.
- transport-comparison-metrics.csv: valores anteriores/posteriores de todos os p95 e limites.
- transport-qualified/*-diagnostics.json: heap, CPU, alocações e timeline separados.
- drivers-v2/: matriz nativa e reproducer do decoder; live/: testes de banco; logs de validação na raiz.

Controle do stress na revisão base: **fail**, exit 1. Os mesmos dois cenários falharam por conexão ativa restante (1). Falha já presente na base; causa pendente. Veja base-stress-control.log.

## Complemento de 2026-10-05

As correções do decoder, a causa do saldo residual do pool e a validação posterior
estão no [relatório de correções](../20261005_performance_corrections/REPORT.md).
O coletor de heap anterior retinha os próprios relatórios de alocação; os números
de heap acima ficam preservados como históricos e não fundamentam aprovação ou
regressão do produto. O novo diagnóstico v2 separa esses perfis dos checkpoints.
