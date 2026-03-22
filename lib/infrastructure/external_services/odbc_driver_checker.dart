import 'dart:io';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:result_dart/result_dart.dart';

typedef OdbcDriverCheckerProcessRun =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

class OdbcDriverChecker implements IOdbcDriverChecker {
  OdbcDriverChecker({OdbcDriverCheckerProcessRun? processRun}) : _processRun = processRun ?? Process.run;

  final OdbcDriverCheckerProcessRun _processRun;

  @override
  Future<Result<bool>> checkDriverInstalled(String driverName) async {
    if (driverName.trim().isEmpty) {
      return Failure(
        domain.ValidationFailure('Nome do driver não pode estar vazio'),
      );
    }

    try {
      final result = await _processRun('powershell', [
        '-Command',
        'Get-OdbcDriver | Select-Object -ExpandProperty Name',
      ], runInShell: true);

      if (result.exitCode != 0) {
        return Failure(
          domain.ConfigurationFailure(
            'Erro ao listar drivers ODBC: ${result.stderr}',
          ),
        );
      }

      final output = result.stdout.toString().toLowerCase();
      final driverNameLower = driverName.trim().toLowerCase();

      final isInstalled = output.contains(driverNameLower);

      return Success(isInstalled);
    } on ProcessException {
      return Failure(
        domain.ConfigurationFailure(
          'Não foi possível executar PowerShell para verificar drivers ODBC.',
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Erro ao verificar driver ODBC',
          cause: error,
          context: {
            'operation': 'checkDriverInstalled',
            'driverName': driverName,
          },
        ),
      );
    }
  }
}
