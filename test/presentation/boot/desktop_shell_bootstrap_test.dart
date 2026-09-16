import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/presentation/boot/desktop_shell_bootstrap.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  test('keeps window visible on autostart when tray is unsupported', () async {
    final window = _FakeDesktopWindow();
    final tray = _FakeTrayService(availabilityAfterInitialize: TrayAvailability.unsupported);

    await _bootstrap(window: window, tray: tray, isAutostartLaunch: true).initialize(
      RuntimeCapabilities.degraded(reasons: const ['tray unavailable']),
    );

    expect(window.startMinimized, isFalse);
    expect(window.isVisibleNow, isTrue);
    expect(window.showCalls, 0);
  });

  test('reveals autostart window and disables tray session when tray initialization fails', () async {
    final window = _FakeDesktopWindow();
    final tray = _FakeTrayService(
      throwOnInitialize: true,
      availabilityAfterInitialize: TrayAvailability.failed,
    );

    await _bootstrap(window: window, tray: tray, isAutostartLaunch: true).initialize(
      RuntimeCapabilities.full(),
    );

    expect(window.startMinimized, isTrue);
    expect(window.isVisibleNow, isTrue);
    expect(window.showCalls, 1);
    expect(window.minimizePreferenceCalls, isEmpty);
    expect(window.closePreferenceCalls, isEmpty);
    expect(tray.disposeCalls, 1);
  });

  test('disables every tray behavior when startup application fails partially', () async {
    final window = _FakeDesktopWindow(failCloseToTrayWhenEnabled: true);
    final tray = _FakeTrayService(availabilityAfterInitialize: TrayAvailability.ready);

    await _bootstrap(window: window, tray: tray, isAutostartLaunch: true).initialize(
      RuntimeCapabilities.full(),
    );

    expect(window.startMinimized, isTrue);
    expect(window.isVisibleNow, isTrue);
    expect(window.showCalls, 1);
    expect(window.minimizePreferenceCalls, [true, false]);
    expect(window.closePreferenceCalls, [true, false]);
    expect(tray.disposeCalls, 1);
  });

  test('keeps autostart window hidden with a ready tray and dispatches one show action', () async {
    final window = _FakeDesktopWindow();
    final tray = _FakeTrayService(availabilityAfterInitialize: TrayAvailability.ready);

    await _bootstrap(window: window, tray: tray, isAutostartLaunch: true).initialize(
      RuntimeCapabilities.full(),
    );

    expect(window.startMinimized, isTrue);
    expect(window.isVisibleNow, isFalse);
    expect(window.showCalls, 0);
    expect(window.minimizePreferenceCalls, [true]);
    expect(window.closePreferenceCalls, [true]);
    expect(tray.disposeCalls, 0);

    await tray.dispatch(TrayMenuAction.show);

    expect(window.showCalls, 1);

    await tray.dispatch(TrayMenuAction.exit);

    expect(window.closeCalls, 1);
    expect(tray.disposeCalls, 1);
  });
}

DesktopShellBootstrap _bootstrap({
  required _FakeDesktopWindow window,
  required _FakeTrayService tray,
  required bool isAutostartLaunch,
}) {
  return DesktopShellBootstrap(
    isAutostartLaunch: isAutostartLaunch,
    dependencies: DesktopShellBootstrapDependencies(
      settingsStore: InMemoryAppSettingsStore(),
      trayService: tray,
      notificationService: const _FakeNotificationService(),
      resolveWindowManager: window,
    ),
  );
}

class _FakeDesktopWindow implements IDesktopWindowService {
  _FakeDesktopWindow({this.failCloseToTrayWhenEnabled = false});

  final bool failCloseToTrayWhenEnabled;
  bool isVisibleNow = true;
  bool? startMinimized;
  int showCalls = 0;
  int closeCalls = 0;
  final List<bool> minimizePreferenceCalls = <bool>[];
  final List<bool> closePreferenceCalls = <bool>[];

  @override
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  Future<void> initialize({
    ui.Size? size,
    ui.Size? minimumSize,
    bool center = true,
    String? title,
    bool startMinimized = false,
  }) async {
    this.startMinimized = startMinimized;
    isVisibleNow = !startMinimized;
  }

  @override
  Future<bool> isVisible() async => isVisibleNow;

  @override
  Future<Result<Unit>> setCloseToTray({required bool value}) async {
    closePreferenceCalls.add(value);
    if (failCloseToTrayWhenEnabled && value) {
      return Failure(Exception('preventClose failed'));
    }
    return const Success(unit);
  }

  @override
  Future<Result<Unit>> setMinimizeToTray({required bool value}) async {
    minimizePreferenceCalls.add(value);
    return const Success(unit);
  }

  @override
  Future<void> show() async {
    showCalls += 1;
    isVisibleNow = true;
  }
}

class _FakeTrayService implements ITrayService {
  _FakeTrayService({
    required this.availabilityAfterInitialize,
    this.throwOnInitialize = false,
  });

  final bool throwOnInitialize;
  final TrayAvailability availabilityAfterInitialize;
  TrayMenuActionHandler? _handler;
  TrayAvailability _availability = TrayAvailability.initializing;
  int disposeCalls = 0;

  @override
  TrayAvailability get availability => _availability;

  @override
  bool get isReady => _availability == TrayAvailability.ready;

  @override
  Future<void> initialize({
    TrayMenuActionHandler? onMenuAction,
    String showWindowLabel = 'Open Plug Database',
    String exitLabel = 'Exit',
  }) async {
    if (throwOnInitialize) {
      _availability = TrayAvailability.failed;
      throw StateError('tray init failed');
    }
    _handler = onMenuAction;
    _availability = availabilityAfterInitialize;
  }

  @override
  Future<void> setStatus(String status) async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _availability = TrayAvailability.failed;
  }

  Future<void> dispatch(TrayMenuAction action) async {
    await _handler!(action);
  }
}

class _FakeNotificationService implements INotificationService {
  const _FakeNotificationService();

  @override
  Future<Result<void>> cancel(int id) async => const Success(unit);

  @override
  Future<Result<void>> cancelAll() async => const Success(unit);

  @override
  Future<Result<void>> initialize() async => const Success(unit);

  @override
  Future<Result<void>> schedule({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async => const Success(unit);

  @override
  Future<Result<void>> show({
    required String title,
    required String body,
    String? payload,
  }) async => const Success(unit);
}
