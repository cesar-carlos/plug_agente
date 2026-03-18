import 'dart:async';
import 'dart:developer' as developer;

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
    unawaited(
      windowManager.show().catchError((Object e, StackTrace? s) {
        developer.log(
          'Tray: failed to show window',
          name: 'tray_service',
          level: 900,
          error: e,
          stackTrace: s,
        );
      }),
    );
    unawaited(
      windowManager.focus().catchError((Object e, StackTrace s) {
        developer.log(
          'Tray: failed to focus window',
          name: 'tray_service',
          level: 900,
          error: e,
          stackTrace: s,
        );
      }),
    );
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(
      trayManager.popUpContextMenu().catchError((Object e, StackTrace? s) {
        developer.log(
          'Tray: failed to pop up context menu',
          name: 'tray_service',
          level: 900,
          error: e,
          stackTrace: s,
        );
      }),
    );
  }
}
