import 'package:result_dart/result_dart.dart';

abstract interface class IUpdateMaintenanceGate {
  bool get allowsInternalWork;
  Future<T> runValue<T>(Future<T> Function() action);
  Future<Result<T>> run<T extends Object>(Future<Result<T>> Function() action);
}
