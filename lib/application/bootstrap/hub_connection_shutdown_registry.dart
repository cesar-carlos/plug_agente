import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';

/// Mutable holder for the active hub connection lifecycle port.
///
/// Registered in GetIt during dependency setup; a presentation adapter binds on
/// connection provider construction and unbinds on dispose.
class HubConnectionShutdownRegistry {
  IHubConnectionShutdownPort? _port;

  void bind(IHubConnectionShutdownPort port) {
    _port = port;
  }

  void unbind(IHubConnectionShutdownPort port) {
    if (identical(_port, port)) {
      _port = null;
    }
  }

  bool get hasBoundPort => _port != null;

  Future<void> disconnectForShutdown() async {
    final port = _port;
    if (port == null) {
      return;
    }
    await port.disconnectForShutdown();
  }
}
