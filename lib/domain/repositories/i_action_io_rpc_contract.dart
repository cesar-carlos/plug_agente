import 'package:result_dart/result_dart.dart';

abstract interface class IActionIoRpcContract {
  Result<Unit> validateParams(String method, Object? params);
  Result<Unit> validateResult(String method, Object? result);
}
