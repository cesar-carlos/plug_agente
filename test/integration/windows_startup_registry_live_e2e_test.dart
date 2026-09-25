import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_approved_store.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_reader.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_writer.dart';

import '../helpers/e2e_env.dart';

/// Exercises the Win32 registry adapters against the real registry.
///
/// Uses a unique value name per test so the installed "Plug Agente" entry is
/// never read, written, or deleted.
void main() async {
  await E2EEnv.load();
  final skip = E2EEnv.liveStartupRegistrySkipMessage;

  group('Windows startup registry (live)', () {
    const reader = Win32StartupRunValueRegistryReader();
    const writer = Win32StartupRunValueRegistryWriter();
    const approvedStore = Win32StartupApprovedStore();
    const currentUser = StartupRegistryScope.currentUser;
    late String valueName;

    setUp(() {
      valueName = 'PlugAgenteE2E-$pid-${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() {
        writer.deleteRunValue(scope: currentUser, valueName: valueName);
        approvedStore.delete(valueName: valueName);
      });
    });

    test('writes, reads back, and deletes an HKCU Run value', () {
      const executable = r'C:\Program Files\Plug Agente\plug_agente.exe';
      const rawValue = '"$executable" "${LaunchArgsConstants.autostartArg}"';

      expect(
        writer.setRunValue(scope: currentUser, valueName: valueName, rawValueData: rawValue).status,
        StartupRunValueWriteStatus.success,
      );

      final read = reader.read(scope: currentUser, valueName: valueName);
      expect(read.status, StartupRunValueReadStatus.found);
      expect(read.value, rawValue);
      final entry = StartupRegistryEntry.fromRawValue(scope: currentUser, valueName: valueName, rawValue: read.value!);
      expect(entry?.isHealthyFor(executable), isTrue);

      expect(
        writer.deleteRunValue(scope: currentUser, valueName: valueName).status,
        StartupRunValueWriteStatus.success,
      );
      expect(reader.read(scope: currentUser, valueName: valueName).status, StartupRunValueReadStatus.notFound);
      expect(
        writer.deleteRunValue(scope: currentUser, valueName: valueName).status,
        StartupRunValueWriteStatus.success,
      );
    }, skip: skip);

    test('expands REG_EXPAND_SZ Run values written by other tools', () async {
      final addResult = await Process.run('reg', <String>[
        'add',
        currentUser.runKeyPath,
        '/v',
        valueName,
        '/t',
        'REG_EXPAND_SZ',
        '/d',
        r'%SystemRoot%\system32\cmd.exe --autostart',
        '/f',
      ]);
      expect(addResult.exitCode, 0, reason: '${addResult.stderr}');

      final read = reader.read(scope: currentUser, valueName: valueName);

      expect(read.status, StartupRunValueReadStatus.found);
      expect(
        read.value?.toLowerCase(),
        '${Platform.environment['SystemRoot']}\\system32\\cmd.exe --autostart'.toLowerCase(),
      );
    }, skip: skip);

    test('enables and removes the StartupApproved overlay', () {
      expect(approvedStore.read(valueName: valueName).status, StartupApprovedStatus.notPresent);

      expect(approvedStore.writeEnabled(valueName: valueName).status, StartupApprovedWriteStatus.success);
      final enabled = approvedStore.read(valueName: valueName);
      expect(enabled.status, StartupApprovedStatus.enabled);
      expect(enabled.rawBytes, StartupApprovedBinary.enabledPayload);

      expect(approvedStore.delete(valueName: valueName).status, StartupApprovedWriteStatus.success);
      expect(approvedStore.read(valueName: valueName).status, StartupApprovedStatus.notPresent);
    }, skip: skip);

    test('reports machine scopes as missing or denied instead of failing', () {
      for (final scope in StartupRegistryScope.machineScopes) {
        expect(
          reader.read(scope: scope, valueName: valueName).status,
          isIn(<StartupRunValueReadStatus>[StartupRunValueReadStatus.notFound, StartupRunValueReadStatus.accessDenied]),
          reason: scope.label,
        );
        expect(
          writer.deleteRunValue(scope: scope, valueName: valueName).status,
          isIn(<StartupRunValueWriteStatus>[
            StartupRunValueWriteStatus.success,
            StartupRunValueWriteStatus.notFound,
            StartupRunValueWriteStatus.accessDenied,
          ]),
          reason: scope.label,
        );
      }
    }, skip: skip);
  });
}
