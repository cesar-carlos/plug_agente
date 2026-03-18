abstract class IWindowManagerService {
  Future<void> show();
  void setMinimizeToTray({required bool value});
  void setCloseToTray({required bool value});
}
