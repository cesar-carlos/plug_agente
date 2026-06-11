import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/domain/entities/sql_command.dart' show SqlCommand, SqlExecutionOptions;
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

final class OdbcBatchTransactionSupport {
  const OdbcBatchTransactionSupport({
    required MetricsCollector metrics,
  }) : _metrics = metrics;

  final MetricsCollector _metrics;

  TransactionAccessMode inferBatchAccessMode(List<SqlCommand> commands) {
    if (commands.isEmpty) {
      return TransactionAccessMode.readWrite;
    }
    for (final command in commands) {
      if (SqlValidator.validateSelectQuery(command.sql).isError()) {
        return TransactionAccessMode.readWrite;
      }
    }
    _metrics.recordTransactionalBatchReadOnlyInference();
    return TransactionAccessMode.readOnly;
  }

  void maybeRecordTransactionalBatchDeadlineNearStall({
    required DateTime? deadline,
    required Duration? effectiveTimeout,
    required int commandCount,
  }) {
    if (deadline == null || effectiveTimeout == null || effectiveTimeout <= Duration.zero) {
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return;
    }
    final budgetMicros = effectiveTimeout.inMicroseconds;
    if (budgetMicros <= 0) {
      return;
    }
    final consumedRatio = 1 - (remaining.inMicroseconds / budgetMicros);
    if (consumedRatio < 0.8) {
      return;
    }
    _metrics.recordTransactionalBatchDeadlineNearStall();
    developer.log(
      'Transactional batch reached commit near deadline',
      name: 'database_gateway',
      level: 900,
      error: <String, Object?>{
        'consumed_ratio': consumedRatio,
        'remaining_ms': remaining.inMilliseconds,
        'effective_timeout_ms': effectiveTimeout.inMilliseconds,
        'command_count': commandCount,
        'suggestion':
            'Increase SqlExecutionOptions.timeoutMs or split the batch '
            'to avoid locks lingering through the rollback window.',
      },
    );
  }

  Duration? timeoutFromSqlExecutionOptions(SqlExecutionOptions options) {
    if (options.timeoutMs <= 0) {
      return null;
    }
    return Duration(milliseconds: options.timeoutMs);
  }

  Duration? transactionLockTimeout({
    required SqlExecutionOptions options,
    required Duration? timeout,
  }) {
    return timeout ?? timeoutFromSqlExecutionOptions(options);
  }
}
