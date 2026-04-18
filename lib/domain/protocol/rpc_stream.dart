/// Terminal status for rpc:complete when a stream ends without full success.
///
/// JSON-RPC 2.0 does not define stream lifecycle, so we extend `rpc:complete`
/// with an optional `terminal_status` field to give the hub a deterministic
/// close signal when chunks were already partially sent.
enum StreamTerminalStatus {
  /// Stream was cancelled due to backpressure overflow or producer abort.
  aborted,

  /// Stream was interrupted by an execution error (e.g. ODBC failure).
  error
  ;

  String toJson() => name;

  static StreamTerminalStatus fromJson(String value) => StreamTerminalStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => StreamTerminalStatus.error,
  );
}

/// Payload for rpc:chunk event.
class RpcStreamChunk {
  /// Streams must always carry a [requestId]. Notifications (id null) cannot
  /// trigger streams, so an orphan chunk is a programmer bug — the constructor
  /// asserts in dev/test builds and `toJson` validates the wire contract
  /// (the schema requires a string `request_id`).
  // The assert documents the invariant: requestId must not be null. Tightening
  // the parameter to a non-nullable type is impractical because JSON-RPC `id`
  // is `String | int | null` and we keep `dynamic` for fromJson compatibility.
  RpcStreamChunk({
    required this.streamId,
    // ignore: tighten_type_of_initializing_formals
    required this.requestId,
    required this.chunkIndex,
    required this.rows,
    this.totalChunks,
    this.columnMetadata,
  }) : assert(requestId != null, 'RpcStreamChunk.requestId must not be null');

  factory RpcStreamChunk.fromJson(Map<String, dynamic> json) => RpcStreamChunk(
    streamId: json['stream_id'] as String,
    requestId: json['request_id'],
    chunkIndex: json['chunk_index'] as int,
    rows: (json['rows'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList(),
    totalChunks: json['total_chunks'] as int?,
    columnMetadata: (json['column_metadata'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList(),
  );

  final String streamId;
  final dynamic requestId;
  final int chunkIndex;
  final List<Map<String, dynamic>> rows;
  final int? totalChunks;
  final List<Map<String, dynamic>>? columnMetadata;

  Map<String, dynamic> toJson() {
    if (requestId == null) {
      throw StateError(
        'RpcStreamChunk.toJson requires a non-null requestId; orphan chunks are a bug.',
      );
    }
    return <String, dynamic>{
      'stream_id': streamId,
      'request_id': requestId.toString(),
      'chunk_index': chunkIndex,
      'rows': rows,
      if (totalChunks != null) 'total_chunks': totalChunks,
      if (columnMetadata != null) 'column_metadata': columnMetadata,
    };
  }
}

/// Payload for rpc:complete event.
class RpcStreamComplete {
  /// Mirror of [RpcStreamChunk.requestId]: streams require a [requestId];
  /// orphan completes are a programmer bug.
  RpcStreamComplete({
    required this.streamId,
    // JSON-RPC 2.0 allows string or number for `id`; dynamic preserves both.
    // ignore: tighten_type_of_initializing_formals
    required this.requestId,
    required this.totalRows,
    this.affectedRows,
    this.executionId,
    this.startedAt,
    this.finishedAt,
    this.terminalStatus,
  }) : assert(requestId != null, 'RpcStreamComplete.requestId must not be null');

  factory RpcStreamComplete.fromJson(Map<String, dynamic> json) => RpcStreamComplete(
    streamId: json['stream_id'] as String,
    requestId: json['request_id'],
    totalRows: json['total_rows'] as int,
    affectedRows: json['affected_rows'] as int?,
    executionId: json['execution_id'] as String?,
    startedAt: json['started_at'] as String?,
    finishedAt: json['finished_at'] as String?,
    terminalStatus: json['terminal_status'] != null
        ? StreamTerminalStatus.fromJson(
            json['terminal_status'] as String,
          )
        : null,
  );

  final String streamId;
  final dynamic requestId;
  final int totalRows;
  final int? affectedRows;
  final String? executionId;
  final String? startedAt;
  final String? finishedAt;

  /// Present only when the stream ended without full success.
  /// Absent on normal completion so hubs can treat null as success.
  final StreamTerminalStatus? terminalStatus;

  Map<String, dynamic> toJson() {
    if (requestId == null) {
      throw StateError(
        'RpcStreamComplete.toJson requires a non-null requestId; orphan completes are a bug.',
      );
    }
    return <String, dynamic>{
      'stream_id': streamId,
      'request_id': requestId.toString(),
      'total_rows': totalRows,
      if (affectedRows != null) 'affected_rows': affectedRows,
      if (executionId != null) 'execution_id': executionId,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (terminalStatus != null) 'terminal_status': terminalStatus!.toJson(),
    };
  }
}

/// Payload for rpc:stream.pull (client requests more chunks).
class RpcStreamPull {
  const RpcStreamPull({
    required this.streamId,
    this.windowSize = 1,
  });

  factory RpcStreamPull.fromJson(Map<String, dynamic> json) => RpcStreamPull(
    streamId: json['stream_id'] as String,
    windowSize: json['window_size'] as int? ?? 1,
  );

  final String streamId;
  final int windowSize;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'stream_id': streamId,
    'window_size': windowSize,
  };
}
