/// Operation classes for partitioning the direct ODBC connection limiter.
enum DirectOdbcOperationClass {
  streaming,
  bulk,
  batchTransaction,
  general;

  String get healthKey => switch (this) {
    DirectOdbcOperationClass.streaming => 'streaming',
    DirectOdbcOperationClass.bulk => 'bulk',
    DirectOdbcOperationClass.batchTransaction => 'batch_transaction',
    DirectOdbcOperationClass.general => 'general',
  };

  static DirectOdbcOperationClass fromOperation(String operation) {
    return switch (operation) {
      'streaming_query' => DirectOdbcOperationClass.streaming,
      'bulk_insert_direct' => DirectOdbcOperationClass.bulk,
      'batch_transaction' => DirectOdbcOperationClass.batchTransaction,
      _ => DirectOdbcOperationClass.general,
    };
  }
}
