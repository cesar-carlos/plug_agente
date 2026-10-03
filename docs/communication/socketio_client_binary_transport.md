# Socket.IO Client Guide (Binary Transport)

## Objetivo

Este guia define o padrao obrigatorio para clientes que publicam ou consomem
eventos Socket.IO do Plug Agente no transporte binario atual.

O documento `docs/communication/socket_communication_standard.md` continua
descrevendo o estado implementado atual do agente. Este guia descreve o
comportamento que clientes devem seguir no contrato de transporte em producao.

## Regra principal

Registration, capabilities, heartbeat, RPC, ACK and streaming payloads must
travel in `PayloadFrame`. Hub control events `agent:register_error` and
`agent:session.superseded` use plain JSON and must be handled separately.

O payload logico JSON-RPC nao deve ser emitido diretamente como objeto JSON em
producao.

## Eventos cobertos

The frame contract applies to these events:

- `agent:register`
- `agent:capabilities`
- `agent:ready`
- `agent:heartbeat`
- `hub:heartbeat_ack`
- `rpc:request`
- `rpc:response`
- `rpc:request_ack`
- `rpc:batch_ack`
- `rpc:chunk`
- `rpc:complete`
- `rpc:stream.pull`

Eventos internos do proprio Socket.IO, como `connect`, `disconnect`,
`connect_error` e `error`, nao usam este envelope.

`connection:ready` is an informational hub event documented as a frame; the
current agent does not consume it and emits `agent:register` on Socket.IO
`connect`. The old hub `raw_json` compatibility deadline was 2026-09-30;
this repository review does not verify whether deployed hubs removed it.
The optional hub profile socket channel also uses frames, while this agent
synchronizes profiles through REST.

## Envelope de transporte

Formato esperado:

```json
{
  "schemaVersion": "1.0",
  "enc": "json",
  "cmp": "gzip",
  "contentType": "application/json",
  "originalSize": 1234,
  "compressedSize": 456,
  "payload": "<binary>",
  "traceId": "trace-001",
  "requestId": "req-001",
  "signature": {
    "alg": "hmac-sha256",
    "value": "<base64>",
    "key_id": "shared-key-01"
  }
}
```

Regras:

- `payload` contem bytes binarios; em serializacao JSON tambem pode aparecer
  como string base64 equivalente.
- `enc` descreve o formato antes da compressao. Valor padrao: `json`.
- `cmp` descreve o algoritmo aplicado ao payload codificado.
- `cmp` pode ser `gzip` ou `none`.
- Em payloads acima de `compressionThreshold`, o emissor pode usar `gzip` quando
  isso reduzir o tamanho; o agente Plug, no modo de compressao **automatico**,
  envia `cmp: none` quando o GZIP nao fica menor que o JSON UTF-8 bruto.
- O `PayloadFrame` continua carregando bytes de **JSON UTF-8** como payload
  logico; o runtime atual nao negocia MessagePack, Protobuf ou outro codec
  binario real.
- Em payloads pequenos (abaixo do limiar), `cmp: none` e aceito e esperado.
- `originalSize` deve refletir o tamanho antes da compressao.
- `compressedSize` deve refletir o tamanho efetivamente transmitido.
- `signature` e opcional, mas quando presente cobre o frame de transporte.

### Descoberta do formato por mensagem (sem inferir modo do emissor)

Cada frame informa explicitamente `enc` e `cmp`. O receptor **nao** deduz se o
emissor estava em modo Automático, Sempre GZIP ou Desligado: ele apenas le os
campos do frame e aplica decode/descompressao. No fio existem somente
`cmp: gzip` ou `cmp: none`; o modo Automático do agente só decide qual dos dois
usar naquele envio.

Representacao de `payload` por plataforma:

- Dart/Flutter: `ByteBuffer`, `Uint8List` or `List<int>`; production emits
  `PayloadFrame.toSocketPayload()` to keep Socket.IO debug formatting bounded.
- Node.js: `Buffer`
- Browser: `Uint8Array` ou `ArrayBuffer`

## Fluxo obrigatorio do emissor

Para qualquer evento de aplicacao:

1. Montar o payload logico do evento.
2. Serializar em JSON UTF-8.
3. Avaliar GZIP quando o tamanho codificado atingir `compressionThreshold`
   (ou sempre que a politica local exigir); no modo automatico, usar GZIP apenas
   se o resultado for menor que os bytes UTF-8. Em qualquer modo, nao emitir
   gzip quando `originalSize / compressedSize` exceder `maxInflationRatio`; use
   `cmp: none` nesse caso.
4. Montar o `PayloadFrame`.
5. Assinar o frame quando o contrato da sessao exigir assinatura.
6. Emitir o evento Socket.IO com o frame contendo `payload` binario.

## Fluxo obrigatorio do consumidor

Ao receber qualquer evento de aplicacao:

1. Validar que a mensagem chegou como `PayloadFrame`.
2. Ler `enc`, `cmp`, `originalSize` e `compressedSize`.
3. Verificar assinatura do frame quando presente.
4. Extrair `payload` binario.
5. Descomprimir quando `cmp == gzip`.
6. Decodificar conforme `enc`.
7. So depois processar o envelope logico JSON-RPC.

## Regras de validacao e confiabilidade

- Validar `compressedSize` antes da descompressao.
- Validar `originalSize` apos a descompressao.
- Rejeitar `enc` nao suportado.
- Rejeitar `cmp` nao suportado.
- Aplicar limite de expansao para evitar zip bomb.
- A descompressao deve ser incremental e limitada antes de acumular a saida:
  usar o menor entre `originalSize`, o limite negociado e a razao maxima de
  expansao. Excedente, razao excessiva, tamanho divergente e GZIP invalido sao
  `CompressionFailure`, sem derrubar a conexao.
- Nao assumir que toda mensagem vira `gzip`; suportar `cmp: none`.
- Mapear falha de **decode** do conteudo ja descomprimido (ex.: JSON invalido apos `cmp: none` ou apos gunzip) para `-32010`.
- Mapear falha de **compressao/descompressao GZIP** do blob em `payload` para `-32011`.
- Mapear **excesso de payload** / limites negociados para `-32009`.
- Quando o erro for de **encode JSON** do payload logico antes de montar o frame (payload invalido para serializar), mapear para `-32009` (`invalid payload`), nao confundir com `-32011`.

### Implementacao de referencia (Plug Agente, Dart)

- **Wire / `PayloadFrame`:** `TransportPipeline` em `lib/infrastructure/codecs/transport_pipeline.dart`. Para emissao em producao, usar **`prepareSendAsync`** em vez de `prepareSend`, para JSON e gzip grandes poderem correr em isolate.
- **GZIP:** `lib/infrastructure/codecs/compression_codec.dart` uses
  `package:archive`. Generic send/receive GZIP operations use reusable
  `TransportWorkPool` workers from 32 KiB: send compares pre-compression UTF-8
  size; receive compares `PayloadFrame.originalSize`, rather than wire size.
- **JSON em isolate:** o runtime atual so offloada encode/decode JSON quando o
  tamanho UTF-8 estimado passa de ~384 KiB; abaixo disso, o caminho padrao
  permanece no isolate principal.
- **Segundo formato (nao e o frame):** respostas SQL podem usar `GzipCompressor` (`lib/infrastructure/compression/gzip_compressor.dart`): lista de maps com `compressed_data` (base64) e `is_compressed`; e independente do envelope `PayloadFrame` acima.

JSON, GZIP and HMAC share a lazily started pool of two workers by default;
`TRANSPORT_WORKER_POOL_SIZE` clamps to 1..4. Generic HMAC sign/verify offload
starts at 64 KiB (`TRANSPORT_SIGNING_ISOLATE_THRESHOLD_BYTES`). Streaming
`rpc:chunk`/`rpc:complete` uses dedicated thresholds: JSON/GZIP worker offload
at 16 KiB, JSON row-count offload at 32 rows, and compression from 2048 bytes.
Overrides are `RPC_CHUNK_JSON_ISOLATE_THRESHOLD_BYTES`,
`RPC_CHUNK_GZIP_ISOLATE_THRESHOLD_BYTES`, `RPC_CHUNK_ROW_ISOLATE_THRESHOLD`,
and `RPC_CHUNK_COMPRESSION_THRESHOLD_BYTES`. Columnar chunks skip GZIP by
default; opt in with `RPC_CHUNK_COLUMNAR_GZIP_ENABLED` when appropriate.

## Handshake e capabilities

### Worker, stream and control lifecycle (profile 2.11.2)

`dispose()` stops admission immediately, fails queued and active pool jobs,
closes reply channels/listeners and kills isolates. Late startup or replies
cannot reactivate the pool. Startup failures and unexpected exits fault that
instance permanently; there is no automatic retry or synchronous fallback.
Internal diagnostics expose aggregate active/queued/failed/cancelled counts,
worker occupancy and queue wait without changing public snapshots.

Each emitter has one drain. It reserves credit before awaiting a send, caps
all queued admission (excluding the chunk in flight), and returns the existing
`false` result on overflow. Completion is emitted once after accepted chunks.
Disconnect or idle expiry faults the producer and releases buffered state;
identity checks prevent old callbacks from deleting a replacement stream.

Heartbeat preparation and ACK waiting are separate. A tick cannot overlap
pending preparation. Failed/false sends do not start the ACK timeout; async
exceptions are handled. Preparation, traces and timers belong to a session
epoch. Pull and heartbeat-ACK decoding use independent ordered sequences:
small uncompressed frames remain synchronous when idle; heavy gzip/HMAC/JSON
work uses the existing asynchronous decoder and thresholds. Effects after
awaits require the same live connection and generation, including overload
identity extraction. No new control-frame limits are introduced.

The hub reconstructs row maps from valid columnar chunks and reencodes/resigns
the consumer frame; original signed bytes cannot be reused after that change.
Conventional chunks retain their byte forwarding path. See the standard for
representation precedence and rollout order.

O handshake continua sendo um payload logico, mas o transporte fisico deve
seguir o `PayloadFrame`.

No perfil atual, `agent:register` pode incluir `profile` quando o cadastro do
agente estiver completo. Clientes consumidores devem tratar esse bloco como
opcional e ignorar quando ausente.

Quando o cliente anunciar capacidades:

- `compressions`: o agente Plug anuncia `gzip` e `none` quando a compressao
  outbound esta habilitada; se estiver desligada (`none` apenas), o anuncio pode
  ser somente `["none"]`. Nao existe terceiro valor no handshake para o modo
  **automatico** de compressao: no fio continuam apenas `cmp: gzip` ou `cmp: none`.
- `encodings` deve incluir `json`
- `extensions.binaryPayload` deve ser `true`
- `extensions.protocolReadyAck` pode ser `true`; nesse caso, depois de receber
  `agent:capabilities`, o agente emite `agent:ready` para liberar hubs que usam
  readiness explicito
- `extensions.recommendedStreamPullWindowSize` e
  `extensions.maxStreamPullWindowSize` podem anunciar hints para o hub ajustar
  `rpc:stream.pull` quando houver backpressure

Quando o cliente consumir capacidades do outro lado:

- considerar a sessao apta a compressao GZIP negociada apenas se `gzip` estiver em
  `compressions` (se o peer anunciar so `none`, nao exigir gzip outbound)
- considerar a sessao apta ao modo obrigatorio apenas se
  `extensions.binaryPayload == true`
- nao enviar `rpc:request` antes de receber `agent:capabilities`; o runtime
  atual rejeita pedidos antecipados com `invalid_request` e
  `reason: protocol_not_ready`
- para hubs com readiness explicito, considerar a sessao plenamente pronta apos
  `agent:capabilities` e o envio subsequente de `agent:ready`

### Compressao outbound por request

O runtime atual **nao** suporta override por request via `meta`. A compressao
do `PayloadFrame` de saida continua sendo determinada pela negociacao da sessao
e pela configuracao local do agente (`none`, `gzip` ou `auto`).

Perfis operacionais recomendados:

| Perfil              | Configuracao | Quando usar                                                                  | Trade-off principal                                        |
| ------------------- | ------------ | ---------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Baixa latencia      | `none`       | Fluxos sensiveis a p95/p99, payload pequeno/medio, ou payload incompressivel | Menor CPU e menor latencia, com maior consumo de banda     |
| Balanceado (padrao) | `auto`       | Trafego misto em producao, com variacao de tamanho e compressibilidade       | Equilibra banda e CPU por mensagem (`cmp: gzip` ou `none`) |
| Economia de banda   | `gzip`       | Links limitados, respostas SQL grandes/repetitivas, custo de CPU aceitavel   | Reduz bytes no fio, com aumento de latencia/CPU            |

Parametros atuais recomendados:

- `compressionThreshold`: `4096`
- `gzipIsolateThresholdBytes`: `32 * 1024` (32 KiB)
- `jsonPayloadIsolateEncodeThresholdBytes`: `384 * 1024` (384 KiB)

Benchmark local recomendado antes de alterar esses valores:

```bash
python tool/benchmarks/run_benchmark_suite.py --only transport_pipeline
dart run tool/benchmarks/benchmark_transport_pipeline.dart --iterations 20 --path sync
flutter test test/infrastructure/codecs/transport_pipeline_benchmark_test.dart --tags perf
dart run tool/benchmarks/benchmark_transport_pipeline.dart --iterations 20 --path async
dart run tool/benchmarks/benchmark_transport_pipeline.dart --iterations 20 --json
dart run tool/benchmarks/benchmark_transport_pipeline.dart --path async --gzip-isolate-threshold-sweep 16384,32768,65536
dart run tool/benchmarks/benchmark_transport_pipeline.dart --help
```

O benchmark compara `none`, `auto` e `gzip` com payloads SQL sinteticos e
exporta percentis de encode, compressao, decode e descompressao via
`ProtocolMetricsSummary.toJson()`. O caminho padrao e **`--path async`**
(`TransportPipeline.prepareSendAsync` / `receiveProcessAsync`), incluindo
contadores de isolate (`gz-c`, `gz-d`, etc.); requer runtime Flutter — use
`flutter test .../transport_pipeline_benchmark_test.dart --tags perf` quando
`dart run --path async` nao estiver disponivel no VM. Use `--path sync` para
medir somente codecs no isolate principal via `dart run`. `--gzip-isolate-threshold-sweep`
repete o benchmark async para cada limiar e resume p95/isolates por caso.

Para clientes, a regra pratica permanece:

- tratar `cmp` por mensagem, sem inferir o modo local do emissor;
- aceitar `cmp: gzip` e `cmp: none` em qualquer `rpc:response`, `rpc:chunk` ou
  `rpc:complete`;
- nao enviar campos extras em `meta` fora do conjunto publicado pelo schema.

## Assinatura e validacao logica

For signing policy, see [Assinatura opcional de transporte/payload](socket_communication_standard.md#assinatura-opcional-de-transportepayload).

As regras de schema validation, autorizacao e JSON-RPC continuam valendo sobre
o payload logico apos decode.

A assinatura possui duas camadas possiveis:

- camada principal atual: `frame.signature`, cobrindo metadados do
  `PayloadFrame` e os bytes do payload;
- legacy logical-envelope signing remains in internal compatibility helpers;
  production binary transport is mandatory, so it does not replace frame HMAC.

Canonicalizacao obrigatoria para `frame.signature`:

- monte um objeto sem o campo `signature`;
- inclua `schemaVersion`, `enc`, `cmp`, `contentType`, `originalSize`,
  `compressedSize`, `traceId`, `requestId` e `payload`;
- Include `traceId: null` and `requestId: null` in the canonical object when
  either optional field is absent on the wire. Omitting these keys changes
  the HMAC and fails verification against the Dart canonicalizer.
- represente `payload` como base64 dos bytes efetivamente transmitidos;
- serialize como JSON UTF-8 sem espacos, ordenando chaves de objetos
  lexicograficamente em todos os niveis;
- calcule HMAC-SHA256 sobre esses bytes canonicos e codifique o digest em
  base64.

Quando `signatureRequired` for negociado, todos os eventos de aplicacao da
sessao devem trazer assinatura valida. Antes da negociacao obrigatoria, um
frame sem assinatura pode ser aceito; um frame que traz `signature` deve ser
verificavel pelo `key_id` informado. Vetores de contrato estao em
`test/fixtures/payload_signing_test_vectors.json`.

Para frames acima do limiar configurado, canonicalizacao e HMAC (assinatura ou
verificacao) executam em isolate. O snapshot de saude conserva apenas metricas
agregadas de duracao e contagem de isolates; nao inclui payload, request ID,
SQL, credenciais ou outros valores de alta cardinalidade.

Ordem recomendada no recebimento:

1. validar frame
2. verificar assinatura do frame
3. descomprimir
4. decodificar JSON
5. validar schema logico
6. despachar o evento

## Ordem opcional em `sql.executeBatch`

Regra de payload **logico** (nao de framing): ver secao **Batch (implementado)**
em [`socket_communication_standard.md`](socket_communication_standard.md)
(`commands[*].execution_order`). Este guia cobre apenas o envelope
`PayloadFrame`.

## Arquivos e conteudo binario de negocio

O `PayloadFrame` e o transporte binario da mensagem, nao uma API generica de
upload de arquivo.

Regras para clientes:

- nao enviar bytes crus de arquivo fora do `PayloadFrame`;
- se um metodo de negocio aceitar conteudo de arquivo, esse conteudo precisa
  primeiro ser modelado no payload logico do metodo;
- depois disso, a mensagem completa segue o fluxo normal de serializacao,
  compressao opcional e frame binario;
- para arquivos grandes, preferir chunking no nivel do metodo de negocio.

## Exemplo em Node.js

This example covers JSON/frame encoding and bounded decoding. Pass the
negotiated limits and a frame-signature verifier for signed sessions; add the
frame HMAC after encoding and before emitting. Control events using plain JSON
must bypass this decoder. The verifier must implement the canonicalization
above and use the configured key for `signature.key_id`.

```js
import { gzipSync, gunzipSync } from "node:zlib";

const MAX_INFLATION_RATIO = 10;

function encodeFrame(
  message,
  {
    requestId, traceId, compressionThreshold = 4096,
    maxCompressedBytes = 10 * 1024 * 1024,
    maxDecodedBytes = 10 * 1024 * 1024,
    maxInflationRatio = MAX_INFLATION_RATIO,
  } = {},
) {
  const plainBytes = Buffer.from(JSON.stringify(message), "utf8");
  if (plainBytes.length > maxDecodedBytes) throw new Error("decoded payload limit exceeded");
  let cmp = "none";
  let wireBytes = plainBytes;
  if (plainBytes.length >= compressionThreshold) {
    const gz = gzipSync(plainBytes);
    if (gz.length < plainBytes.length && plainBytes.length / gz.length <= maxInflationRatio) {
      cmp = "gzip";
      wireBytes = gz;
    }
  }

  if (wireBytes.length > maxCompressedBytes) throw new Error("wire payload limit exceeded");

  return {
    schemaVersion: "1.0",
    enc: "json",
    cmp,
    contentType: "application/json",
    originalSize: plainBytes.length,
    compressedSize: wireBytes.length,
    payload: wireBytes,
    traceId,
    requestId,
  };
}

function decodeFrame(frame, {
  maxCompressedBytes = 10 * 1024 * 1024,
  maxDecodedBytes = 10 * 1024 * 1024,
  maxInflationRatio = MAX_INFLATION_RATIO,
  signatureRequired = false,
  verifySignature,
} = {}) {
  if (frame.schemaVersion !== "1.0") throw new Error("unsupported frame version");
  if (frame.enc !== "json") throw new Error("unsupported encoding");
  if (frame.contentType !== "application/json") throw new Error("unsupported content type");
  if (frame.cmp !== "gzip" && frame.cmp !== "none") {
    throw new Error("unsupported compression");
  }

  for (const size of [frame.originalSize, frame.compressedSize]) {
    if (!Number.isSafeInteger(size) || size < 0) throw new Error("invalid frame size");
  }
  if (frame.compressedSize > maxCompressedBytes || frame.originalSize > maxDecodedBytes) {
    throw new Error("payload limit exceeded");
  }
  const binary = typeof frame.payload === "string"
    ? Buffer.from(frame.payload, "base64")
    : Buffer.from(frame.payload);
  if (binary.length !== frame.compressedSize) throw new Error("compressed size mismatch");
  if (frame.signature != null) {
    if (!verifySignature || verifySignature(frame) !== true) throw new Error("invalid signature");
  } else if (signatureRequired) {
    throw new Error("missing signature");
  }
  const outputLimit = Math.min(
    frame.originalSize, maxDecodedBytes, Math.floor(binary.length * maxInflationRatio),
  );
  if (frame.cmp === "gzip" && (outputLimit < 1 || frame.originalSize > outputLimit)) {
    throw new Error("payload inflation ratio exceeded");
  }
  const plainBytes = frame.cmp === "gzip"
    ? gunzipSync(binary, { maxOutputLength: outputLimit })
    : binary;
  if (plainBytes.length !== frame.originalSize) throw new Error("original size mismatch");
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(plainBytes));
}
```

O exemplo acima segue o modo **automatico** do contrato: acima do limiar, `gzip` so quando o bloco comprimido e **menor** que o JSON UTF-8 bruto; caso contrario `cmp: none` (alinhado ao plug_agente Dart e ao hub `plug_server`).

## Exemplo em Dart

```dart
// `protocol` is the negotiated ProtocolConfig; `signer` is the configured
// PayloadSigner? for this session. Use PayloadFrameCodec in the runtime for
// full frame/version/content-type validation and pre-handshake signing policy.
final pipeline = TransportPipeline(
  encoding: 'json',
  compression: protocol.compression == 'gzip' ? 'auto' : 'none',
  compressionThreshold: protocol.compressionThreshold,
  maxInflationRatio: protocol.maxInflationRatio,
);

var frame = (await pipeline.prepareSendAsync(
  request.toJson(),
  requestId: request.id?.toString(),
  traceId: request.meta?.traceId,
)).getOrThrow();
if (protocol.signatureRequired && signer == null) {
  throw StateError('A signer is required for this session');
}
if (signer != null) {
  final signed = await signer.signFrameAsync(frame);
  frame = frame.copyWith(signature: signed.signature.toJson());
}
if (frame.compressedSize > protocol.effectiveLimits.maxCompressedPayloadBytes ||
    frame.originalSize > protocol.effectiveLimits.maxDecodedPayloadBytes) {
  throw StateError('Payload exceeds negotiated limits');
}

socket.emit('rpc:request', frame.toSocketPayload());

socket.on('rpc:response', (data) async {
  final frame = PayloadFrame.fromJson(Map<String, dynamic>.from(data));
  final signature = frame.signature;
  if (signature != null) {
    if (signer == null ||
        !(await signer.verifyFrameAsyncWithMetrics(
          frame, PayloadSignature.fromJson(signature),
        )).isValid) {
      throw StateError('Invalid frame signature');
    }
  } else if (protocol.signatureRequired) {
    throw StateError('Missing frame signature');
  }
  final responseJson = (await pipeline.receiveProcessAsync(
    frame,
    maxCompressedBytes: protocol.effectiveLimits.maxCompressedPayloadBytes,
    maxOriginalBytes: protocol.effectiveLimits.maxDecodedPayloadBytes,
  )).getOrThrow();
  // processa o envelope logico aqui
});
```

## Ferramentas manuais

Ferramentas que nao conseguem:

- emitir payload binario
- aplicar compressao antes do envio
- reverter decode/descompressao no recebimento

nao sao clientes compativeis com este contrato de transporte.

Postman e ferramentas equivalentes, quando nao conseguem cumprir esse fluxo,
nao devem ser usadas para homologacao do contrato Socket.IO.

## Schema JSON (frame fisico)

Validacao estrutural opcional do envelope:

- `docs/communication/schemas/payload-frame.schema.json`
