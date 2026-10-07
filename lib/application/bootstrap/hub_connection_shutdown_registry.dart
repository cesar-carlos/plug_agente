import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';

/// Mutable holder for the active hub connection lifecycle port.
///
/// Registered in GetIt during dependency setup; a presentation adapter binds on
/// connection provider construction and unbinds on dispose.
class HubConnectionShutdownRegistry {
  IHubConnectionShutdownPort? _port;
  bool _maintenancePaused = false;

  void bind(IHubConnectionShutdownPort port) {
    _port = port;
    if (_maintenancePaused && port is IHubConnectionMaintenancePort) {
      (port as IHubConnectionMaintenancePort).pauseWritersForMaintenance();
    }
  }

  void unbind(IHubConnectionShutdownPort port) {
    if (identical(_port, port)) {
      _port = null;
    }
  }

  bool get hasBoundPort => _port != null;

  bool get maintenanceWritersIdle {
    final port = _port;
    return port == null ||
        (port is IHubConnectionMaintenancePort && (port as IHubConnectionMaintenancePort).maintenanceWritersIdle);
  }

  void pauseWritersForMaintenance() {
    _maintenancePaused = true;
    final port = _port;
    if (port case final IHubConnectionMaintenancePort maintenance) {
      maintenance.pauseWritersForMaintenance();
    }
  }

  void resumeWritersAfterMaintenance() {
    _maintenancePaused = false;
    final port = _port;
    if (port case final IHubConnectionMaintenancePort maintenance) {
      maintenance.resumeWritersAfterMaintenance();
    }
  }

  Future<void> disconnectForShutdown() async {
    final port = _port;
    if (port == null) {
      return;
    }
    await port.disconnectForShutdown();
  }
}
