# Performance Benchmark Strategy

## Objetivo

Este documento define a estrategia de benchmark para evoluir desempenho sem
regredir comportamento. Ele existe para responder tres perguntas:

1. Onde esta o gargalo real: banco, pool, serializacao, compressao ou socket?
2. Como comparar mudancas sem misturar perfis incompativeis?
3. Como evitar que ganho de latencia esconda regressao funcional?

Esta nota e deliberadamente analitica. Detalhes operacionais de comandos,
variaveis de ambiente e arquivos JSONL vivem em `benchmark/README.md` e
`.env.example`.

## Mapa Resumido da Implementacao

### Caminho ODBC / RPC

Fluxo principal:

1. O pedido entra pelo `RpcMethodDispatcher`.
2. O dispatcher valida o metodo e resolve o caminho de execucao.
3. O `OdbcDatabaseGateway` executa o SQL usando `odbc_fast`.
4. O handle ODBC passa por um pool configuravel:
   `OdbcConnectionPool` no modo lease-based ou
   `OdbcNativeConnectionPool` no modo native.
5. O resultado volta materializado, em `multi_result`, ou em streaming.

Arquivos centrais:

- `lib/application/rpc/rpc_method_dispatcher.dart`
- `lib/application/use_cases/execute_sql_batch.dart`
- `lib/infrastructure/external_services/odbc_database_gateway.dart`
- `lib/infrastructure/external_services/odbc_streaming_gateway.dart`
- `lib/infrastructure/pool/odbc_connection_pool.dart`
- `lib/infrastructure/pool/odbc_native_connection_pool.dart`
- `test/live/odbc_rpc_benchmark_live_e2e_test.dart`
- `test/helpers/odbc_e2e_rpc_harness.dart`

### Caminho de transporte

Fluxo principal:

1. O request e serializado segundo o contrato Plug JSON-RPC.
2. O payload pode trafegar em `PayloadFrame`, com ou sem compressao.
3. O transporte Socket.IO entrega request, chunk(s) e complete.
4. Cliente e servidor negociam limites de payload, chunking e streaming.
5. O resultado e remontado do lado do consumidor.

Arquivos e contratos centrais:

- `docs/communication/socket_communication_standard.md`
- `docs/communication/socketio_client_binary_transport.md`
- `docs/communication/openrpc.json`
- `docs/communication/schemas/`
- `test/infrastructure/codecs/transport_pipeline_benchmark_test.dart`
- `test/infrastructure/external_services/socket_transport_e2e_benchmark_test.dart`

## Gargalos Estruturais

### Banco / ODBC

#### 1. Custo de conexao no pool lease-based

No pool lease-based atual, o handle nao fica reutilizavel como em um pool
classico. A estrategia limita concorrencia e faz `connect` / `disconnect` por
lease. Isso aumenta o custo por operacao, especialmente em leituras pequenas e
repetidas.

Impacto:

- penaliza `sql.executeBatch` sem transacao;
- distorce comparacoes entre `batch_reads` e `multi_result`;
- aumenta a sensibilidade a `pool_size` sob concorrencia.

#### 2. `executeBatch` sem transacao e sequencial

O caminho atual de `sql.executeBatch` sem transacao executa comando por
comando. Para multiplos `SELECTs`, isso tende a ser menos eficiente do que
`sql.execute` com `options.multi_result=true`, porque o batch paga mais vezes o
custo de ida ao gateway e de lease no pool.

Impacto:

- `batch_reads` mede bastante overhead de infraestrutura;
- escala pior sob carga concorrente;
- nao deve ser usado como proxy de custo puro de query.

#### 3. `multi_result` tende a ganhar, mas e mais sensivel a driver

`multi_result` concentra mais trabalho em uma unica chamada ODBC e em uma unica
conexao. Em geral esse e o melhor caminho para multiplas consultas curtas, mas
depende mais do comportamento do driver e das heuristicas de fallback.

Impacto:

- melhor latencia em cenarios de multi-consulta;
- maior risco de comportamento vacuo em drivers com suporte inconsistente.

#### 4. Materializacao vs streaming

O sistema suporta hoje:

- resposta materializada completa;
- streaming direto do DB;
- streaming por chunks materializados.

Cada caminho tem custo diferente:

- materializado: mais simples, mas pode concentrar custo em memoria;
- streaming from DB: reduz acumulacao, mas aumenta custo de emissao;
- streaming chunks: adiciona trabalho de fragmentacao e montagem.

Impacto:

- o melhor caminho depende do tamanho do result set;
- a comparacao precisa olhar latencia total e latencia do primeiro chunk.

#### 5. Buffer de resultado e fallback

`max_result_buffer_mb` influencia o comportamento em respostas grandes e no
`multi_result`. Quando o buffer e insuficiente, o gateway pode cair em
fallbacks mais caros.

Impacto:

- benchmarks pequenos podem esconder o problema;
- benchmarks grandes precisam observar counters de fallback.

### Transporte

#### 1. Encode/decode logico

O custo de transformar request/response em JSON, `PayloadFrame`, chunks e
estruturas de protocolo pode ser relevante mesmo quando o banco esta rapido.

Impacto:

- em respostas pequenas, o transporte pode dominar a latencia total;
- em respostas grandes, encode/decode pode competir com o custo da query.

#### 2. Empacotamento binario em `PayloadFrame`

O transporte nao paga apenas o custo de serializar JSON. Ele tambem precisa
converter o payload para bytes, encapsular no `PayloadFrame` e carregar
metadados como `schemaVersion`, `enc`, `cmp`, `originalSize`,
`compressedSize`, `traceId` e, quando aplicavel, `requestId` e assinatura.

Impacto:

- em payloads pequenos, o overhead fixo do frame pode pesar mais do que a query;
- em payloads medios e grandes, o custo do pipeline
  `encode -> compress -> frame -> send -> receive -> decode` vira parte real da
  latencia;
- qualquer comparacao de desempenho do socket precisa considerar o custo do
  frame binario, nao apenas o custo de GZIP.

#### 3. Compressao e politica outbound

Compressao melhora uso de rede, mas adiciona CPU e pode piorar cenarios de
payload pequeno ou loopback local. No envio agente -> hub, a politica efetiva
tambem depende do modo configurado no agente (`none`, `gzip`, `auto`), do
`compressionThreshold`, da negociacao de capacidades e, quando habilitado, de
`meta.outbound_compression` por request.

Impacto:

- pode ser boa em remoto e ruim em local;
- precisa ser comparada por tamanho de payload e tipo de resposta;
- o modo `auto` evita wire `gzip` quando o payload comprimido nao melhora o
  tamanho final, mas ainda paga parte do custo de decisao e tentativa de
  compressao;
- o modo outbound escolhido na UI e por request muda o perfil do benchmark e
  precisa entrar na leitura dos resultados.

#### 4. Chunking e write amplification

Streaming com muitos chunks pequenos aumenta numero de eventos, alocacoes,
headers e trabalho do emitter/consumer.

Impacto:

- chunk pequeno demais piora throughput;
- chunk grande demais aumenta memoria e latencia do primeiro byte util.

#### 5. Overhead do caminho completo

Mesmo quando o banco esta otimizado, a pilha
`dispatcher -> codec -> socket -> client -> decode` pode continuar sendo o
gargalo.

Impacto:

- otimizacao no gateway so resolve parte do problema;
- banco e transporte precisam ser medidos separadamente.

## Hipoteses Tecnicas Atuais

### Multi-consulta

Hoje a expectativa tecnica e:

- `sql.execute` com `multi_result` tende a ser o caminho mais rapido;
- `sql.executeBatch` sem transacao tende a escalar pior para leituras curtas;
- `sql.executeBatch` com transacao serve mais para consistencia do que para
  throughput bruto de leitura.

### Knobs mais importantes

Os knobs de benchmark que mais mudam o resultado hoje sao:

- `pool_mode`;
- `pool_size`;
- `concurrency`;
- `database_hosting`;
- `max_result_buffer_mb`;
- `streaming_chunk_size_kb`;
- `binaryPayload` negociado;
- `compressionThreshold`;
- modo de compressao outbound (`none`, `gzip`, `auto`);
- flags de compressao e encoding no transporte.

## Observabilidade Implementada

### Metricas de transporte

O transporte agora coleta metricas detalhadas do pipeline binario via
`MetricsCollector` e `ProtocolMetricsCollector`:

- `transport_outbound_encode_sync` / `transport_outbound_encode_async`
- `transport_outbound_compress_sync` / `transport_outbound_compress_async`
- `transport_outbound_auto_fallback_to_none`
- `transport_outbound_frame_signed`
- `transport_outbound_compression_none` / `transport_outbound_compression_gzip`
- `transport_inbound_decode_sync` / `transport_inbound_decode_async`

Cada `PayloadFrame` outbound e inbound registra no `ProtocolMetricsCollector`:

- `timestamp`, `protocol`, `encoding`, `compression`, `direction`
- `originalSize`, `compressedSize`, `compressionRatio`, `bytesSaved`

Isso permite diagnosticar no runtime:

- quantas vezes `auto` caiu para `none`;
- quando compress/encode usou isolate;
- distribuicao de tamanhos e ratios de compressao por direcao.

### Integracao no transporte

`TransportPipeline` agora aceita `MetricsCollector?` opcional e registra eventos
durante `prepareSend` / `prepareSendAsync` e `receiveProcess` /
`receiveProcessAsync`.

`SocketIOTransportClientV2` injeta `MetricsCollector` e
`ProtocolMetricsCollector`, permitindo observabilidade end-to-end do caminho
outbound/inbound.

## O Que e um Benchmark Util

Benchmark util:

- compara apenas perfis equivalentes;
- mede sob concorrencia controlada;
- separa custo de ODBC/RPC e custo de transporte;
- registra counters de fallback;
- falha quando ha regressao relevante;
- valida que o payload continua correto.

Benchmark enganoso:

- mistura local e remoto no mesmo baseline;
- compara runs com `pool_mode` diferente;
- mede so latencia media;
- ignora warmup e tamanho pequeno de amostra;
- passa sem smoke funcional.

## Estrategia de Benchmark

### Principios

1. Cada benchmark precisa ter um perfil explicito.
2. Cada perfil precisa ter baseline proprio.
3. Benchmark sem smoke funcional nao e evidencia suficiente.
4. O benchmark precisa ser reproduzivel por configuracao.
5. A analise precisa separar diagnostico automatico de leitura humana.

### Camadas de benchmark

#### 1. ODBC / RPC sem socket real

Objetivo:

- medir o custo de banco, gateway, pool e dispatcher com minimo de ruido de
  socket.

Escopo:

- `materialized`
- `batch_reads`
- `named_params`
- `multi_result`
- `batch_tx`
- `streaming_from_db`
- `streaming_chunks`
- variantes paralelas

Implementacao atual:

- `test/live/odbc_rpc_benchmark_live_e2e_test.dart`

Observacao importante:

- este benchmark nao mede ODBC puro;
- ele ainda passa pelo `RpcMethodDispatcher` e pelo caminho RPC de aplicacao;
- o nome correto e algo como "ODBC/RPC sem socket real", nao "DB puro".

#### 2. Transporte isolado

Objetivo:

- medir custo de codec, `PayloadFrame`, compressao, chunking e emissao.

Escopo atual:

- custo de encode/decode por estagio no pipeline;
- custo de empacotamento e desempacotamento do `PayloadFrame`;
- custo de serializacao de frame (`send`);
- comparacao `none` vs `gzip` vs `auto` com payloads variados;
- payload compressivel vs nao-compressivel;
- threshold de compressao (abaixo/no/acima);
- custo de assinatura de frame;
- custo de isolate async para encode/decode/compress;
- roundtrip RPC no transporte com retries de ack;
- streaming com backpressure no caminho de socket;
- micro-benchmarks de GZIP.

Implementacao atual:

- `test/infrastructure/codecs/transport_pipeline_benchmark_test.dart` (pipeline
  completo com roundtrips)
- `test/infrastructure/codecs/payload_frame_transport_benchmark_test.dart`
  (frame isolado, compressao, assinatura, decode)
- `test/infrastructure/external_services/socket_transport_e2e_benchmark_test.dart`
  (fluxo E2E com mocks)
- `test/benchmark/gzip_codec_benchmark_test.dart` (primitivas de gzip)
- `test/benchmark/gzip_compressor_benchmark_test.dart` (wrapper com base64)

Observacao importante:

- o benchmark `socket_transport_e2e` valida o fluxo de transporte da aplicacao,
  mas usa mocks de socket e de dependencias proximas;
- portanto, ele nao mede wire real nem latencia de rede real;
- no agente Dart, o GZIP do `PayloadFrame` e das primitivas partilhadas usa
  zlib da VM (`dart:io`), nao `package:archive`;
- o `GzipCompressor` cobre o outro formato com `compressed_data` em base64 e
  limiares para evitar `compute` em payloads pequenos;
- a suite de `PayloadFrame` segue o mesmo padrao operacional das outras suites:
  execucao opt-in e gravacao JSONL opt-in.

#### 3. Caminho completo

Objetivo:

- medir query real + dispatcher + transporte + cliente.

Estado atual:

- esta camada ainda e objetivo de consolidacao, nao suite principal ja
  estabelecida;
- hoje o repositorio cobre bem ODBC/RPC sem socket real e transporte em
  benchmarks separados;
- o benchmark full path continua sendo uma lacuna planejada, nao a base do gate
  atual.

Uso correto:

- deve ser menor e mais seletivo que os benchmarks parciais;
- serve como validacao final, nao como unica ferramenta de diagnostico.

## Metricas Minimas

Cada caso deve registrar:

- `mean_ms`
- `median_ms`
- `p90_ms`
- `p95_ms`
- `trimmed_mean_ms`
- `samples_ms`

Cada run deve registrar:

- `target_label`
- `build_mode`
- `database_hosting`
- `benchmark_profile`
- `metrics_counters`

Counters importantes:

- `multi_result_pool_vacuous_fallback`
- `multi_result_direct_still_vacuous`
- `transactional_batch_direct_path`
- `connection_pool_acquire_failure`
- `connection_pool_release_failure`

Metricas adicionais ja implementadas:

- latencia do primeiro chunk;
- numero de chunks emitidos;
- p95 de estagios de conexao (`acquire`, `release`, `wait`);
- p95 de estagios diretos (`connect`, `disconnect`);
- p95 de estagios de transporte (`encode`, `decode`, `send`);
- bytes originais e comprimidos no benchmark de pipeline de transporte;
- razao de compressao e bytes poupados nas metricas de protocolo.

Metricas adicionais recomendadas:

- `time_to_first_row` no caminho materializado;
- mais counters de fallback para rotas especificas de driver, se surgirem novas
  heuristicas.

### Limites de leitura das metricas

Os percentis atuais sao uteis, mas a interpretacao precisa ser prudente:

- varias suites usam poucas iteracoes;
- com amostragem pequena, `p90` e `p95` sao sinais aproximados, nao estatistica
  forte;
- warmup ajuda, mas nao elimina ruido de ambiente.

Por isso, o gate automatico pode ser simples, enquanto a leitura humana precisa
olhar `median`, `p90`, `p95`, counters e corretude funcional em conjunto.

## Guardrails de Nao Regressao

### 1. Thresholds absolutos por caso

Thresholds absolutos sao uteis quando o ambiente e previsivel.

Bom para:

- CI controlado;
- gates simples de performance.

Ruim para:

- ambientes variaveis;
- comparacao entre maquinas distintas.

### 2. Baseline comparavel por perfil

O baseline JSONL so deve comparar runs compativeis. Os campos principais sao:

- `target_label`
- `build_mode`
- `database_hosting`
- `benchmark_profile`

Regra atual:

- o run atual pode piorar ate um teto relativo e/ou absoluto sobre a media do
  baseline recente;
- fora desse teto, o benchmark falha.

Observacao importante:

- o helper atual de regressao usa media do baseline por simplicidade;
- isso e adequado para gate automatico, mas nao substitui leitura humana de
  `median`, `p90` e `p95`.

### 3. Smoke funcional obrigatorio

Benchmark sem validacao funcional e perigoso. Cada suite de performance precisa
continuar garantindo:

- payload nao vazio quando o caso exige isso;
- `multi_result` consistente;
- streaming completo;
- comportamento transacional correto;
- ausencia de falhas de pool e fallbacks inesperados.

## Estado Atual

Ja implementado:

- benchmark live parametrizavel para ODBC/RPC;
- comparacao entre `lease` e `native`;
- cenarios paralelos para `materialized`, `batch_reads` e `multi_result`;
- cenarios `write_dml`, `timeout_cancel` e `write_dml_parallel`;
- baseline por perfil comparavel;
- thresholds absolutos;
- registro de `benchmark_profile` no JSONL;
- benchmark de transporte isolado;
- benchmark socket E2E;
- p95 por estagio anexado por caso;
- testes unitarios dos helpers de regressao e perfis;
- normalizacao de perfis `native` quando `pool_size < concurrency`;
- `build_mode` real no JSONL do benchmark socket E2E.

### Compatibilidade de baseline no perfil `native`

Registros antigos com `benchmark_profile.pool_mode: native` e `pool_size` menor
que `concurrency` deixaram de ser comparaveis ao codigo atual. O harness passou
a usar `pool_size` efetivo igual a `concurrency` para evitar timeout artificial
do worker do `odbc_fast`.

Conclusao pratica:

- baseline antigo de `native_p4_c8` nao deve ser comparado com runs novos
  equivalentes a `native_p8_c8`;
- quando houver duvida, regrave o baseline.

## Prioridades de Evolucao

### Fase 1. Multi-consulta

- comparar `batch_reads` vs `multi_result` em mais tamanhos de dataset;
- identificar se ha espaco para otimizar `executeBatch` em leituras;
- verificar se algum reuse controlado de conexao e viavel sem reabrir os
  problemas do native pool.

### Fase 2. Streaming

- medir primeiro chunk vs tempo total;
- calibrar `streaming_chunk_size`;
- comparar `streaming_from_db` contra `streaming_chunks`.

### Fase 3. Transporte

- comparar custo de empacotamento binario em `PayloadFrame` contra o resto do
  pipeline;
- comparar custo de compressao por tamanho de payload;
- medir `PayloadFrame` vs payload simples;
- comparar modos outbound `none`, `gzip` e `auto`;
- medir chunking e reconstrucao do lado cliente.

### Fase 4. Consolidar gates

- manter smoke funcional no benchmark live;
- habilitar baseline em ambiente controlado;
- definir thresholds absolutos apenas onde o ambiente for previsivel.

## Riscos

### Otimizacao errada do pool

Trocar robustez por throughput sem criterio pode reintroduzir bugs de buffer e
de validade do handle.

### Benchmark sem isolamento

Comparar runs com perfis diferentes produz conclusoes falsas e pode levar a
mudancas ruins.

### Foco excessivo em media

Media sozinha mascara cauda de latencia. O gate automatico atual usa media do
baseline por simplicidade, mas a analise tecnica precisa olhar tambem `median`,
`p90` e `p95`.

### Foco excessivo em banco

Mesmo com ODBC otimizado, o socket pode continuar limitando o throughput final.

## Recomendacao Operacional

Para cada mudanca relevante em banco ou transporte:

1. Rodar o benchmark da camada afetada com o mesmo perfil do baseline.
2. Verificar regressao, counters de fallback e corretude funcional.
3. Se a mudanca tocar transporte, rodar benchmark de transporte isolado.
4. Usar full path apenas como confirmacao final.
5. So atualizar baseline depois de confirmar ganho real e estabilidade.

## Referencias Operacionais

Para detalhes de execucao, configuracao e formatos de saida, usar:

- `benchmark/README.md`
- `.env.example`
- `docs/testing/e2e_setup.md`

## Conclusao

O caminho para melhorar desempenho sem quebrar a aplicacao nao e procurar uma
unica grande otimizacao. O caminho correto e:

- medir por camada;
- comparar apenas perfis equivalentes;
- proteger comportamento com smoke funcional;
- ler metricas de forma compativel com o que o harness realmente mede;
- evoluir pool, multi-consulta, streaming e socket com guardrails.

Hoje os dois maiores gargalos estruturais continuam sendo:

- comunicacao com a base de dados, especialmente pool e multi-consulta;
- comunicacao via socket, especialmente serializacao, compressao e chunking.

O benchmark precisa refletir exatamente essa divisao.
