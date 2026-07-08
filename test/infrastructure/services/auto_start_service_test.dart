import 'dart:collection';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_reader.dart';

class _ProcessInvocation {
  _ProcessInvocation({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

class _FakeRegistryReader implements IStartupRunValueRegistryReader {
  _FakeRegistryReader(Queue<Map<StartupRegistryScope, StartupRunValueReadResult>> snapshots) : _snapshots = snapshots;

  final Queue<Map<StartupRegistryScope, StartupRunValueReadResult>> _snapshots;
  Map<StartupRegistryScope, StartupRunValueReadResult> _activeSnapshot = {};
  var _readsInSnapshot = 0;

  @override
  StartupRunValueReadResult read({
    required StartupRegistryScope scope,
    required String valueName,
  }) {
    if (_readsInSnapshot == 0) {
      _activeSnapshot = _snapshots.isNotEmpty ? _snapshots.removeFirst() : {};
    }
    _readsInSnapshot += 1;
    if (_readsInSnapshot >= StartupRegistryScope.values.length) {
      _readsInSnapshot = 0;
    }
    return _activeSnapshot[scope] ?? const StartupRunValueReadResult.notFound();
  }
}

const _currentExecutable = r'C:\Program Files\PlugAgente\plug_agente.exe';
const _oldExecutable = r'C:\Old\PlugAgente\plug_agente.exe';
const _hkcuRunKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _hklmRunKey = r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run';

void main() {
  group('AutoStartService', () {
    test('should detect enabled startup entry in HKCU', () async {
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.isEnabled();

      check(result.isSuccess()).isTrue();
      result.fold(
        (enabled) => check(enabled).isTrue(),
        (_) => fail('Expected success'),
      );
      check(calls).isEmpty();
    });

    test('should fail with accessDenied when registry read is denied', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(hkcu: _accessDenied()),
        ]),
      );

      final result = await service.isEnabled();

      check(result.isError()).isTrue();
      result.fold(
        (_) => fail('Expected failure when registry read is denied'),
        (failure) {
          check(failure).isA<StartupServiceFailure>();
          check((failure as StartupServiceFailure).startupCode).equals(StartupServiceFailureCode.accessDenied);
        },
      );
    });

    test('should fail with registryReadFailed when win32 read returns unexpected status', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(hkcu: _readFailed()),
        ]),
      );

      final result = await service.isEnabled();

      check(result.isError()).isTrue();
      result.fold(
        (_) => fail('Expected failure when registry read fails'),
        (failure) {
          check(failure).isA<StartupServiceFailure>();
          check((failure as StartupServiceFailure).startupCode).equals(StartupServiceFailureCode.registryReadFailed);
        },
      );
    });

    test('should treat notFound registry reads as missing entry', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );

      final result = await service.isEnabled();

      check(result.isSuccess()).isTrue();
      result.fold(
        (enabled) => check(enabled).isFalse(),
        (_) => fail('Expected success'),
      );
    });

    test('should keep valid HKLM entry without creating duplicate HKCU entry', () async {
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(calls.where((call) => call.arguments.contains('add')).length).equals(0);
    });

    test('should enable startup in HKCU when no entry exists', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );

      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      final addCall = calls.singleWhere((call) => call.arguments.contains('add'));
      check(addCall.executable).equals('reg');
      check(addCall.arguments).contains(_hkcuRunKey);
      check(addCall.arguments.join(' ')).contains(LaunchArgsConstants.autostartArg);
    });

    test('should report repair needed for duplicate HKCU and HKLM entries without elevation', () async {
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration(
        allowElevation: false,
      );

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.needsRepair),
        (_) => fail('Expected success'),
      );
      check(calls.where((call) => call.arguments.contains('delete')).length).equals(0);
    });

    test('should remove duplicate HKLM entry when repairing launch configuration', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
      final deleteCall = calls.singleWhere((call) => call.arguments.contains('delete'));
      check(deleteCall.arguments).contains(_hklmRunKey);
    });

    test(
      'should repair duplicate HKLM entry using elevated registry cmdlet after access denied',
      () async {
        final calls = <_ProcessInvocation>[];
        final results = Queue<ProcessResult>.from([
          ProcessResult(1, 1, '', 'ERROR: Access is denied.'),
          ProcessResult(2, 0, '', ''),
        ]);

        final service = _makeService(
          calls: calls,
          results: results,
          registrySnapshots: Queue.from([
            _registrySnapshot(
              hkcu: _found(_startupValue(_currentExecutable)),
              hklm: _found(_startupValue(_currentExecutable)),
            ),
            _registrySnapshot(
              hkcu: _found(_startupValue(_currentExecutable)),
            ),
          ]),
        );

        final result = await service.ensureLaunchConfiguration();

        check(result.isSuccess()).isTrue();
        final elevatedCall = calls.singleWhere(
          (call) => call.executable == 'powershell' && call.arguments.join(' ').contains('-Verb RunAs'),
        );
        check(elevatedCall.arguments.join(' ')).contains('-EncodedCommand');
        check(elevatedCall.arguments.join(' ')).not((value) => value.contains('reg.exe'));
      },
    );

    test('should return legacy machine status when HKLM delete fails but HKCU is healthy', () async {
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 1, '', 'ERROR: Access is denied.'),
        ProcessResult(2, 1, '', 'ERROR: Access is denied.'),
      ]);

      final service = _makeService(
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry),
        (_) => fail('Expected success'),
      );
    });

    test('should repair stale executable path even when autostart argument exists', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_oldExecutable)),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
      final addCall = calls.singleWhere((call) => call.arguments.contains('add'));
      check(addCall.arguments).contains(_hkcuRunKey);
      check(addCall.arguments.join(' ')).contains(_currentExecutable);
    });

    test('should disable startup from HKCU and HKLM using elevation only for HKLM access denied', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
        ProcessResult(2, 1, '', 'ERROR: Access is denied.'),
        ProcessResult(3, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(calls.where((call) => call.executable == 'powershell').length).equals(1);
      check(calls.where((call) => call.arguments.join(' ').contains('-Verb RunAs')).length).equals(1);
    });

    test('should disable HKCU only without touching HKLM when machine entries are absent', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(calls.where((call) => call.arguments.contains('delete')).length).equals(1);
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test('should not ignore machine-scope registry read access denied when disabling', () async {
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hklm: _accessDenied(),
          ),
        ]),
      );

      final result = await service.disable();

      check(result.isError()).isTrue();
      result.fold(
        (_) => fail('Expected failure when registry read is denied'),
        (failure) {
          check(failure).isA<StartupServiceFailure>();
          check((failure as StartupServiceFailure).startupCode).equals(StartupServiceFailureCode.accessDenied);
        },
      );
      check(calls.where((call) => call.arguments.contains('delete')).length).equals(0);
    });

    test('should classify localized UAC cancellation with accents', () async {
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
        ProcessResult(2, 1, '', 'ERRO: Acesso negado.'),
        ProcessResult(3, 1, '', 'A operação foi cancelada pelo usuário.'),
      ]);

      final service = _makeService(
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.disable();

      check(result.isError()).isTrue();
      result.fold(
        (_) => fail('Expected failure when UAC is cancelled'),
        (failure) {
          check(failure).isA<StartupServiceFailure>();
          check((failure as StartupServiceFailure).startupCode).equals(StartupServiceFailureCode.uacCancelled);
        },
      );
    });

    test('should not elevate HKCU add when current-user auto-start write is denied', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 1, '', 'ERROR: Access is denied.'),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );
      final result = await service.enable();

      check(result.isError()).isTrue();
      check(calls.where((call) => call.executable == 'reg').length).equals(1);
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test(
      'should return explicit failure when UAC prompt is cancelled',
      () async {
        final results = Queue<ProcessResult>.from([
          ProcessResult(1, 0, '', ''),
          ProcessResult(2, 1, '', 'ERROR: Access is denied.'),
          ProcessResult(3, 1, '', 'The operation was canceled by the user.'),
        ]);

        final service = _makeService(
          results: results,
          registrySnapshots: Queue.from([
            _registrySnapshot(
              hkcu: _found(_startupValue(_currentExecutable)),
              hklm: _found(_startupValue(_currentExecutable)),
            ),
          ]),
        );
        final result = await service.disable();

        check(result.isError()).isTrue();
        result.fold(
          (_) => fail('Expected failure when UAC is cancelled'),
          (failure) {
            check(failure).isA<StartupServiceFailure>();
            check((failure as StartupServiceFailure).startupCode).equals(StartupServiceFailureCode.uacCancelled);
          },
        );
      },
    );

    test('should not request UAC when reg add succeeds immediately', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );
      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test('should repair enabled registry entry missing autostart argument', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found('"$_currentExecutable"'),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );
      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
      check(calls.where((call) => call.arguments.contains('add')).length).equals(1);
    });

    test('should report repair needed without UAC when validation forbids elevation', () async {
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found('"$_currentExecutable"'),
          ),
        ]),
      );
      final result = await service.ensureLaunchConfiguration(
        allowElevation: false,
      );

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.needsRepair),
        (_) => fail('Expected success'),
      );
      check(calls).isEmpty();
    });

    test('should not repair registry entry that already has autostart argument', () async {
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );
      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.unchanged),
        (_) => fail('Expected success'),
      );
      check(calls).isEmpty();
    });

    test('should repair registry entry when autostart argument is only a partial token', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found('"$_currentExecutable" "${LaunchArgsConstants.autostartArg}-extra"'),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );
      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
    });

    test('should report disabled when registry entry exists but is unhealthy', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found('"$_currentExecutable"'),
          ),
        ]),
      );

      final result = await service.isEnabled();

      check(result.isSuccess()).isTrue();
      result.fold(
        (enabled) => check(enabled).isFalse(),
        (_) => fail('Expected success'),
      );
    });

    test('should report disabled when registry entry targets stale executable', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_oldExecutable)),
          ),
        ]),
      );
      final result = await service.isEnabled();

      check(result.isSuccess()).isTrue();
      result.fold(
        (enabled) => check(enabled).isFalse(),
        (_) => fail('Expected success'),
      );
    });

    test('should detect missing autostart argument for current executable', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found('"$_currentExecutable"'),
          ),
        ]),
      );
      final result = await service.hasRegistryEntryMissingAutostartForCurrentExecutable();

      check(result.isSuccess()).isTrue();
      result.fold(
        (missing) => check(missing).isTrue(),
        (_) => fail('Expected success'),
      );
    });

    test('should build startup diagnostic report with scope details', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_oldExecutable)),
          ),
        ]),
      );
      final result = await service.buildStartupDiagnosticReport();

      check(result.isSuccess()).isTrue();
      result.fold(
        (report) {
          check(report).contains('HKCU');
          check(report).contains('HKLM');
          check(report).contains('Needs repair: true');
        },
        (_) => fail('Expected success'),
      );
    });
  });
}

AutoStartService _makeService({
  List<_ProcessInvocation>? calls,
  Queue<ProcessResult>? results,
  Queue<Map<StartupRegistryScope, StartupRunValueReadResult>>? registrySnapshots,
}) {
  return AutoStartService(
    isWindows: () => true,
    executablePathProvider: () => _currentExecutable,
    registryReader: _FakeRegistryReader(
      registrySnapshots ??
          Queue<Map<StartupRegistryScope, StartupRunValueReadResult>>.from(
            <Map<StartupRegistryScope, StartupRunValueReadResult>>{},
          ),
    ),
    processRunner: (String executable, List<String> arguments) async {
      calls?.add(
        _ProcessInvocation(
          executable: executable,
          arguments: arguments,
        ),
      );
      return results?.removeFirst() ?? ProcessResult(0, 0, '', '');
    },
  );
}

Map<StartupRegistryScope, StartupRunValueReadResult> _registrySnapshot({
  StartupRunValueReadResult? hkcu,
  StartupRunValueReadResult? hklm,
  StartupRunValueReadResult? wow6432,
}) {
  return <StartupRegistryScope, StartupRunValueReadResult>{
    StartupRegistryScope.currentUser: ?hkcu,
    StartupRegistryScope.localMachine: ?hklm,
    StartupRegistryScope.localMachineWow6432: ?wow6432,
  };
}

StartupRunValueReadResult _found(String value) => StartupRunValueReadResult.found(value);

StartupRunValueReadResult _accessDenied() => const StartupRunValueReadResult.accessDenied(5);

StartupRunValueReadResult _readFailed() => const StartupRunValueReadResult.failed(999);

String _startupValue(String executablePath) {
  return '"$executablePath" "${LaunchArgsConstants.autostartArg}"';
}
