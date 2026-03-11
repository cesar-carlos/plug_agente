import 'package:result_dart/result_dart.dart';

abstract interface class IStartupService {
  Future<Result<bool>> isEnabled();

  Future<Result<Unit>> enable();

  Future<Result<Unit>> disable();

  Future<Result<Unit>> openSystemSettings();
}
