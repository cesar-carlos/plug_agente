import 'package:result_dart/result_dart.dart';

abstract class IAutoUpdateOrchestrator {
  bool get isAvailable;

  Future<void> initialize();

  Future<void> checkInBackground();

  Future<Result<bool>> checkManual();
}
