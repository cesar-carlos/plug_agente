# Correções de estabilidade e otimização — 2026-10-05

Referência inicial: `bc3835070267f8d859c484125e273e2c28c6341e` do Plug Agente.
Este relatório complementa o histórico de 2026-10-04; não promove um novo baseline.

## Alterações aplicadas

- Decoder: o `NativeFinalizer` aponta diretamente para `odbc_columnar_decompress_release(void*)` em Rust. O registro nativo determina o layout correto da alocação. O callback Dart e o mapa associado foram removidos. Liberação explícita destaca o finalizador; falhas parciais liberam o buffer; bibliotecas antigas usam cópia Dart e liberação imediata. Exports, header gerado e bindings ffigen foram atualizados juntos.
- Pool: cada aquisição recebe um identificador lógico único. A resposta de uma devolução antiga não pode apagar uma aquisição posterior que reutilizou o mesmo handle nativo. Diagnósticos distinguem checkout, retorno pendente e resultado desconhecido, com estado nativo atualizado. IDs internos correlacionam eventos sem incluir connection strings.
- Descartes: tarefas conhecidas são registradas antes da admissão no semáforo e podem ser aguardadas com timeout. A reconciliação não inicia uma segunda devolução para um descarte ainda pendente. Falhas permanecem isoladas até recuperação explícita. Encerramento, recarga e recuperação usam a barreira; recarga falha quando a limpeza não foi confirmada.
- Streaming row-major: a lista pronta é transferida ao consumidor. A emissão mapeia apenas o próximo lote e aguarda `onChunk`, verificando cancelamento antes do mapeamento e depois da entrega. O helper que retorna todos os lotes e o caminho columnar foram preservados.
- Reprodução: compilação Rust usa o `Cargo.lock` versionado, `--locked`, revisão Git completa e manifesto SHA-256. Flutter recebe o binário pelo hook; o empacotamento verifica a DLL do bundle. Nenhum cache global do Pub foi editado manualmente.
- Medições: nove repetições, aquecimento, execução serial, proteção temporária contra suspensão e invalidação por mudança de fontes/binário. A mudança intencional de `odbc_fast` exige duas revisões e dois binários explícitos; outras diferenças de dependências bloqueiam a comparação. Controle instável ou baseline de heap zero é inconclusivo.
- Diagnóstico de heap v2: os checkpoints após GC não guardam os grandes relatórios de alocação. Perfis completos de alocações e CPU são coletados depois dos checkpoints. O gate não aceita diagnósticos v1 para aprovar memória.
- Ferramentas: gates ODBC recebem o ambiente do subprocesso, inclusive quando o processo pai não tem a flag. O relatório identifica número de amostras, revisão e hash do binário. O runner atual exige nove amostras; três amostras antigas permanecem legíveis, sem qualificar desempenho. O SHA do harness também é conferido. Dry-run não compila dependências. O preflight preserva logs das verificações bem-sucedidas.

Não houve alteração do protocolo Plug, métodos públicos de consulta, política de transações ou repetição de comandos após reconexão.

## Revisões e ambiente

| Etapa | Revisão `dart_odbc_fast` | SHA-256 da DLL Windows |
| --- | --- | --- |
| Tuning inicial | `7a96d3bac0c7d104802bd24a4ffd4c606f80f756` | `933c6e6b0c4c2200566c4412d28ce4bd69dd459f7b39f4ed3a76c833189dc512` |
| Transporte e primeira integração | `8c6ef35cafc6fbdfa50037e24f54da8e07fe5d60` | `ed1d286e4f690a82d66f157fe5671beacd3e2cee5c8262e03489a4e524f2c102` |
| Revisão final fixada no aplicativo | `ea1e04f03a8cf1f2d5f3790697e8bc62ba130f89` | `c072e4693d8ffdea8b024841c80f3247f403cd329e09991200a816233cb87aff` |

O baseline usa `odbc_fast` 5.0.0, fonte identificada por `f15b33653593a6eed367fdc8ba98e80540dfe771`; a DLL preservada tem SHA-256 `329f1e90398c6a9d124bcc8f57b5f0f79f4f3049f0884745eb03c0c292d7348a`. O caminho original do cache ficou indisponível durante a preparação da coleta final; a cópia no workspace foi conferida contra esse hash antes do uso, sem restaurar arquivos manualmente no cache.
Cargo.lock final: `baac5b4c66854fce0ce1766723e5d3898902284d1289209d3fc62dc6b0ce4293`.
Rust 1.93.0; Flutter 3.47.5; Dart 3.13.4; Python 3.13.14; host Windows 11 x64, build 26300.
Drivers reais: SQL Server ODBC 17.10.0006 / DBMS 14.00.1000; SQL Anywhere ODBC 16.00.2043 / DBMS 16.00.0000. Metadados completos e configuração estão nos artefatos.

## Estabilidade e regressões

O decoder antigo abortava ao executar um callback Dart no thread do finalizador nativo. A versão corrigida libera em Rust e passou pelos testes de zstd/lz4, buffers pequenos/grandes, payload inválido, falhas parciais, liberação explícita/duplicada, GC e encerramento de isolates. A regressão é reproduzida sem banco; os testes verificam o registro de alocações, não apenas ausência de exceção.

A causa do saldo residual do pool foi reproduzida com uma aquisição durante a devolução anterior: Rust já havia reutilizado o handle, enquanto a resposta antiga ainda estava a caminho do Dart. O ID único remove essa colisão. O stress do aplicativo na referência falhou nos dois casos SQL Server; após a correção, dez rodadas por banco, dois casos por rodada, passaram. O diagnóstico adicional na revisão final executou dez rodadas por banco, 2.000 aquisições e 2.000 devoluções confirmadas por banco, com IDs únicos. Em cada rodada, checkout lógico/nativo e conexão nativa ativa ficaram em zero; o pool permaneceu com 20 conexões ociosas, que foram fechadas no encerramento.

O primeiro teste de cancelamento SQL Server falhou por polling de uma consulta curta e seleção da consulta SQL Anywhere ao aliasar o DSN na matriz. A seleção agora prefere o banco específico e o teste sincroniza o primeiro lote com um consumidor bloqueado. A integração final passou nos dois bancos, incluindo transações, RPC multi-resultados, DML, bulk de 50.000 linhas e cancelamento.

A primeira execução do gate offline recebeu indevidamente overrides do `.env` de benchmark: 24 falhas de expectativas de limites de fila/pool, sem alteração dessas constantes. Essa execução está preservada. O gate foi repetido com o ambiente normal, sem esses overrides.

## Medições e decisões

### Transporte

A comparação inicial executou controle idêntico A/A, A/B e B/A, com 10 aquecimentos, nove repetições e 100 medições por perfil: 18 perfis, 97.200 pares de envio/recepção no total. Fontes e DLLs permaneceram iguais durante a medição; não houve suspensão detectada.

| Comparação | Razão de throughput candidata/base | Alertas de p95 | Resultado |
| --- | ---: | ---: | --- |
| Controle A/A | 1,0304 | 7 | inconclusivo |
| Controle invertido A/A | 0,9705 | 16 | inconclusivo |
| Ordem A/B | 0,9725 | 15 | inconclusivo |
| Ordem B/A normalizada | 0,9877 | 11 | inconclusivo |

Os controles excedem o limite de p95 (+5%). Os alertas das candidatas não permitem atribuir regressão às mudanças. Throughput isolado permanece dentro de −15%, mas não aprova a comparação.

Os snapshots v1 dessa execução retinham seus próprios perfis de alocação. Seus valores de crescimento não aprovam nem reprovam memória do produto. Isso também limita as conclusões de heap do relatório de 2026-10-04. Os artefatos originais foram preservados com essa ressalva. A investigação v2 após GC está registrada separadamente e não substitui retroativamente a identidade da candidata daquela execução.

### Investigação final de memória v2

Foram executados quatro processos, serialmente, com todos os perfis de transporte, 100 iterações por perfil, aquecimento, cinco ciclos adicionais após GC e perfil de CPU/alocações separado. As fontes e os binários permaneceram iguais; os três checkouts usaram o mesmo harness e não houve suspensão detectada. Nenhum checkpoint reteve o relatório de alocação.

| Processo | Heap inicial → primeiro intervalo após GC | Crescimento inicial | Último checkpoint |
| --- | ---: | ---: | ---: |
| Controle 1 | 97.720.480 → 100.114.512 | 2.394.032 bytes | 100.942.384 |
| Controle 2 | 103.531.680 → 98.897.248 | 0 bytes, delta negativo | 97.451.744 |
| Referência independente | 99.535.008 → 103.816.608 | 4.281.600 bytes | 103.880.864 |
| Candidata final | 99.884.864 → 100.571.568 | 686.704 bytes | 99.159.216 |

Nos cinco ciclos adicionais, a candidata variou entre 99.028.336 e 103.748.624 bytes e terminou abaixo do heap inicial. Os demais processos também oscilaram, sem crescimento monotônico. Os dados não demonstram retenção persistente nesse workload. O controle apresenta zero versus crescimento positivo entre processos iguais: a aprovação de heap continua **inconclusiva**, sem tratar zero como aprovação automática. Os testes do decoder verificam separadamente que as alocações nativas rastreadas voltam a zero.

Essa investigação usa a candidata final; não reutiliza os cronômetros da candidata anterior para produzir uma aprovação global. Deltas, snapshots completos e perfis estão em `heap-v2/` no arquivo de evidências.

### Mapeador

Com 30 aquecimentos e nove repetições por processo, em ambas as ordens:

- 50.000 linhas completas: tempo mediano observado de 0,530× e 0,496× da referência; primeira entrega de 0,010× e 0,009×.
- Cancelamento após o primeiro lote em 50.000 linhas: tempo mediano observado de 0,009× e 0,010×. A correção limita o mapeamento ao lote entregue, em vez de materializar as 50.000 linhas previamente.
- Em 1.000 linhas com cancelamento, razões observadas de 1,029× e 1,079×. O controle de p95 é instável, portanto não há regressão de velocidade confirmada nesse cenário.

Essas observações não constituem aprovação estatística global: o controle idêntico variou além dos limites mesmo após maior aquecimento. Os testes de ordem, independência das listas, normalização, consumidor lento/erro e cancelamento verificam a redução de trabalho estrutural.

### Tuning por banco

Foram executadas 72 configurações: dois bancos × três quantidades (1.000/8.000/50.000) × 12 combinações de lote/buffer, mais controles. Cada processo executou um aquecimento e nove amostras, verificando textos longos, nulos, binários, ordem e reutilização da conexão após cancelamento.

Nenhum candidato foi elegível; os controles de primeira resposta também ficaram instáveis. Não houve ajuste automático. Foram preservados os defaults e os tamanhos explicitamente solicitados. Os critérios continuam ganho mediano ≥10%, p95 da primeira resposta ≤+5%, RSS máximo ≤+10% e desempate pelo menor lote/buffer.

### Gates nativos

Na primeira rodada, a fila de validação havia consultado a flag no ambiente pai, registrando incorretamente exit 0 dos gates. `native-gates.json` contém a reaplicação autoritativa aos mesmos dados; `validation.json` original está preservado. Os gates de produção agora usam explicitamente o ambiente da execução.

| Banco | Columnar/comprimido vs row-major, melhor razão | Streaming batched/buffer | Gate |
| --- | ---: | ---: | --- |
| SQL Server, revisão 8c6ef35 | 1,214× | 0,200× | falha |
| SQL Anywhere, revisão 8c6ef35 | 1,102× | 1,093× | falha |
| SQL Server, revisão final ea1e04f | 1,315× | 0,253× | columnar passou; streaming falhou |
| SQL Anywhere, revisão final ea1e04f | 1,094× | 1,085× | falha |

Os limites permanecem columnar 1,3× e streaming 2×. SQL Server buffered entregou 8.000 linhas em um chunk; batched usou oito. O custo adicional de fetch, codificação e passagem por FFI é uma hipótese compatível com esse resultado, sem perfil suficiente para atribuir percentuais. O benchmark nativo não executa o mapeador do aplicativo: a melhoria do cancelamento no mapeador não implica atingir streaming nativo 2×. Sem baseline nativo completo comparável (o antigo decoder aborta), não se afirma uma nova regressão de throughput.

## Validação final e pendências

Resultados finais, logs e manifestos são relacionados em `validation-summary.json` e no arquivo de evidências. A biblioteca passou em 1.881 testes Rust (um ignorado), 1.873 testes Dart (53 opt-in ignorados), clippy, análise Dart e verificação de 113 símbolos FFI. O aplicativo passou em 4.800 testes offline (cinco ignorados), 89 testes dirigidos, smoke de VM Service v2 e cinco verificações de arquitetura; a integração final passou em 11 testes por banco. Ferramentas Python, incluindo preflight: 112 testes; release/appcast: 43 testes; actionlint e validador CI passaram.

Build Windows Release aprovado. A verificação do bundle confirmou a DLL final e os DLLs obrigatórios do runtime Visual C++. Cinco probes nativos de instalação, dois contratos CTest do updater e o smoke do helper com argumentos inválidos passaram. A sintaxe do instalador e seus testes Pascal de recuperação passaram. Esses testes locais preservam a política de aviso para dependências opcionais e bloqueio para falhas críticas, mas não aprovam instalação/upgrade/reparo em outros sistemas.

O arquivo `evidence.zip` contém os logs e resultados completos, com connection strings e segredos configurados removidos das cópias. `evidence-manifest.json` identifica o SHA-256 do arquivo e de cada evidência. Os originais locais e os resultados que falharam foram preservados; as versões compactas em JSON permitem revisar as decisões sem extrair todos os perfis.

A matriz de instalação/atualização/reparo permanece **pendente** para Server 2016/2019/2022/2025 e Windows 10/11. A consulta aos runners GitHub retornou zero runners disponíveis. Compilação e testes de políticas/probes no host Windows 11 não equivalem à execução dessa matriz em máquinas descartáveis. Dependências opcionais continuam gerando aviso/relatório; falhas críticas continuam interrompendo, conforme as políticas já presentes em `bc383507`.

Não houve publicação no Pub.dev, distribuição de instalador, release ou atualização de feed. Certificados/segredos de publicação ausentes continuam bloqueando distribuição de produção. PostgreSQL e demais sistemas/drivers não disponíveis não foram aprovados. Limites de desempenho não foram reduzidos; nenhum baseline foi promovido.
