import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';

final class DesktopShellBootstrapDependencies {
  const DesktopShellBootstrapDependencies({
    required this.settingsStore,
    required this.trayService,
    required this.notificationService,
    this.resolveWindowManager,
  });

  final IAppSettingsStore settingsStore;
  final ITrayService trayService;
  final INotificationService notificationService;
  final WindowManagerService? resolveWindowManager;
}
