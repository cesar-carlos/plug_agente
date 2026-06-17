import 'dart:collection';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';

class _ProcessInvocation {
  _ProcessInvocation({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

const _currentExecutable = r'C:\Program Files\PlugAgente\plug_agente.exe';
const _oldExecutable = r'C:\Old\PlugAgente\plug_agente.exe';
const _hkcuRunKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _hklmRunKey = r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run';
const _hklmWowRunKey = r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';

void main() {
  group('AutoStartService', () {
    test('should detect enabled startup entry in HKCU', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(
        _queries(hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable))),
      );

      final service = _makeService(
        calls: calls,
        results: results,
      );

      final result = await service.isEnabled();

      check(result.isSuccess()).isTrue();
      result.fold(
        (enabled) => check(enabled).isTrue(),
        (_) => fail('Expected success'),
      );
      check(calls.length).equals(3);
      check(calls[0].arguments).contains(_hkcuRunKey);
      check(calls[1].arguments).contains(_hklmRunKey);
      check(calls[2].arguments).contains(_hklmWowRunKey);
    });

    test('should keep valid HKLM entry without creating duplicate HKCU entry', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(
        _queries(hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable))),
      );

      final service = _makeService(
        calls: calls,
        results: results,
      );

      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(calls.where((call) => call.arguments.contains('add')).length).equals(0);
    });

    test('should enable startup in HKCU when no entry exists', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(),
        ProcessResult(3, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
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
      final results = Queue<ProcessResult>.from(
        _queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
          hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
        ),
      );

      final service = _makeService(
        calls: calls,
        results: results,
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
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
          hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
        ),
        ProcessResult(3, 0, '', ''),
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        ),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
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
        final results = Queue<ProcessResult>.from(<ProcessResult>[
          ..._queries(
            hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
            hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
          ),
          ProcessResult(3, 1, '', 'ERROR: Access is denied.'),
          ProcessResult(4, 0, '', ''),
          ..._queries(
            hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
          ),
        ]);

        final service = _makeService(
          calls: calls,
          results: results,
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
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
          hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
        ),
        ProcessResult(3, 1, '', 'ERROR: Access is denied.'),
        ProcessResult(4, 1, '', 'ERROR: Access is denied.'),
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
          hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
        ),
      ]);

      final service = _makeService(results: results);

      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repairedWithLegacyMachineEntry),
        (_) => fail('Expected success'),
      );
    });

    test('should repair stale executable path even when autostart argument exists', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(hkcu: _querySuccess(_hkcuRunKey, _startupValue(_oldExecutable))),
        ProcessResult(3, 0, '', ''),
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        ),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
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
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
          hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
        ),
        ProcessResult(3, 0, '', ''),
        ProcessResult(4, 1, '', 'ERROR: Access is denied.'),
        ProcessResult(5, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(calls.where((call) => call.executable == 'powershell').length).equals(1);
      check(calls.where((call) => call.arguments.join(' ').contains('-Verb RunAs')).length).equals(1);
    });

    test('should disable HKCU only without touching HKLM when machine entries are absent', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable))),
        ProcessResult(3, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(calls.where((call) => call.arguments.contains('delete')).length).equals(1);
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test('should classify localized UAC cancellation with accents', () async {
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable))),
        ProcessResult(2, 1, '', 'ERRO: Acesso negado.'),
        ProcessResult(3, 1, '', 'A operação foi cancelada pelo usuário.'),
      ]);

      final service = _makeService(results: results);

      final result = await service.disable();

      check(result.isError()).isTrue();
      result.fold(
        (_) => fail('Expected failure when UAC is cancelled'),
        (failure) {
          check(failure).isA<StartupServiceFailure>();
          check((failure as StartupServiceFailure).code).equals(StartupServiceFailureCode.uacCancelled);
        },
      );
    });

    test('should not elevate HKCU add when current-user auto-start write is denied', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(),
        ProcessResult(
          3,
          1,
          '',
          'ERROR: Access is denied.',
        ),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
      );
      final result = await service.enable();

      check(result.isError()).isTrue();
      check(calls.where((call) => call.executable == 'reg').length).equals(4);
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test(
      'should return explicit failure when UAC prompt is cancelled',
      () async {
        final results = Queue<ProcessResult>.from(<ProcessResult>[
          ..._queries(hklm: _querySuccess(_hklmRunKey, _startupValue(_currentExecutable))),
          ProcessResult(
            2,
            1,
            '',
            'ERROR: Access is denied.',
          ),
          ProcessResult(
            3,
            1,
            '',
            'The operation was canceled by the user.',
          ),
        ]);

        final service = _makeService(results: results);
        final result = await service.disable();

        check(result.isError()).isTrue();
        result.fold(
          (_) => fail('Expected failure when UAC is cancelled'),
          (failure) {
            check(failure).isA<StartupServiceFailure>();
            check((failure as StartupServiceFailure).code).equals(StartupServiceFailureCode.uacCancelled);
          },
        );
      },
    );

    test('should not request UAC when reg add succeeds immediately', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(),
        ProcessResult(
          3,
          0,
          '',
          '',
        ),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
      );
      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test('should repair enabled registry entry missing autostart argument', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(hkcu: _querySuccess(_hkcuRunKey, '"$_currentExecutable"')),
        ProcessResult(3, 0, '', ''),
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        ),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
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
      final results = Queue<ProcessResult>.from(
        _queries(hkcu: _querySuccess(_hkcuRunKey, '"$_currentExecutable"')),
      );

      final service = _makeService(
        calls: calls,
        results: results,
      );
      final result = await service.ensureLaunchConfiguration(
        allowElevation: false,
      );

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.needsRepair),
        (_) => fail('Expected success'),
      );
      check(calls.length).equals(3);
      check(calls.every((call) => call.arguments.contains('query'))).isTrue();
    });

    test('should not repair registry entry that already has autostart argument', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(
        _queries(hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable))),
      );

      final service = _makeService(
        calls: calls,
        results: results,
      );
      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.unchanged),
        (_) => fail('Expected success'),
      );
      check(calls.length).equals(3);
    });

    test('should repair registry entry when autostart argument is only a partial token', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, '"$_currentExecutable" "${LaunchArgsConstants.autostartArg}-extra"'),
        ),
        ProcessResult(3, 0, '', ''),
        ..._queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        ),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
      );
      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
    });

    test('should build startup diagnostic report with scope details', () async {
      final results = Queue<ProcessResult>.from(
        _queries(
          hkcu: _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
          hklm: _querySuccess(_hklmRunKey, _startupValue(_oldExecutable)),
        ),
      );

      final service = _makeService(results: results);
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
}) {
  return AutoStartService(
    isWindows: () => true,
    executablePathProvider: () => _currentExecutable,
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

List<ProcessResult> _queries({
  ProcessResult? hkcu,
  ProcessResult? hklm,
  ProcessResult? wow6432,
}) {
  return <ProcessResult>[
    hkcu ?? _queryNotFound(),
    hklm ?? _queryNotFound(),
    wow6432 ?? _queryNotFound(),
  ];
}

ProcessResult _querySuccess(String scopeKey, String valueData) {
  return ProcessResult(
    1,
    0,
    '''
$scopeKey
    Plug Agente    REG_SZ    $valueData
''',
    '',
  );
}

ProcessResult _queryNotFound() {
  return ProcessResult(
    1,
    1,
    '',
    'ERROR: The system was unable to find the specified registry key or value.',
  );
}

String _startupValue(String executablePath) {
  return '"$executablePath" "${LaunchArgsConstants.autostartArg}"';
}
