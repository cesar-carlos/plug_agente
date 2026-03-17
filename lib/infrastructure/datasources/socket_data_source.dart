import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketDataSource {
  io.Socket createSocket(String url, {String? authToken}) {
    final socketUrl = ensureAgentsNamespaceUrl(url);
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .setRememberUpgrade(true)
        .setTimeout(10000)
        .setAckTimeout(8000)
        .setReconnectionAttempts(15)
        .setReconnectionDelay(5000)
        .setReconnectionDelayMax(60000)
        .setRandomizationFactor(0.2)
        .setExtraHeaders({'Connection': 'Upgrade'});

    if (authToken != null && authToken.isNotEmpty) {
      options.setAuth({'token': authToken});
    }

    return io.io(socketUrl, options.build());
  }
}
