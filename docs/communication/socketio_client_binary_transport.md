# Socket.IO Client Guide (Binary Transport)

## Objetivo

Este guia define o padrao obrigatorio para clientes que publicam ou consomem
eventos Socket.IO do Plug Agente no transporte binario atual.

O documento `docs/communication/socket_communication_standard.md` continua
descrevendo o estado implementado atual do agente. Este guia descreve o
comportamento que clientes devem seguir no contrato de transporte em producao.

## Regra principal

Todo evento de aplicacao deve trafegar em um `PayloadFrame`.

O payload logico JSON-RPC nao deve ser emitido diretamente como objeto JSON em
producao.

## Eventos cobertos

O padrao abaixo se aplica a todos os eventos de aplicacao:

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

- Dart/Flutter: `Uint8List` ou `List<int>`
- Node.js: `Buffer`
- Browser: `Uint8Array` ou `ArrayBuffer`

## Fluxo obrigatorio do emissor

Para qualquer evento de aplicacao:

1. Montar o payload logico do evento.
2. Serializar em JSON UTF-8.
3. Avaliar GZIP quando o tamanho codificado atingir `compressionThreshold`
   (ou sempre que a politica local exigir); no modo automatico, usar GZIP apenas
   se o resultado for menor que os bytes UTF-8.
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
- Nao assumir que toda mensagem vira `gzip`; suportar `cmp: none`.
- Mapear falha de **decode** do conteudo ja descomprimido (ex.: JSON invalido apos `cmp: none` ou apos gunzip) para `-32010`.
- Mapear falha de **compressao/descompressao GZIP** do blob em `payload` para `-32011`.
- Mapear **excesso de payload** / limites negociados para `-32009`.
- Quando o erro for de **encode JSON** do payload logico antes de montar o frame (payload invalido para serializar), mapear para `-32009` (`invalid payload`), nao confundir com `-32011`.

### Implementacao de referencia (Plug Agente, Dart)

- **Wire / `PayloadFrame`:** `TransportPipeline` em `lib/infrastructure/codecs/transport_pipeline.dart`. Para emissao em producao, usar **`prepareSendAsync`** em vez de `prepareSend`, para JSON e gzip grandes poderem correr em isolate.
- **GZIP:** primitivas em `lib/infrastructure/codecs/compression_codec.dart` via **`dart:io` gzip** (zlib da VM), partilhadas com o pipeline e com o compressor de linhas.
- **Segundo formato (nao e o frame):** respostas SQL podem usar `GzipCompressor` (`lib/infrastructure/compression/gzip_compressor.dart`): lista de maps com `compressed_data` (base64) e `is_compressed`; e independente do envelope `PayloadFrame` acima.

## Handshake e capabilities

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

### Preferencia por pedido (`meta.outbound_compression`)

Opcionalmente o hub pode enviar em cada JSON-RPC request `meta.outbound_compression`
com `none`, `gzip` ou `auto`, alinhado a semantica do agente (mesmo significado
que o modo configurado na UI). Isso altera apenas o `PayloadFrame` de **saida**
(`rpc:response`, e `rpc:chunk` / `rpc:complete` ligados ao mesmo `id`). Sem o
campo, aplica-se a politica padrao do agente. O limiar `compressionThreshold`
e a negociacao (`compressions` no handshake) continuam a limitar o que e possivel
no fio. Em batch JSON-RPC, todos os itens que **definirem**
`meta.outbound_compression` devem usar o **mesmo** valor; valores diferentes no
mesmo batch sao rejeitados. Itens **sem** o campo podem coexistir com itens que
o definem desde que exista no maximo **um** valor distinto entre os que o
definem (ex.: um item com `gzip` e os restantes sem `meta.outbound_compression`
aplicam `gzip` ao `PayloadFrame` unico da resposta em batch).

## Assinatura e validacao logica

As regras de schema validation, autorizacao e JSON-RPC continuam valendo sobre
o payload logico apos decode.

A assinatura possui duas camadas possiveis:

- camada principal atual: `frame.signature`, cobrindo metadados do
  `PayloadFrame` e os bytes do payload;
- compatibilidade legada: assinatura no envelope logico JSON, usada apenas
  quando o modo binario estiver desativado.

Ordem recomendada no recebimento:

1. validar frame
2. verificar assinatura do frame
3. descomprimir
4. decodificar JSON
5. validar schema logico
6. despachar o evento

## Ordem opcional em `sql.executeBatch`

No payload logico de `sql.executeBatch`, cada item de `params.commands` pode
incluir `execution_order` (inteiro `>= 0`) para definir a ordem de execucao.

Regras para clientes:

- quando `execution_order` nao for enviado, a execucao segue a ordem natural
  da lista `commands` (comportamento atual);
- quando houver mistura de comandos com e sem `execution_order`, os comandos
  com ordem explicita executam primeiro (ordem crescente) e os sem ordem
  executam depois, mantendo a ordem original da lista;
- quando houver empate de `execution_order`, o desempate segue a ordem original
  da lista;
- `result.items[*].index` continua representando o indice original no array
  `commands`, independentemente da ordem de execucao.

Exemplo de payload logico:

```json
{
  "jsonrpc": "2.0",
  "method": "sql.executeBatch",
  "id": "batch-001",
  "params": {
    "commands": [
      { "sql": "SELECT * FROM users", "execution_order": 2 },
      { "sql": "SELECT COUNT(*) AS total FROM orders", "execution_order": 1 },
      { "sql": "SELECT * FROM products" }
    ]
  }
}
```

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

```js
import { gzipSync, gunzipSync } from "node:zlib";

function encodeFrame(
  message,
  { requestId, traceId, compressionThreshold = 1024 },
) {
  const plainBytes = Buffer.from(JSON.stringify(message), "utf8");
  let cmp = "none";
  let wireBytes = plainBytes;
  if (plainBytes.length >= compressionThreshold) {
    const gz = gzipSync(plainBytes);
    if (gz.length < plainBytes.length) {
      cmp = "gzip";
      wireBytes = gz;
    }
  }

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

function decodeFrame(frame) {
  if (frame.enc !== "json") throw new Error("unsupported encoding");
  if (frame.cmp !== "gzip" && frame.cmp !== "none") {
    throw new Error("unsupported compression");
  }

  const binary = Buffer.from(frame.payload);
  const plainBytes = frame.cmp === "gzip" ? gunzipSync(binary) : binary;
  return JSON.parse(plainBytes.toString("utf8"));
}
```

O exemplo acima segue o modo **automatico** do contrato: acima do limiar, `gzip` so quando o bloco comprimido e **menor** que o JSON UTF-8 bruto; caso contrario `cmp: none` (alinhado ao plug_agente Dart e ao hub `plug_server`).

## Exemplo em Dart

```dart
final pipeline = TransportPipeline(
  encoding: 'json',
  compression: 'gzip',
  compressionThreshold: 1024,
);

final frame = pipeline.prepareSend(
  request.toJson(),
  requestId: request.id?.toString(),
  traceId: request.meta?.traceId,
).getOrThrow();

socket.emit('rpc:request', frame.toJson());

socket.on('rpc:response', (data) {
  final frame = PayloadFrame.fromJson(Map<String, dynamic>.from(data));
  final responseJson = pipeline.receiveProcess(frame).getOrThrow();
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
