/// Token de cancelamento para operações assíncronas.
///
/// Permite sinalizar cancelamento de operações em andamento.
/// A operação deve periodicamente verificar [isCancelled] e abortar se true.
class CancellationToken {
  bool _isCancelled = false;

  /// Indica se a operação foi cancelada.
  bool get isCancelled => _isCancelled;

  /// Cancela a operação.
  void cancel() {
    _isCancelled = true;
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
