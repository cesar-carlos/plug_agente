import 'dart:async';
import 'package:plug_agente/domain/repositories/i_pending_silent_update_store.dart';

/// Serializes local transitions sharing the same pending repository.
class UpdateTransitionGate {
  static final _gates = Expando<UpdateTransitionGate>();
  static UpdateTransitionGate forStore(IPendingSilentUpdateStore store) => _gates[store] ??= UpdateTransitionGate();
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        completed.complete();
      }
    })();
  }
}
