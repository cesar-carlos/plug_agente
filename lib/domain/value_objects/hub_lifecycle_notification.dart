/// Returns true when the Socket.IO disconnect reason is `io server disconnect`
/// (hub closed the socket). Other reasons (for example `transport close`) are
/// typically handled by transport-level auto reconnect.
bool isHubIoServerInitiatedDisconnect(String? reason) => reason?.toLowerCase() == 'io server disconnect';

/// Notifications emitted by the hub transport **after** the initial connect
/// transport Future completes.
///
/// Initial transport connect success or failure is reported via that Future's
/// result. These variants describe protocol readiness and later transport-only
/// events (for example Socket.IO disconnect / automatic reconnect).
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

/// The hub accepted the agent capabilities and the effective protocol is ready
/// for application-level RPC traffic.
final class HubProtocolReady extends HubLifecycleNotification {
  const HubProtocolReady();
}

/// Automatic reconnect succeeded after a prior disconnect in the same session,
/// once protocol capabilities are negotiated with the hub.
final class HubTransportAutoReconnectSucceeded extends HubLifecycleNotification {
  const HubTransportAutoReconnectSucceeded();
}
