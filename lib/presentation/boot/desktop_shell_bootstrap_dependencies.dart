import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';

typedef WindowManagerRegistrar = void Function(
  WindowManagerService service,
  IWindowManagerService interface,
);

final class DesktopShellBootstrapDependencies {
  const DesktopShellBootstrapDependencies({
    required this.settingsStore,
    required this.trayService,
    required this.notificationService,
    this.registerWindowManager,
  });

  final IAppSettingsStore settingsStore;
  final ITrayService trayService;
  final INotificationService notificationService;
  final WindowManagerRegistrar? registerWindowManager;
}
