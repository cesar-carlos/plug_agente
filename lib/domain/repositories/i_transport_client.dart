import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:result_dart/result_dart.dart';

abstract class ITransportClient {
  /// Initiates the transport connection to [serverUrl].
  ///
  /// Returns `Success` once the socket is connected **and** `agent:register`
  /// has been sent to the hub. This does **not** mean the protocol is ready
  /// for RPC traffic: full readiness (capabilities negotiated) is signalled
  /// by the `HubProtocolReady` notification delivered via [setOnHubLifecycle].
  ///
  /// Callers that need to send RPC requests must wait for `HubProtocolReady`
  /// rather than acting immediately on the `Success` result of `connect`.
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  });
  Future<Result<void>> disconnect();
  Future<Result<void>> sendResponse(QueryResponse response);
  bool get isConnected;
  String get agentId;

  void setMessageCallback(
    void Function(String direction, String event, dynamic data)? callback,
  );

  /// Fired when the transport detects an authentication failure (401 / token
  /// invalid). The callback is fire-and-forget; the caller is responsible for
  /// scheduling the async recovery work without blocking the socket event loop.
  ///
  /// **Contract:** [setOnTokenExpired], [setOnReconnectionNeeded], and
  /// [setOnHubLifecycle] remain registered after [disconnect]. Recovery flows
  /// call [disconnect] before reconnecting; implementations must not clear
  /// these callbacks on disconnect (only [setMessageCallback] / explicit null
  /// may clear them).
  void setOnTokenExpired(void Function()? callback);
  void setOnReconnectionNeeded(void Function()? callback);

  /// Reports hub transport lifecycle after the initial connect Future settles.
  /// Pass null to clear the callback.
  void setOnHubLifecycle(void Function(HubLifecycleNotification notification)? callback);

  /// Optional correlation id appended to `resilience:` transport logs; set by
  /// the connection presentation layer during hub recovery. Pass null to clear.
  void setResilienceLogContext(String? recoveryId);

  /// Optional hook so the dashboard can defer WebSocket log UI work while hub
  /// `sql.execute` is in flight. Default is a no-op for test doubles.
  void setHubSqlDashboardCapturePauseHandler(void Function(bool paused)? handler) {}
}
