/// One streaming ODBC chunk ready for Hub framing.
final class StreamingWireChunk {
  const StreamingWireChunk({
    required this.rows,
    this.columnar,
    this.resultSetIndex,
    this.multiResultItemIndex,
    this.rowCountOnly,
  });

  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? columnar;
  final int? resultSetIndex;
  final int? multiResultItemIndex;

  /// When set, the chunk represents a DML row-count item in a multi-result batch.
  final int? rowCountOnly;
}
