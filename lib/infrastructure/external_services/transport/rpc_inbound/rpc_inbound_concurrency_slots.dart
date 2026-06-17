import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';

/// Per-call slot-release flag carried in a Zone so concurrent invocations of
/// deferred slot release do not stomp on each other.
class RpcInboundSlotReleaseState {
  bool released = false;
}

/// Tracks inbound RPC handler concurrency and zone-scoped deferred slot release.
class RpcInboundConcurrencySlots {
  static const slotReleaseZoneKey = #rpcInboundHandlerSlotRelease;

  int _activeRpcHandlers = 0;

  /// Returns `true` if a slot was acquired. Returns `false` when the per-socket
  /// concurrency cap is reached.
  bool tryAcquireSlot() {
    if (_activeRpcHandlers >= ConnectionConstants.maxConcurrentRpcHandlers) {
      return false;
    }
    _activeRpcHandlers++;
    return true;
  }

  void releaseSlot() {
    if (_activeRpcHandlers > 0) {
      _activeRpcHandlers--;
    }
  }

  void releaseDeferredIfPresent() {
    final state = Zone.current[slotReleaseZoneKey];
    if (state is! RpcInboundSlotReleaseState || state.released) {
      return;
    }
    state.released = true;
    releaseSlot();
  }

  Future<T> runWithDeferredSlotRelease<T>(Future<T> Function() action) {
    final state = RpcInboundSlotReleaseState();
    return runZoned(
      () async {
        try {
          return await action();
        } finally {
          releaseDeferredIfPresent();
        }
      },
      zoneValues: <Object, Object?>{slotReleaseZoneKey: state},
    );
  }
}
