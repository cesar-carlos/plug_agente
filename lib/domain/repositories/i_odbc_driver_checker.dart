import 'package:result_dart/result_dart.dart';

abstract class IOdbcDriverChecker {
  Future<Result<bool>> checkDriverInstalled(String driverName);
}
