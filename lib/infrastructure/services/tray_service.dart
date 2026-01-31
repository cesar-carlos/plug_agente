import 'dart:async';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener {
  Future<void> initialize() async {
    await trayManager.setIcon('assets/icons/icon-512-dark.svg');

    final menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: 'Show Window',
          onClick: (_) async {
            await windowManager.show();
            await windowManager.focus();
          },
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit',
          label: 'Exit',
          onClick: (_) async {
            await trayManager.destroy();
            await windowManager.close();
          },
        ),
      ],
    );

    await trayManager.setContextMenu(menu);

    trayManager.addListener(this);
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(windowManager.show());
    unawaited(windowManager.focus());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }
}
