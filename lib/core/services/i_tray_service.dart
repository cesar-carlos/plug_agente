enum TrayMenuAction { show, exit }

abstract class ITrayService {
  Future<void> initialize({
    void Function(TrayMenuAction)? onMenuAction,
  });

  Future<void> setStatus(String status);

  void dispose();
}
