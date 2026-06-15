import 'package:plug_agente/domain/errors/failures.dart' as domain;

/// Fail-closed helpers when Windows secure storage is unavailable.
abstract final class SecureStorageGuard {
  static const String unavailableReason = 'secure_storage_unavailable';

  static domain.ConfigurationFailure unavailableFailure({
    required String operation,
    String? store,
  }) {
    return domain.ConfigurationFailure.withContext(
      message: 'Secure storage is unavailable; secrets cannot be persisted safely',
      context: <String, dynamic>{
        'secure_storage': true,
        'reason': unavailableReason,
        'operation': operation,
        'store': ?store,
      },
    );
  }

  static void ensureAvailable({
    required bool isAvailable,
    required String operation,
    String? store,
  }) {
    if (!isAvailable) {
      throw unavailableFailure(operation: operation, store: store);
    }
  }
}
