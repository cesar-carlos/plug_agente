import 'package:result_dart/result_dart.dart';

import '../entities/config.dart';

abstract class IAgentConfigRepository {
  Future<Result<Config>> getById(String id);
  Future<Result<List<Config>>> getAll();
  Future<Result<Config>> save(Config config);
  Future<Result<void>> delete(String id);

  // Returns the current config. If no config exists, returns NotFoundFailure.
  // This avoids using nullable types which result_dart doesn't support.
  Future<Result<Config>> getCurrentConfig();
}
