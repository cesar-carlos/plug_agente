import 'package:result_dart/result_dart.dart';

abstract class INotificationService {
  Future<Result<void>> initialize();
  Future<Result<void>> show({required String title, required String body, String? payload});
  Future<Result<void>> schedule({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  });
  Future<Result<void>> cancel(int id);
  Future<Result<void>> cancelAll();
}
