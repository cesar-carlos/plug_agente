enum TrayMenuAction { show, exit }

abstract class ITrayService {
  Future<void> initialize({
    void Function(TrayMenuAction)? onMenuAction,
    String showWindowLabel = 'Open Plug Database',
    String exitLabel = 'Exit',
  });

  Future<void> setStatus(String status);

  void dispose();
}
