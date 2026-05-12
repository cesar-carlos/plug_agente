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

void main() {
  group('AutoStartService', () {
    test('should request UAC when reg add fails with access denied', () async {
      if (!Platform.isWindows) {
        return;
      }

      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ProcessResult(
          1,
          1,
          '',
          'ERROR: Access is denied.',
        ),
        ProcessResult(
          2,
          0,
          '',
          '',
        ),
      ]);

      Future<ProcessResult> processRunner(
        String executable,
        List<String> arguments,
      ) async {
        calls.add(
          _ProcessInvocation(
            executable: executable,
            arguments: arguments,
          ),
        );
        return results.removeFirst();
      }

      final service = AutoStartService(processRunner: processRunner);
      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(calls.length).equals(2);
      check(calls[0].executable).equals('reg');
      check(calls[1].executable).equals('powershell');
      check(calls[1].arguments.last).contains('-Verb RunAs');
    });

    test(
      'should return explicit failure when UAC prompt is cancelled',
      () async {
        if (!Platform.isWindows) {
          return;
        }

        final results = Queue<ProcessResult>.from(<ProcessResult>[
          ProcessResult(
            1,
            1,
            '',
            'ERROR: Access is denied.',
          ),
          ProcessResult(
            2,
            1,
            '',
            'The operation was canceled by the user.',
          ),
        ]);

        Future<ProcessResult> processRunner(
          String executable,
          List<String> arguments,
        ) async {
          return results.removeFirst();
        }

        final service = AutoStartService(processRunner: processRunner);
        final result = await service.enable();

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
      if (!Platform.isWindows) {
        return;
      }

      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ProcessResult(
          1,
          0,
          '',
          '',
        ),
      ]);

      Future<ProcessResult> processRunner(
        String executable,
        List<String> arguments,
      ) async {
        calls.add(
          _ProcessInvocation(
            executable: executable,
            arguments: arguments,
          ),
        );
        return results.removeFirst();
      }

      final service = AutoStartService(processRunner: processRunner);
      final result = await service.enable();

      check(result.isSuccess()).isTrue();
      check(calls.length).equals(1);
      check(calls.single.executable).equals('reg');
    });

    test('should repair enabled registry entry missing autostart argument', () async {
      if (!Platform.isWindows) {
        return;
      }

      final calls = <_ProcessInvocation>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ProcessResult(
          1,
          0,
          r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run Plug Agente REG_SZ "C:\Program Files\PlugAgente\plug_agente.exe"',
          '',
        ),
        ProcessResult(
          2,
          0,
          '',
          '',
        ),
      ]);

      Future<ProcessResult> processRunner(
        String executable,
        List<String> arguments,
      ) async {
        calls.add(
          _ProcessInvocation(
            executable: executable,
            arguments: arguments,
          ),
        );
        return results.removeFirst();
      }

      final service = AutoStartService(processRunner: processRunner);
      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.repaired),
        (_) => fail('Expected success'),
      );
      check(calls.length).equals(2);
      check(calls[0].arguments).contains('query');
      check(calls[1].arguments).contains('add');
      check(calls[1].arguments.join(' ')).contains(AppStrings.singleInstanceArgAutostart);
    });

    test('should not repair registry entry that already has autostart argument', () async {
      if (!Platform.isWindows) {
        return;
      }

      final calls = <_ProcessInvocation>[];

      Future<ProcessResult> processRunner(
        String executable,
        List<String> arguments,
      ) async {
        calls.add(
          _ProcessInvocation(
            executable: executable,
            arguments: arguments,
          ),
        );
        return ProcessResult(
          1,
          0,
          'Plug Agente REG_SZ "plug_agente.exe" "${AppStrings.singleInstanceArgAutostart}"',
          '',
        );
      }

      final service = AutoStartService(processRunner: processRunner);
      final result = await service.ensureLaunchConfiguration();

      check(result.isSuccess()).isTrue();
      result.fold(
        (status) => check(status).equals(StartupLaunchConfigurationStatus.unchanged),
        (_) => fail('Expected success'),
      );
      check(calls.length).equals(1);
      check(calls.single.arguments).contains('query');
    });
  });
}
