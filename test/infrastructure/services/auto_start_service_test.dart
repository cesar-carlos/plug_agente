import 'dart:collection';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_approved_store.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_reader.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_writer.dart';

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

class _FakeStartupApprovedStore implements IStartupApprovedStore {
  _FakeStartupApprovedStore({
    this.readResult = const StartupApprovedReadResult.notPresent(),
    this.writeResult = const StartupApprovedWriteResult.success(),
  });

  StartupApprovedReadResult readResult;
  StartupApprovedWriteResult writeResult;
  var writeEnabledCallCount = 0;

  @override
  StartupApprovedReadResult read({required String valueName}) => readResult;

  @override
  StartupApprovedWriteResult writeEnabled({required String valueName}) {
    writeEnabledCallCount += 1;
    if (writeResult.status == StartupApprovedWriteStatus.success) {
      readResult = const StartupApprovedReadResult.enabled();
    }
    return writeResult;
  }
}

class _FakeRegistryWriter implements IStartupRunValueRegistryWriter {
  _FakeRegistryWriter({
    this.setResult = const StartupRunValueWriteResult.success(),
    this.deleteResult = const StartupRunValueWriteResult.success(),
    this.machineDeleteResult,
  });

  StartupRunValueWriteResult setResult;
  StartupRunValueWriteResult deleteResult;
  StartupRunValueWriteResult? machineDeleteResult;
  final setCalls = <({StartupRegistryScope scope, String valueName, String rawValueData})>[];
  final deleteCalls = <({StartupRegistryScope scope, String valueName})>[];

  @override
  StartupRunValueWriteResult setRunValue({
    required StartupRegistryScope scope,
    required String valueName,
    required String rawValueData,
  }) {
    setCalls.add((scope: scope, valueName: valueName, rawValueData: rawValueData));
    return setResult;
  }

  @override
  StartupRunValueWriteResult deleteRunValue({
    required StartupRegistryScope scope,
    required String valueName,
  }) {
    deleteCalls.add((scope: scope, valueName: valueName));
    if (scope.isMachineScope) {
      return machineDeleteResult ?? deleteResult;
    }
    return deleteResult;
  }
}

const _currentExecutable = r'C:\Program Files\PlugAgente\plug_agente.exe';
const _oldExecutable = r'C:\Old\PlugAgente\plug_agente.exe';

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

    test('should fail with accessDenied when HKCU registry read is denied', () async {
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

    test('should ignore machine-scope accessDenied when querying startup status', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _accessDenied(),
          ),
        ]),
      );

      final result = await service.isEnabled();

      check(result.isSuccess()).isTrue();
      result.fold(
        (enabled) => check(enabled).isTrue(),
        (_) => fail('Expected success'),
      );
    });

    test('should fail with registryReadFailed when HKCU win32 read returns unexpected status', () async {
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

    test('should report disabled when only HKLM is healthy', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hklm: _found(_startupValue(_currentExecutable)),
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

    test('should enable startup in HKCU even when only HKLM is healthy', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(writer.setCalls).length.equals(1);
      check(writer.setCalls.single.scope).equals(StartupRegistryScope.currentUser);
      check(writer.setCalls.single.rawValueData).contains(LaunchArgsConstants.autostartArg);
    });

    test('should repair HKCU when only a healthy HKLM entry exists', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hklm: _found(_startupValue(_currentExecutable)),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration(allowElevation: false);

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry),
        (_) => fail('Expected success'),
      );
      check(writer.setCalls).length.equals(1);
      check(writer.setCalls.single.scope).equals(StartupRegistryScope.currentUser);
    });

    test('should create HKCU entry when ensure finds no startup registry values', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration(allowElevation: false);

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
      check(writer.setCalls).length.equals(1);
    });

    test('should enable startup in HKCU when no entry exists', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );

      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(writer.setCalls).length.equals(1);
      check(writer.setCalls.single.scope).equals(StartupRegistryScope.currentUser);
      check(writer.setCalls.single.rawValueData).contains(LaunchArgsConstants.autostartArg);
    });

    test('should report legacy machine status for duplicate entries without elevation after HKCU ensure', () async {
      final calls = <_ProcessInvocation>[];
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        calls: calls,
        registryWriter: writer,
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

      final result = await service.ensureLaunchConfiguration(
        allowElevation: false,
      );

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry),
        (_) => fail('Expected success'),
      );
      check(calls.where((call) => call.arguments.contains('delete')).length).equals(0);
      check(writer.setCalls).isEmpty();
    });

    test('should remove duplicate HKLM entry when repairing launch configuration', () async {
      final writer = _FakeRegistryWriter();
      final calls = <_ProcessInvocation>[];

      final service = _makeService(
        calls: calls,
        registryWriter: writer,
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
      check(writer.deleteCalls.single.scope).equals(StartupRegistryScope.localMachine);
      check(calls.where((call) => call.arguments.contains('delete'))).isEmpty();
    });

    test(
      'should repair duplicate HKLM entry using elevated registry cmdlet after access denied',
      () async {
        final writer = _FakeRegistryWriter(
          machineDeleteResult: const StartupRunValueWriteResult.accessDenied(5),
        );
        final calls = <_ProcessInvocation>[];
        final results = Queue<ProcessResult>.from([
          ProcessResult(1, 1, '', 'ERROR: Access is denied.'),
          ProcessResult(2, 0, '', ''),
        ]);

        final service = _makeService(
          calls: calls,
          results: results,
          registryWriter: writer,
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
        check(writer.deleteCalls.single.scope).equals(StartupRegistryScope.localMachine);
        final elevatedCall = calls.singleWhere(
          (call) => call.executable == 'powershell' && call.arguments.join(' ').contains('-Verb RunAs'),
        );
        check(elevatedCall.arguments.join(' ')).contains('-EncodedCommand');
        check(elevatedCall.arguments.join(' ')).not((value) => value.contains('reg.exe'));
      },
    );

    test('should return legacy machine status when HKLM delete fails but HKCU is healthy', () async {
      final writer = _FakeRegistryWriter(
        machineDeleteResult: const StartupRunValueWriteResult.accessDenied(5),
      );
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 1, '', 'ERROR: Access is denied.'),
        ProcessResult(2, 1, '', 'ERROR: Access is denied.'),
      ]);

      final service = _makeService(
        results: results,
        registryWriter: writer,
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
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
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
      check(writer.setCalls).length.equals(1);
      check(writer.setCalls.single.rawValueData).contains(_currentExecutable);
    });

    test('should disable startup from HKCU and HKLM using elevation only for HKLM access denied', () async {
      final calls = <_ProcessInvocation>[];
      final writer = _FakeRegistryWriter(
        machineDeleteResult: const StartupRunValueWriteResult.accessDenied(5),
      );
      final results = Queue<ProcessResult>.from([
        ProcessResult(2, 1, '', 'ERROR: Access is denied.'),
        ProcessResult(3, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(writer.deleteCalls).length.equals(2);
      check(writer.deleteCalls.first.scope).equals(StartupRegistryScope.currentUser);
      check(calls.where((call) => call.executable == 'powershell').length).equals(1);
      check(calls.where((call) => call.arguments.join(' ').contains('-Verb RunAs')).length).equals(1);
    });

    test('should disable HKCU only without touching HKLM when machine entries are absent', () async {
      final writer = _FakeRegistryWriter();
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(writer.deleteCalls).length.equals(1);
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test('should ignore machine-scope registry read access denied when disabling without entries', () async {
      final writer = _FakeRegistryWriter(
        machineDeleteResult: const StartupRunValueWriteResult.accessDenied(5),
      );
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from([
        ProcessResult(1, 0, '', 'ERROR: The system was unable to find the specified registry key or value.'),
      ]);
      final service = _makeService(
        calls: calls,
        results: results,
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hklm: _accessDenied(),
          ),
        ]),
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(writer.deleteCalls.single.scope).equals(StartupRegistryScope.localMachine);
      check(calls.where((call) => call.arguments.contains('delete')).length).equals(1);
    });

    test('should classify UAC cancellation by exit code', () async {
      final writer = _FakeRegistryWriter(
        machineDeleteResult: const StartupRunValueWriteResult.accessDenied(5),
      );
      final results = Queue<ProcessResult>.from([
        ProcessResult(2, 5, '', 'ERROR: Access is denied.'),
        ProcessResult(3, 1223, '', ''),
      ]);

      final service = _makeService(
        results: results,
        registryWriter: writer,
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

    test('should classify localized UAC cancellation with accents', () async {
      final writer = _FakeRegistryWriter(
        machineDeleteResult: const StartupRunValueWriteResult.accessDenied(5),
      );
      final results = Queue<ProcessResult>.from([
        ProcessResult(2, 1, '', 'ERRO: Acesso negado.'),
        ProcessResult(3, 1, '', 'A operação foi cancelada pelo usuário.'),
      ]);

      final service = _makeService(
        results: results,
        registryWriter: writer,
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
      final writer = _FakeRegistryWriter(
        setResult: const StartupRunValueWriteResult.accessDenied(5),
      );

      final service = _makeService(
        calls: calls,
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );
      final result = await service.enable();

      check(result.isError()).isTrue();
      check(writer.setCalls).length.equals(1);
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test(
      'should return explicit failure when UAC prompt is cancelled',
      () async {
        final writer = _FakeRegistryWriter(
          machineDeleteResult: const StartupRunValueWriteResult.accessDenied(5),
        );
        final results = Queue<ProcessResult>.from([
          ProcessResult(2, 1, '', 'ERROR: Access is denied.'),
          ProcessResult(3, 1, '', 'The operation was canceled by the user.'),
        ]);

        final service = _makeService(
          results: results,
          registryWriter: writer,
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

    test('should not request UAC when HKCU write succeeds immediately', () async {
      final calls = <_ProcessInvocation>[];
      final writer = _FakeRegistryWriter();

      final service = _makeService(
        calls: calls,
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );
      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test('should repair enabled registry entry missing autostart argument', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
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
      check(writer.setCalls).length.equals(1);
    });

    test('should repair HKCU without UAC when validation forbids elevation', () async {
      final calls = <_ProcessInvocation>[];
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        calls: calls,
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found('"$_currentExecutable"'),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
      );
      final result = await service.ensureLaunchConfiguration(
        allowElevation: false,
      );

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
      check(writer.setCalls).length.equals(1);
      check(calls).isEmpty();
    });

    test('should return failure when post-repair revalidation cannot read HKCU', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found('"$_currentExecutable"'),
          ),
          _registrySnapshot(
            hkcu: _accessDenied(),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration(allowElevation: false);

      check(result.isError()).isTrue();
      result.fold(
        (_) => fail('Expected failure when post-repair validation cannot read HKCU'),
        (failure) {
          check(failure).isA<StartupServiceFailure>();
          check((failure as StartupServiceFailure).startupCode).equals(StartupServiceFailureCode.accessDenied);
        },
      );
    });

    test('should not repair registry entry that already has autostart argument', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
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
      check(writer.setCalls).isEmpty();
    });

    test('should repair registry entry when autostart argument is only a partial token', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
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

    test('should report disabled when StartupApproved blocks a healthy Run entry', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
        startupApprovedStore: _FakeStartupApprovedStore(
          readResult: const StartupApprovedReadResult.disabled(),
        ),
      );

      final result = await service.isEnabled();

      check(result.isSuccess()).isTrue();
      result.fold(
        (enabled) => check(enabled).isFalse(),
        (_) => fail('Expected success'),
      );
    });

    test('should enable StartupApproved when enabling auto-start', () async {
      final approved = _FakeStartupApprovedStore(
        readResult: const StartupApprovedReadResult.disabled(),
      );
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
        startupApprovedStore: approved,
      );

      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(writer.setCalls).length.equals(1);
      check(approved.writeEnabledCallCount).equals(1);
      check(approved.readResult.status).equals(StartupApprovedStatus.enabled);
    });

    test('should repair StartupApproved when Run entry is healthy but blocked', () async {
      final approved = _FakeStartupApprovedStore(
        readResult: const StartupApprovedReadResult.disabled(),
      );
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
          ),
        ]),
        startupApprovedStore: approved,
      );

      final result = await service.ensureLaunchConfiguration(allowElevation: false);

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
      check(writer.setCalls).isEmpty();
      check(approved.writeEnabledCallCount).equals(1);
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

    test('should leave healthy HKCU unchanged when HKLM read is denied without elevation', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _accessDenied(),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration(allowElevation: false);

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.unchanged),
        (_) => fail('Expected success'),
      );
      check(writer.setCalls).isEmpty();
      check(writer.deleteCalls).isEmpty();
    });

    test('should not elevate for unreadable HKLM when HKCU is already healthy', () async {
      final writer = _FakeRegistryWriter(
        deleteResult: const StartupRunValueWriteResult.accessDenied(5),
      );
      final calls = <_ProcessInvocation>[];
      final service = _makeService(
        calls: calls,
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _accessDenied(),
          ),
        ]),
      );

      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.unchanged),
        (_) => fail('Expected success'),
      );
      check(writer.deleteCalls).isEmpty();
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test('should not create missing HKCU entry when createIfMissing is false', () async {
      final writer = _FakeRegistryWriter();
      final service = _makeService(
        registryWriter: writer,
        registrySnapshots: Queue.from([
          _registrySnapshot(),
        ]),
      );

      final result = await service.ensureLaunchConfiguration(
        allowElevation: false,
        createIfMissing: false,
      );

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.unchanged),
        (_) => fail('Expected success'),
      );
      check(writer.setCalls).isEmpty();
    });

    test('should build startup diagnostic report with scope details and StartupApproved state', () async {
      final service = _makeService(
        registrySnapshots: Queue.from([
          _registrySnapshot(
            hkcu: _found(_startupValue(_currentExecutable)),
            hklm: _accessDenied(),
            wow6432: _found(_startupValue(_oldExecutable)),
          ),
        ]),
        startupApprovedStore: _FakeStartupApprovedStore(
          readResult: const StartupApprovedReadResult.disabled(),
        ),
      );
      final result = await service.buildStartupDiagnosticReport();

      check(result.isSuccess()).isTrue();
      result.fold(
        (report) {
          check(report).contains('HKCU');
          check(report).contains('HKLM');
          check(report).contains('Read denied');
          check(report).contains('StartupApproved (HKCU): disabled');
          check(report).contains('StartupApproved blocked by Startup Apps: true');
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
  IStartupRunValueRegistryWriter? registryWriter,
  IStartupApprovedStore? startupApprovedStore,
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
    registryWriter: registryWriter ?? _FakeRegistryWriter(),
    startupApprovedStore: startupApprovedStore ?? _FakeStartupApprovedStore(),
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
