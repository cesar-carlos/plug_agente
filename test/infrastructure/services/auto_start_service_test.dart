import 'dart:collection';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
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

void main() {
  group('AutoStartService', () {
    test('should detect enabled startup entry in HKCU', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        _queryNotFound(),
      ]);

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
      check(calls.length).equals(2);
      check(calls[0].arguments).contains(_hkcuRunKey);
      check(calls[1].arguments).contains(_hklmRunKey);
    });

    test('should keep valid HKLM entry without creating duplicate HKCU entry', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _queryNotFound(),
        _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
      ]);

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
        _queryNotFound(),
        _queryNotFound(),
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
      check(addCall.arguments.join(' ')).contains(AppStrings.singleInstanceArgAutostart);
    });

    test('should report repair needed for duplicate HKCU and HKLM entries without elevation', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
      ]);

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
        _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        _querySuccess(_hklmRunKey, _startupValue(_currentExecutable)),
        ProcessResult(3, 0, '', ''),
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

    test('should repair stale executable path even when autostart argument exists', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _querySuccess(_hkcuRunKey, _startupValue(_oldExecutable)),
        _queryNotFound(),
        ProcessResult(3, 0, '', ''),
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
        ProcessResult(1, 0, '', ''),
        ProcessResult(2, 1, '', 'ERROR: Access is denied.'),
        ProcessResult(3, 0, '', ''),
      ]);

      final service = _makeService(
        calls: calls,
        results: results,
      );

      final result = await service.disable();

      check(result.isSuccess()).isTrue();
      check(calls.length).equals(3);
      check(calls[0].arguments).contains(_hkcuRunKey);
      check(calls[1].arguments).contains(_hklmRunKey);
      check(calls[2].executable).equals('powershell');
      check(calls[2].arguments.last).contains('-Verb RunAs');
    });

    test('should classify localized UAC cancellation with accents', () async {
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _queryNotFound(),
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
          check((failure as StartupServiceFailure).message).contains('UAC');
        },
      );
    });

    test('should not elevate HKCU add when current-user auto-start write is denied', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _queryNotFound(),
        _queryNotFound(),
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
      check(calls.length).equals(3);
      check(calls[2].executable).equals('reg');
      check(calls.any((call) => call.executable == 'powershell')).isFalse();
    });

    test(
      'should return explicit failure when UAC prompt is cancelled',
      () async {
        final results = Queue<ProcessResult>.from(<ProcessResult>[
          _queryNotFound(),
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
            check((failure as StartupServiceFailure).message).contains(
              'UAC',
            );
          },
        );
      },
    );

    test('should not request UAC when reg add succeeds immediately', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _queryNotFound(),
        _queryNotFound(),
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
      check(calls.length).equals(3);
      check(calls.last.executable).equals('reg');
    });

    test('should repair enabled registry entry missing autostart argument', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _querySuccess(_hkcuRunKey, '"$_currentExecutable"'),
        _queryNotFound(),
        ProcessResult(3, 0, '', ''),
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
      check(calls.length).equals(3);
      check(calls[0].arguments).contains('query');
      check(calls[1].arguments).contains('query');
      check(calls[2].arguments).contains('add');
      check(calls[2].arguments.join(' ')).contains(AppStrings.singleInstanceArgAutostart);
    });

    test('should report repair needed without UAC when validation forbids elevation', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _querySuccess(_hkcuRunKey, '"$_currentExecutable"'),
        _queryNotFound(),
      ]);

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
      check(calls.length).equals(2);
      check(calls.every((call) => call.arguments.contains('query'))).isTrue();
    });

    test('should not repair registry entry that already has autostart argument', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _querySuccess(_hkcuRunKey, _startupValue(_currentExecutable)),
        _queryNotFound(),
      ]);

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
      check(calls.length).equals(2);
      check(calls.every((call) => call.arguments.contains('query'))).isTrue();
    });

    test('should repair registry entry when autostart argument is only a partial token', () async {
      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        _querySuccess(_hkcuRunKey, '"$_currentExecutable" "${AppStrings.singleInstanceArgAutostart}-extra"'),
        _queryNotFound(),
        ProcessResult(3, 0, '', ''),
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
      check(calls.length).equals(3);
      check(calls[2].arguments).contains('add');
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
  return '"$executablePath" "${AppStrings.singleInstanceArgAutostart}"';
}
