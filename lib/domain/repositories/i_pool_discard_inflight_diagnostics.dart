/// Diagnostics for asynchronous pooled-connection discards started on the hot path.
abstract class IPoolDiscardInflightDiagnostics {
  int get poolDiscardInflightCount;

  Future<void> reconcilePoolDiscardInflight();
}
