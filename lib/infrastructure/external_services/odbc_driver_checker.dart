import 'dart:io';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:result_dart/result_dart.dart';

class OdbcDriverChecker implements IOdbcDriverChecker {
  @override
  Future<Result<bool>> checkDriverInstalled(String driverName) async {
    if (driverName.trim().isEmpty) {
      return Failure(
        domain.ValidationFailure('Nome do driver não pode estar vazio'),
      );
    }

    try {
      final result = await Process.run('powershell', [
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
    } on Exception catch (e) {
      return Failure(
        domain.ConfigurationFailure('Erro ao verificar driver ODBC: $e'),
      );
    }
  }
}
