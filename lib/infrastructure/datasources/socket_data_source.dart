import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketDataSource {
  io.Socket createSocket(
    String url, {
    String? authToken,
    String? Function()? authTokenProvider,
  }) {
    final socketUrl = ensureAgentsNamespaceUrl(url);
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .setTimeout(ConnectionConstants.socketConnectionTimeoutMs)
        .setAckTimeout(ConnectionConstants.socketAckTimeoutMs)
        .setReconnectionAttempts(ConnectionConstants.socketReconnectionAttempts)
        .setReconnectionDelay(ConnectionConstants.socketReconnectionDelayMs)
        .setReconnectionDelayMax(
          ConnectionConstants.socketReconnectionDelayMaxMs,
        )
        .setRandomizationFactor(0.2)
        .setExtraHeaders({'Connection': 'Upgrade'});

    // Prefer setAuthFn so Socket.IO L0 reconnect can read the current JWT.
    // A new token is still applied on full reconnect (createSocket) after
    // disconnect+connect (HubProactiveTokenRefresh / recovery).
    if (authTokenProvider != null || (authToken != null && authToken.isNotEmpty)) {
      options.setAuthFn((callback) {
        final token = (authTokenProvider?.call() ?? authToken)?.trim();
        if (token != null && token.isNotEmpty) {
          callback({'token': token});
        } else {
          callback(<String, String>{});
        }
      });
    }

    return io.io(socketUrl, options.build());
  }
}
