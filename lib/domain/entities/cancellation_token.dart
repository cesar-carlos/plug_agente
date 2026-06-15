import 'dart:async';

/// Token de cancelamento para operações assíncronas.
///
/// Permite sinalizar cancelamento de operações em andamento.
/// A operação deve periodicamente verificar [isCancelled] e abortar se true.
class CancellationToken {
  bool _isCancelled = false;
  final List<Completer<void>> _cancelWaiters = <Completer<void>>[];

  /// Indica se a operação foi cancelada.
  bool get isCancelled => _isCancelled;

  /// Completes when [cancel] is called. Resolves immediately if already cancelled.
  Future<void> get whenCancelled {
    if (_isCancelled) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _cancelWaiters.add(waiter);
    return waiter.future;
  }

  /// Cancela a operação.
  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final waiters = List<Completer<void>>.of(_cancelWaiters);
    _cancelWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  /// Restaura o token para o estado não cancelado.
  void reset() {
    _isCancelled = false;
  }

  /// Lança [CancellationException] se a operação foi cancelada.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const CancellationException('Operation was cancelled');
    }
  }
}

/// Exceção lançada quando uma operação é cancelada.
class CancellationException implements Exception {
  const CancellationException(this.message);
  final String message;

  @override
  String toString() => 'CancellationException: $message';
}
