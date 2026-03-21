/// Payload for rpc:chunk event.
class RpcStreamChunk {
  const RpcStreamChunk({
    required this.streamId,
    required this.requestId,
    required this.chunkIndex,
    required this.rows,
    this.totalChunks,
    this.columnMetadata,
  });

  factory RpcStreamChunk.fromJson(Map<String, dynamic> json) => RpcStreamChunk(
    streamId: json['stream_id'] as String,
    requestId: json['request_id'],
    chunkIndex: json['chunk_index'] as int,
    rows: (json['rows'] as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList(),
    totalChunks: json['total_chunks'] as int?,
    columnMetadata: (json['column_metadata'] as List<dynamic>?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList(),
  );

  final String streamId;
  final dynamic requestId;
  final int chunkIndex;
  final List<Map<String, dynamic>> rows;
  final int? totalChunks;
  final List<Map<String, dynamic>>? columnMetadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'stream_id': streamId,
    'request_id': requestId?.toString(),
    'chunk_index': chunkIndex,
    'rows': rows,
    if (totalChunks != null) 'total_chunks': totalChunks,
    if (columnMetadata != null) 'column_metadata': columnMetadata,
  };
}

/// Payload for rpc:complete event.
class RpcStreamComplete {
  const RpcStreamComplete({
    required this.streamId,
    required this.requestId,
    required this.totalRows,
    this.affectedRows,
    this.executionId,
    this.startedAt,
    this.finishedAt,
    this.terminalStatus,
  });

  factory RpcStreamComplete.fromJson(Map<String, dynamic> json) =>
      RpcStreamComplete(
        streamId: json['stream_id'] as String,
        requestId: json['request_id'],
        totalRows: json['total_rows'] as int,
        affectedRows: json['affected_rows'] as int?,
        executionId: json['execution_id'] as String?,
        startedAt: json['started_at'] as String?,
        finishedAt: json['finished_at'] as String?,
        terminalStatus: json['terminal_status'] as String?,
      );

  /// Abnormal stream end: backpressure / overflow before full delivery.
  static const String terminalStatusAborted = 'aborted';

  /// Abnormal stream end: database or transport error after partial delivery.
  static const String terminalStatusError = 'error';

  final String streamId;
  final dynamic requestId;
  final int totalRows;
  final int? affectedRows;
  final String? executionId;
  final String? startedAt;
  final String? finishedAt;

  /// When set (`aborted` or `error`), the hub should treat the stream as
  /// closed even though the matching `rpc:response` may be an error.
  final String? terminalStatus;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'stream_id': streamId,
    'request_id': requestId?.toString(),
    'total_rows': totalRows,
    if (affectedRows != null) 'affected_rows': affectedRows,
    if (executionId != null) 'execution_id': executionId,
    if (startedAt != null) 'started_at': startedAt,
    if (finishedAt != null) 'finished_at': finishedAt,
    if (terminalStatus != null) 'terminal_status': terminalStatus,
  };
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
