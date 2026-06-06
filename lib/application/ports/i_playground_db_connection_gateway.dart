import 'package:result_dart/result_dart.dart';

abstract class IPlaygroundDbConnectionGateway {
  Future<Result<bool>> testConnection(String connectionString);

  void syncConnectionIndicator(bool connected);
}
