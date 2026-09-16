enum TrayAvailability {
  unsupported,
  initializing,
  ready,
  failed,
}

enum TrayMenuAction { show, exit }

typedef TrayMenuActionHandler = Future<void> Function(TrayMenuAction action);

abstract class ITrayService {
  TrayAvailability get availability;

  bool get isReady;

  Future<void> initialize({
    TrayMenuActionHandler? onMenuAction,
    String showWindowLabel = 'Open Plug Database',
    String exitLabel = 'Exit',
  });

  Future<void> setStatus(String status);

  Future<void> dispose();
}
