import 'package:plug_agente/domain/entities/config.dart';

/// Short-TTL cache for config resolution on SQL hot paths.
abstract interface class IActiveConfigQueryCache {
  Future<Config?> resolveForDatabaseAccess({String? configId});

  void invalidate();
}
