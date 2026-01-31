import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:result_dart/result_dart.dart';

class CheckOdbcDriver {
  CheckOdbcDriver(this._driverChecker);
  final IOdbcDriverChecker _driverChecker;

  Future<Result<bool>> call(String driverName) async {
    if (driverName.trim().isEmpty) {
      return Failure(
        domain.ValidationFailure('Nome do driver não pode estar vazio'),
      );
    }

    return _driverChecker.checkDriverInstalled(driverName);
  }
}
