# Performance Benchmark Strategy

## Objetivo

Este documento consolida o levantamento da implementacao atual de comunicacao
com a base de dados e com o socket, identifica os principais pontos de
gargalo, e define uma estrategia de benchmark para evoluir o desempenho sem
regredir comportamento nem quebrar a aplicacao.

O foco e manter tres propriedades ao mesmo tempo:

1. Medir custo real dos caminhos criticos.
2. Comparar mudancas contra baselines compativeis.
3. Garantir que performance nao venha ao custo de regressao funcional.

## Mapa Atual da Implementacao

### Caminho de banco de dados

Fluxo principal:

1. O pedido entra pelo `RpcMethodDispatcher`.
2. O dispatcher valida o metodo, aplica regras de SQL e resolve o caminho de
   execucao.
3. O `OdbcDatabaseGateway` executa o SQL usando `odbc_fast`.
4. O acesso ao handle ODBC passa por um pool configuravel:
   `OdbcConnectionPool` no modo lease-based ou `OdbcNativeConnectionPool` no
   modo native.
5. O resultado volta materializado, em `multi_result`, ou em streaming.

Arquivos centrais:

- `lib/application/rpc/rpc_method_dispatcher.dart`
- `lib/application/use_cases/execute_sql_batch.dart`
- `lib/infrastructure/external_services/odbc_database_gateway.dart`
- `lib/infrastructure/external_services/odbc_streaming_gateway.dart`
- `lib/infrastructure/pool/odbc_connection_pool.dart`
- `lib/infrastructure/pool/odbc_native_connection_pool.dart`
- `lib/infrastructure/pool/odbc_connection_pool_factory.dart`

### Caminho de socket / transporte

Fluxo principal:

1. O pedido e serializado segundo o contrato Plug JSON-RPC.
2. O payload pode trafegar em `PayloadFrame`, com ou sem compressao.
3. O transporte Socket.IO entrega request, chunk(s) e complete.
4. O cliente e o servidor negociam limites de payload, chunking e streaming.
5. O resultado e remontado do lado do consumidor.

Documentos e contratos centrais:

- `docs/communication/socket_communication_standard.md`
- `docs/communication/socketio_client_binary_transport.md`
- `docs/communication/openrpc.json`
- `docs/communication/schemas/`

## Gargalos Principais

### Banco / ODBC

#### 1. Custo de conexao no pool lease-based

No pool lease-based atual, o handle nao e mantido reutilizavel como em um pool
classico; a estrategia limita concorrencia e faz `connect` / `disconnect` por
lease. Isso traz robustez, mas aumenta custo por operacao, especialmente em
leituras pequenas e repetidas.

Impacto:

- Penaliza `sql.executeBatch` sem transacao.
- Distorce comparacoes entre `batch_reads` e `multi_result`.
- Aumenta sensibilidade a `poolSize` sob concorrencia.

#### 2. `executeBatch` sem transacao e sequencial

O caminho atual de `sql.executeBatch` sem transacao executa comando por
comando. Para multiplos `SELECTs`, isso tende a ser menos eficiente do que um
`sql.execute` com `options.multi_result=true`, porque o batch paga mais vezes o
custo de ida ao gateway e de lease no pool.

Impacto:

- `batch_reads` mede mais overhead de infraestrutura do que custo puro de query.
- Escala pior sob carga concorrente.

#### 3. `multi_result` e mais eficiente, mas mais sensivel a driver

`multi_result` faz mais trabalho em uma unica chamada ODBC e em uma unica
conexao. Em geral esse e o melhor caminho para multiplas consultas curtas, mas
depende mais do comportamento do driver e das heuristicas de fallback.

Impacto:

- Melhor latencia em cenarios de multi-consulta.
- Mais risco de comportamento vacuo em drivers com suporte inconsistente.

#### 4. Materializacao vs streaming

O sistema hoje suporta:

- resposta materializada completa;
- streaming direto do DB;
- streaming por chunks materializados.

Cada caminho tem um custo diferente:

- materializado: mais simples, mas pode concentrar custo em memoria;
- streaming from DB: reduz acumulacao, mas aumenta custo de emissao;
- streaming chunks: adiciona trabalho de fragmentacao e montagem.

Impacto:

- O melhor caminho depende do tamanho do result set.
- A aplicacao precisa medir latencia total e latencia do primeiro chunk.

#### 5. Buffer de resultado e fallback

`maxResultBufferMb` influencia o comportamento em respostas grandes e no
`multi_result`. Quando o buffer e insuficiente, o gateway pode cair em
fallbacks mais caros.

Impacto:

- Benchmarks com pouco volume podem esconder o problema.
- Benchmarks grandes precisam observar counters de fallback.

### Socket / Transporte

#### 1. Serializacao e desserializacao

O custo de transformar request/response em JSON, `PayloadFrame`, chunks e
estruturas de protocolo pode ser relevante mesmo quando o banco esta rapido.

Impacto:

- Em respostas pequenas, o transporte pode dominar a latencia total.
- Em respostas grandes, o custo de encode/decode pode competir com o custo da
  query.

#### 2. Compressao

Compressao melhora uso de rede, mas adiciona CPU e pode piorar cenarios de
payload pequeno ou local loopback.

Impacto:

- Pode ser boa em remoto e ruim em local.
- Precisa ser comparada por tamanho de payload e por tipo de resposta.

#### 3. Chunking e write amplification

Streaming com muitos chunks pequenos aumenta numero de eventos, alocacoes,
headers e trabalho do emitter/consumer.

Impacto:

- Chunk pequeno demais piora throughput.
- Chunk grande demais aumenta memoria e latencia do primeiro byte util.

#### 4. Overhead do caminho completo de socket

Mesmo quando o banco esta otimizado, a pilha `dispatcher -> codec -> socket ->
client -> decode` pode continuar sendo o gargalo.

Impacto:

- Otimizacao no gateway so resolve parte do problema.
- E necessario separar benchmark DB-bound de benchmark transport-bound.

## Leitura Atual dos Cenarios Criticos

### Multi-consulta

Hoje, para multi-consulta, a expectativa tecnica e:

- `sql.execute` com `multi_result` tende a ser o caminho mais rapido.
- `sql.executeBatch` sem transacao tende a escalar pior para leituras curtas.
- `sql.executeBatch` com transacao serve mais para consistencia do que para
  throughput bruto de leitura.

### Controle fino do pool

Os knobs mais importantes hoje sao:

- `pool_mode`: `lease` ou `native`
- `pool_size`
- `concurrency`
- `login_timeout_seconds`
- `max_result_buffer_mb`
- `streaming_chunk_size_kb`

### Diferenca entre benchmark util e benchmark enganoso

Benchmark util:

- compara perfis equivalentes;
- mede sob concorrencia controlada;
- separa custo de banco e custo de transporte;
- registra counters de fallback;
- falha em regressao relevante.

Benchmark enganoso:

- mistura local e remoto no mesmo baseline;
- compara runs com `pool_mode` diferente;
- mede apenas latencia media;
- passa sem validar que o payload retornado continua correto.

## Estrategia de Benchmark

### Principios

1. Cada benchmark precisa ter um perfil explicito.
2. Cada perfil precisa ter baseline proprio.
3. O benchmark so e valido se acompanhado de smoke funcional do mesmo fluxo.
4. O benchmark precisa ser reproduzivel por variaveis de ambiente.

### Camadas de benchmark

#### 1. Benchmark DB-bound

Objetivo:

- medir o custo de banco/gateway/pool com minimo de ruido de socket.

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

#### 2. Benchmark transport-bound

Objetivo:

- medir custo de codec, `PayloadFrame`, compressao, chunking e emissao.

Escopo coberto:

- custo de encode/decode por estagio no pipeline
- custo de serializacao de frame (`send`)
- roundtrip RPC no transporte com retries de ack
- streaming com backpressure no caminho de socket
- thresholds e baseline dedicados para transporte E2E

Implementacao atual:

- `test/infrastructure/codecs/transport_pipeline_benchmark_test.dart`
- `test/infrastructure/external_services/socket_transport_e2e_benchmark_test.dart`
- Micro-benchmarks (gzip VM + `GzipCompressor`): `test/benchmark/gzip_codec_benchmark_test.dart` (`CODEC_GZIP_BENCHMARK=true`), `test/benchmark/gzip_compressor_benchmark_test.dart` (`GZIP_COMPRESSOR_BENCHMARK=true`)

No agente Dart, o GZIP do `PayloadFrame` e das primitivas partilhadas usa **zlib da VM** (`dart:io`), nao `package:archive`. O segundo formato (linhas de query em mapa com `compressed_data` em base64) esta em `lib/infrastructure/compression/gzip_compressor.dart`, com limiares para evitar `compute` em payloads pequenos.

#### 3. Benchmark full path

Objetivo:

- medir o caminho completo: query real + dispatcher + transporte + cliente.

Escopo:

- deve ser menor e mais seletivo que os benchmarks parciais;
- serve como validacao final, nao como unica ferramenta de diagnostico.

## Matriz de Execucao Recomendada

### Banco

- `pool_mode`: `lease`, `native`
- `pool_size`: `1`, `2`, `4`, `8`, `16`
- `concurrency`: `1`, `4`, `8`, `16`, `32`
- `seed_rows`: `32`, `256`, `2048`
- `max_result_buffer_mb`: `16`, `32`, `64`, `128`

### Transporte

- `compression`: `off`, `on`
- `encoding`: `json`, `payload_frame`
- `streaming_chunk_size`: pequeno, medio, grande
- `payload_size`: pequeno, medio, grande
- `database_hosting`: `local`, `remote`

### Casos obrigatorios

- `materialized`
- `batch_reads`
- `multi_result`
- `streaming_from_db`
- `streaming_chunks`
- `materialized_parallel`
- `batch_reads_parallel`
- `multi_result_parallel`

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

Metricas adicionais implementadas:

- latencia do primeiro chunk
- numero de chunks emitidos
- p95 de estagios de conexao (`acquire`, `release`, `wait`)
- p95 de estagios diretos (`connect`, `disconnect`)
- p95 de estagios de transporte (`encode`, `decode`, `send`)

Metricas adicionais recomendadas para proxima etapa:

- bytes comprimidos e nao comprimidos por caso
- tempo de primeira resposta (`time_to_first_row`) no caminho materializado

## Guardrails de Nao Regressao

### 1. Thresholds absolutos por caso

Usar `ODBC_E2E_BENCHMARK_MAX_MS_*` para limites maximos conhecidos quando o
ambiente e estavel.

Bom para:

- CI controlado
- gates simples de performance

Ruim para:

- ambientes muito variaveis
- comparacao entre maquinas distintas

### 2. Baseline comparavel por perfil

Usar baseline JSONL com comparacao apenas entre runs compativeis.

Campos de compatibilidade:

- `target_label`
- `build_mode`
- `database_hosting`
- `benchmark_profile`

Variaveis adicionadas para esse fluxo:

- `ODBC_E2E_BENCHMARK_BASELINE_FILE`
- `ODBC_E2E_BENCHMARK_MAX_REGRESSION_PERCENT`
- `ODBC_E2E_BENCHMARK_MAX_REGRESSION_MS`
- `ODBC_E2E_BENCHMARK_BASELINE_WINDOW`

Regra:

- o run atual pode piorar ate um teto relativo e/ou absoluto sobre a media do
  baseline recente;
- fora desse teto, o benchmark falha.

### 3. Smoke funcional obrigatorio

Benchmark sem validacao funcional e perigoso. Cada suite de performance precisa
continuar garantindo:

- payload nao vazio quando o caso exige isso;
- `multi_result` consistente;
- streaming completo;
- comportamento transacional correto;
- ausencia de falhas de pool e fallbacks inesperados.

## Estado Atual dos Guardrails

Ja implementado:

- benchmark live parametrizavel para ODBC/RPC;
- comparacao entre `lease` e `native`;
- cenarios paralelos para `materialized`, `batch_reads` e `multi_result`;
- cenarios `write_dml`, `timeout_cancel` e `write_dml_parallel`;
- baseline por perfil comparavel;
- thresholds absolutos;
- registro de `benchmark_profile` no JSONL;
- benchmark transport-bound (pipeline + socket E2E);
- p95 por estagio anexado por caso;
- testes unitarios dos helpers de regressao e perfis;
- normalizacao de perfis `native` quando `pool_size < concurrency` (worker
  `odbc_fast` com timeout por pedido ~30s; ver
  `normalizeOdbcE2eBenchmarkProfilesForNativeWorker`);
- `build_mode` real (debug/profile/release) no JSONL do benchmark socket E2E.

### Baseline JSONL e perfil `native`

Registros antigos com `benchmark_profile.pool_mode: native` e `pool_size` menor
que `concurrency` (ex.: `native_p4_c8`) deixam de ser comparaveis ao codigo
atual: o harness passa a usar `pool_size` efetivo igual a `concurrency`
(`native_p8_c8`). Regrave o baseline ou alinhe a matriz em `.env` com
`native:8:8`.

### Melhorias operacionais sugeridas

- Gates de latencia: preferir `flutter test --profile` (ou workflow manual com
  `build_mode: profile`) em vez de `debug` local.
- Ajustar `ODBC_E2E_BENCHMARK_MAX_REGRESSION_MS` / socket E2E
  `SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_REGRESSION_MS` quando o ambiente for
  ruidoso.
- `odbc_fast`: o `ServiceLocator` ainda nao expoe `requestTimeout` do
  `AsyncNativeOdbcConnection`; evolucao futura depende do pacote ou de wrapper.

Arquivos relevantes:

- `test/live/odbc_rpc_benchmark_live_e2e_test.dart`
- `test/helpers/e2e_benchmark_assertions.dart`
- `test/helpers/e2e_env.dart`
- `test/helpers/e2e_benchmark_assertions_test.dart`
- `test/helpers/e2e_env_benchmark_test.dart`
- `test/infrastructure/codecs/transport_pipeline_benchmark_test.dart`
- `test/infrastructure/external_services/socket_transport_e2e_benchmark_test.dart`
- `test/benchmark/gzip_codec_benchmark_test.dart`
- `test/benchmark/gzip_compressor_benchmark_test.dart`
- `lib/infrastructure/codecs/compression_codec.dart`
- `lib/infrastructure/compression/gzip_compressor.dart`
- `tool/e2e_benchmark_profile_parse.dart`
- `test/tool/e2e_benchmark_profile_parse_test.dart`
- `test/helpers/rpc_response_test_helpers.dart`

## Roadmap Tecnico de Evolucao

### Fase 1. Atacar multi-consulta

- comparar `batch_reads` vs `multi_result` em mais tamanhos de dataset
- identificar se ha espaco para otimizar `executeBatch` em leituras
- verificar se algum reuse controlado de conexao e viavel sem reabrir o
  problema do native pool

### Fase 2. Atacar streaming

- medir primeiro chunk vs tempo total
- calibrar `streamingChunkSize`
- comparar `streaming_from_db` contra `streaming_chunks`

### Fase 3. Atacar socket

- comparar custo de compressao por tamanho de payload
- medir `PayloadFrame` vs payload simples
- medir chunking e reconstrucao lado cliente

### Fase 4. Consolidar gates

- manter smoke funcional no benchmark live
- habilitar baseline em ambiente controlado
- definir thresholds absolutos apenas onde o ambiente for previsivel

## Riscos

### Otimizacao errada do pool

Trocar robustez por throughput sem criterio pode reintroduzir bugs antigos de
buffer e de validade do handle.

### Benchmark sem isolamento

Comparar runs com perfis diferentes produz conclusoes falsas e pode levar a
mudancas ruins.

### Foco excessivo em media

Media sozinha mascara cauda de latencia. O projeto precisa olhar `median`,
`p90` e `p95`.

### Foco excessivo em banco

Mesmo com ODBC otimizado, o socket pode continuar limitando o throughput final.

## Recomendacao Operacional

Para cada mudanca relevante em banco ou transporte:

1. Rodar benchmark DB-bound com o mesmo perfil do baseline.
2. Verificar regressao estatistica e counters de fallback.
3. Rodar smoke funcional do fluxo alterado.
4. Se a mudanca tocar transporte, rodar benchmark transport-bound.
5. So atualizar baseline depois de confirmar ganho real e estabilidade.

## Conclusao

O caminho para melhorar desempenho sem quebrar a aplicacao nao e procurar uma
unica grande otimizacao. O caminho correto e:

- medir por camada;
- comparar apenas perfis equivalentes;
- proteger comportamento com smoke funcional;
- evoluir pool, multi-consulta, streaming e socket com guardrails.

Hoje, os dois maiores gargalos estruturais continuam sendo:

- comunicacao com a base de dados, especialmente pool e multi-consulta;
- comunicacao via socket, especialmente serializacao, compressao e chunking.

O benchmark precisa refletir exatamente essa divisao.
