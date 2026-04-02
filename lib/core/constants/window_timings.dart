class WindowTimings {
  WindowTimings._();

  static const Duration showInitialDelay = Duration(milliseconds: 100);
  static const Duration showRestoreDelay = Duration(milliseconds: 200);
  static const Duration showFinalDelay = Duration(milliseconds: 300);

  static const int startupHideRetryCount = 5;
  static const Duration startupHideRetryDelay = Duration(milliseconds: 150);

  static const Duration trayInitDelay = Duration(milliseconds: 100);
  static const Duration trayContextMenuDelay = Duration(milliseconds: 50);
  static const Duration trayIconClickDelay = Duration(milliseconds: 200);
  static const Duration trayInteractionWarmupDelay = Duration(
    milliseconds: 1200,
  );
}
