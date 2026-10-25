import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/installation_preparation_service.dart';
import 'package:plug_agente/infrastructure/services/windows_installation_preparation_monitor.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  const channel = MethodChannel('fixture/installation');
  const operation = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  testWidgets('lost status report blocks close and never replays preparation', (tester) async {
    var prepares = 0;
    var closes = 0;
    var delivered = false;
    var enabled = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'enable':
          enabled++;
          return true;
        case 'cancelled':
          return false;
        case 'poll':
          if (delivered) return '';
          delivered = true;
          return operation;
        case 'report':
          throw PlatformException(code: 'lost');
      }
      return null;
    });
    final monitor = WindowsInstallationPreparationMonitor(
      InstallationPreparationService(
        prepareMaintenance: (_) async {
          prepares++;
          return const Success(unit);
        },
        closeApplication: () async {
          closes++;
        },
        cancelMaintenance: () {},
      ),
      channel: channel,
    );
    await Future.wait([monitor.start(), monitor.start()]);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    monitor.stop();
    expect(prepares, 1);
    expect(enabled, 1);
    expect(closes, 0);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('dispose during poll cannot start late maintenance', (tester) async {
    final pending = Completer<String>();
    var prepares = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'enable') return true;
      if (call.method == 'poll') return pending.future;
      return false;
    });
    final monitor = WindowsInstallationPreparationMonitor(
      InstallationPreparationService(
        prepareMaintenance: (_) async {
          prepares++;
          return const Success(unit);
        },
        closeApplication: () async {},
        cancelMaintenance: () {},
      ),
      channel: channel,
    );
    await monitor.start();
    await tester.pump(const Duration(milliseconds: 200));
    monitor.stop();
    pending.complete(operation);
    await tester.pump();
    expect(prepares, 0);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
