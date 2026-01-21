import 'package:result_dart/result_dart.dart';

import '../../domain/repositories/i_odbc_driver_checker.dart';
import '../../domain/errors/failures.dart' as domain;

class CheckOdbcDriver {
  final IOdbcDriverChecker _driverChecker;

  CheckOdbcDriver(this._driverChecker);

  Future<Result<bool>> call(String driverName) async {
    if (driverName.trim().isEmpty) {
      return Failure(domain.ValidationFailure('Nome do driver não pode estar vazio'));
    }

    return await _driverChecker.checkDriverInstalled(driverName);
  }
}
