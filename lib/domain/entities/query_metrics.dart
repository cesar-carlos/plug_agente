/// Métricas de performance de execução de query.
class QueryMetrics {
  const QueryMetrics({
    required this.queryId,
    required this.query,
    required this.executionDuration,
    required this.rowsAffected,
    required this.columnCount,
    required this.timestamp,
    required this.success,
    this.errorMessage,
  });

  /// Cria métricas de sucesso.
  factory QueryMetrics.success({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required int rowsAffected,
    required int columnCount,
  }) {
    return QueryMetrics(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      rowsAffected: rowsAffected,
      columnCount: columnCount,
      timestamp: DateTime.now(),
      success: true,
    );
  }

  /// Cria métricas de falha.
  factory QueryMetrics.failure({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required String errorMessage,
  }) {
    return QueryMetrics(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      rowsAffected: 0,
      columnCount: 0,
      timestamp: DateTime.now(),
      success: false,
      errorMessage: errorMessage,
    );
  }
  final String queryId;
  final String query;
  final Duration executionDuration;
  final int rowsAffected;
  final int columnCount;
  final DateTime timestamp;
  final bool success;
  final String? errorMessage;

  /// Converte para Map para serialização.
  Map<String, dynamic> toMap() {
    return {
      'queryId': queryId,
      'query': query,
      'executionDurationMs': executionDuration.inMilliseconds,
      'rowsAffected': rowsAffected,
      'columnCount': columnCount,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'errorMessage': errorMessage,
    };
  }

  @override
  String toString() {
    return 'QueryMetrics(id: $queryId, duration: ${executionDuration.inMilliseconds}ms, rows: $rowsAffected, success: $success)';
  }
}

/// Coleção de métricas com estatísticas agregadas.
class MetricsSummary {
  const MetricsSummary({
    required this.totalQueries,
    required this.successfulQueries,
    required this.failedQueries,
    required this.averageExecutionTime,
    required this.maxExecutionTime,
    required this.minExecutionTime,
    required this.totalRowsAffected,
    required this.periodStart,
    required this.periodEnd,
  });

  /// Calcula resumo a partir de lista de métricas.
  factory MetricsSummary.fromList(List<QueryMetrics> metrics) {
    if (metrics.isEmpty) {
      final now = DateTime.now();
      return MetricsSummary(
        totalQueries: 0,
        successfulQueries: 0,
        failedQueries: 0,
        averageExecutionTime: Duration.zero,
        maxExecutionTime: Duration.zero,
        minExecutionTime: Duration.zero,
        totalRowsAffected: 0,
        periodStart: now,
        periodEnd: now,
      );
    }

    final successful = metrics.where((m) => m.success).length;
    final failed = metrics.where((m) => !m.success).length;

    final durations = metrics.map((m) => m.executionDuration);
    final totalDuration = durations.fold(Duration.zero, (sum, d) => sum + d);
    final avgDuration = Duration(
      microseconds: totalDuration.inMicroseconds ~/ metrics.length,
    );

    final maxDuration = durations.reduce((a, b) => a > b ? a : b);
    final minDuration = durations.reduce((a, b) => a < b ? a : b);

    final totalRows = metrics.fold(0, (sum, m) => sum + m.rowsAffected);

    final timestamps = metrics.map((m) => m.timestamp);
    final periodStart = timestamps.reduce((a, b) => a.isBefore(b) ? a : b);
    final periodEnd = timestamps.reduce((a, b) => a.isAfter(b) ? a : b);

    return MetricsSummary(
      totalQueries: metrics.length,
      successfulQueries: successful,
      failedQueries: failed,
      averageExecutionTime: avgDuration,
      maxExecutionTime: maxDuration,
      minExecutionTime: minDuration,
      totalRowsAffected: totalRows,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }
  final int totalQueries;
  final int successfulQueries;
  final int failedQueries;
  final Duration averageExecutionTime;
  final Duration maxExecutionTime;
  final Duration minExecutionTime;
  final int totalRowsAffected;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Taxa de sucesso em百分比.
  double get successRate {
    if (totalQueries == 0) return 0;
    return (successfulQueries / totalQueries) * 100;
  }

  @override
  String toString() {
    return 'MetricsSummary(total: $totalQueries, success: $successRate%, avgTime: ${averageExecutionTime.inMilliseconds}ms)';
  }
}
