import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketDataSource {
  io.Socket createSocket(String url, {String? authToken}) {
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setReconnectionAttempts(5)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setExtraHeaders({'Connection': 'Upgrade'});

    if (authToken != null && authToken.isNotEmpty) {
      options.setAuth({'token': authToken});
    }

    return io.io(url, options.build());
  }
}
