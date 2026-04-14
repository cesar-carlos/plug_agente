/// Notifications emitted by the hub transport **after** the initial connect
/// handshake Future completes.
///
/// Initial connect success or failure is reported only via that Future's
/// result. These variants describe later transport-only events (for example
/// Socket.IO disconnect / automatic reconnect).
sealed class HubLifecycleNotification {
  const HubLifecycleNotification();
}

/// The transport socket disconnected (e.g. network loss, server restart).
final class HubTransportDisconnected extends HubLifecycleNotification {
  const HubTransportDisconnected({this.reason});

  /// Opaque reason from the underlying client, when available.
  final String? reason;
}

/// Socket.IO is attempting to reconnect (transport-level attempt counter when known).
final class HubTransportReconnectAttempt extends HubLifecycleNotification {
  const HubTransportReconnectAttempt({this.attemptNumber});

  final int? attemptNumber;
}

/// Automatic reconnect succeeded after a prior disconnect in the same session,
/// once protocol capabilities are negotiated with the hub.
final class HubTransportAutoReconnectSucceeded extends HubLifecycleNotification {
  const HubTransportAutoReconnectSucceeded();
}
